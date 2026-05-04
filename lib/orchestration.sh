#!/bin/sh

# Orchestration functions for claudeloop main flow
# Handles config precedence, AI parsing, progress initialization, and phase overrides

# Handle orphan recovery when detect_orphan_logs signals _ORPHAN_RECOVERY_ACTION=recover.
# Switches to ai-parsed-plan.md, re-parses, and recovers progress from logs.
handle_orphan_recovery() {
  [ "${_ORPHAN_RECOVERY_ACTION:-}" = "recover" ] || return 0

  log_ts "Switching plan to .claudeloop/ai-parsed-plan.md"
  PLAN_FILE=".claudeloop/ai-parsed-plan.md"
  parse_plan "$PLAN_FILE"
  printf '[%s] Re-parsed: %s phases\n' "$(date '+%H:%M:%S')" "$PHASE_COUNT"

  if [ -f "$PROGRESS_FILE" ]; then
    cp "$PROGRESS_FILE" "${PROGRESS_FILE}.bak"
    printf '[%s] Backed up progress to %s\n' "$(date '+%H:%M:%S')" "${PROGRESS_FILE}.bak"
  fi

  recover_progress_from_logs ".claudeloop" "$PROGRESS_FILE" "$PLAN_FILE"

  # Persist recovered PLAN_FILE to config
  update_conf_key ".claudeloop/.claudeloop.conf" PLAN_FILE "$PLAN_FILE"

  # Prompt user to verify runtime settings
  if [ -t 0 ] && [ "$YES_MODE" = "false" ]; then
    run_config_wizard
    # Persist any changes
    update_conf_key ".claudeloop/.claudeloop.conf" MAX_RETRIES "$MAX_RETRIES"
    update_conf_key ".claudeloop/.claudeloop.conf" SKIP_PERMISSIONS "$SKIP_PERMISSIONS"
    update_conf_key ".claudeloop/.claudeloop.conf" VERIFY_PHASES "$VERIFY_PHASES"
    update_conf_key ".claudeloop/.claudeloop.conf" REFACTOR_PHASES "$REFACTOR_PHASES"
  else
    log_ts "Non-interactive: review .claudeloop/.claudeloop.conf to verify settings"
  fi

  _PLAN_HAD_CHANGES=""
}

# Apply config file → env var → CLI argument precedence chain
apply_config_precedence() {
  load_config
  # Fallback: if no conf exists, load defaults from most recent archive
  if [ ! -f ".claudeloop/.claudeloop.conf" ]; then
    load_config_from_latest_archive
    # If PLAN_FILE loaded from archive points to a missing .claudeloop/ file,
    # reset to default so AI parsing re-triggers or wizard asks
    case "${PLAN_FILE:-}" in
      .claudeloop/*)
        [ -f "$PLAN_FILE" ] || PLAN_FILE="PLAN.md"
        ;;
    esac
  fi

  # Apply env var overrides (env vars take priority over config file)
  [ -n "$_CL_PLAN_FILE" ]              && PLAN_FILE="$_CL_PLAN_FILE"
  [ -n "$_CL_PROGRESS_FILE" ]          && PROGRESS_FILE="$_CL_PROGRESS_FILE"
  [ -n "$_CL_MAX_RETRIES" ]            && MAX_RETRIES="$_CL_MAX_RETRIES"
  [ -n "$_CL_BASE_DELAY" ]             && BASE_DELAY="$_CL_BASE_DELAY"
  [ -n "$_CL_SIMPLE_MODE" ]            && SIMPLE_MODE="$_CL_SIMPLE_MODE"
  [ -n "$_CL_PHASE_PROMPT_FILE" ]      && PHASE_PROMPT_FILE="$_CL_PHASE_PROMPT_FILE"
  [ -n "$_CL_QUOTA_RETRY_INTERVAL" ]   && QUOTA_RETRY_INTERVAL="$_CL_QUOTA_RETRY_INTERVAL"
  [ -n "$_CL_SKIP_PERMISSIONS" ]       && SKIP_PERMISSIONS="$_CL_SKIP_PERMISSIONS"
  [ -n "$_CL_STREAM_TRUNCATE_LEN" ]    && STREAM_TRUNCATE_LEN="$_CL_STREAM_TRUNCATE_LEN"
  [ -n "$_CL_MAX_PHASE_TIME" ]         && MAX_PHASE_TIME="$_CL_MAX_PHASE_TIME"
  [ -n "$_CL_IDLE_TIMEOUT" ]           && IDLE_TIMEOUT="$_CL_IDLE_TIMEOUT"
  [ -n "$_CL_VERIFY_TIMEOUT" ]         && VERIFY_TIMEOUT="$_CL_VERIFY_TIMEOUT"
  [ -n "$_CL_VERIFY_IDLE_TIMEOUT" ]    && VERIFY_IDLE_TIMEOUT="$_CL_VERIFY_IDLE_TIMEOUT"
  [ -n "$_CL_DEAD_TIMEOUT" ]           && DEAD_TIMEOUT="$_CL_DEAD_TIMEOUT"
  [ -n "$_CL_VERIFY_PHASES" ]          && VERIFY_PHASES="$_CL_VERIFY_PHASES"
  [ -n "$_CL_REFACTOR_PHASES" ]        && REFACTOR_PHASES="$_CL_REFACTOR_PHASES"
  [ -n "$_CL_REFACTOR_MAX_RETRIES" ]   && REFACTOR_MAX_RETRIES="$_CL_REFACTOR_MAX_RETRIES"
  [ -n "$_CL_PROVIDER" ]               && PROVIDER="$_CL_PROVIDER"

  # Parse CLI arguments (CLI takes priority over everything)
  parse_args "$@"

  # Validate granularity
  case "$GRANULARITY" in phases|tasks|steps) ;;
    *) print_error "Invalid granularity: $GRANULARITY (must be phases, tasks, or steps)"; exit 1 ;; esac

  # Auto-enable non-interactive mode when running inside Claude Code
  if [ -n "${CLAUDECODE:-}" ] && [ "$YES_MODE" = "false" ]; then
    print_warning "Running inside Claude Code — enabling non-interactive mode (--yes)."
    YES_MODE=true
  fi
}

# Initialize or rotate the live log file
init_live_log() {
  if [ -z "${LIVE_LOG:-}" ] && { ! $DRY_RUN || [ "$AI_PARSE" = "true" ]; }; then
    LIVE_LOG=".claudeloop/live.log"
    mkdir -p "$(dirname "$LIVE_LOG")"
    if [ "$AI_PARSE_FEEDBACK" = "true" ]; then
      # Feedback mode: append to existing log (don't archive)
      touch "$LIVE_LOG"
    elif [ -f "$LIVE_LOG" ]; then
      _ts=$(date '+%Y%m%d-%H%M%S')
      mv "$LIVE_LOG" ".claudeloop/live-${_ts}.log"
      : > "$LIVE_LOG"
    else
      : > "$LIVE_LOG"
    fi
  fi
}

# AI parsing: generate structured plan from free-form input
# Sets: PLAN_FILE, _parse_msg
run_ai_parsing() {
  _parse_msg="Parsing plan file"

  # --ai-parse-feedback implies AI parsing — no AI_PARSE guard needed
  # --ai-parse-feedback: reparse with feedback and exit
  if [ "$AI_PARSE_FEEDBACK" = "true" ]; then
    ai_parse_feedback "$PLAN_FILE" "$GRANULARITY"
    exit $?
  fi

  # --no-retry: single-pass parse+verify and exit
  if [ "$NO_RETRY" = "true" ] && [ "$AI_PARSE" = "true" ]; then
    ai_parse_no_retry "$PLAN_FILE" "$GRANULARITY"
    exit $?
  fi

  # In dry-run, only AI-parse if explicitly requested via --ai-parse CLI flag
  if [ "$AI_PARSE" = "true" ] && { ! $DRY_RUN || [ -n "$_CLI_AI_PARSE" ]; }; then
    local ai_plan=".claudeloop/ai-parsed-plan.md"
    if [ -f "$ai_plan" ] && [ -f "$PROGRESS_FILE" ] && [ "$YES_MODE" != "true" ] && [ -t 0 ]; then
      # If all phases completed and not resetting, skip re-parse prompt —
      # the archive prompt in main() will handle the completed-run flow
      _sc=$(grep -c "^Status: " "$PROGRESS_FILE" 2>/dev/null) || _sc=0
      if [ "$_sc" -gt 0 ] && ! $RESET_PROGRESS \
         && ! grep "^Status: " "$PROGRESS_FILE" | grep -qv "^Status: completed"; then
        PLAN_FILE="$ai_plan"
        _parse_msg="Using cached plan"
      else
        print_warning "AI-parsed plan already exists. Re-parsing will invalidate progress."
        printf 'Re-parse? (y/N) '
        read -r _ans
        case "$_ans" in [yY]*) ;; *) PLAN_FILE="$ai_plan"; _parse_msg="Using cached plan" ;; esac
      fi
    fi
    if [ "$PLAN_FILE" != "$ai_plan" ] || [ ! -f "$ai_plan" ]; then
      if ! ai_parse_and_verify "$PLAN_FILE" "$GRANULARITY"; then
        print_error "AI parsing failed"
        exit 1
      fi
      if ! confirm_ai_plan "$ai_plan"; then
        print_error "AI plan rejected"
        exit 1
      fi
    fi
    PLAN_FILE="$ai_plan"
    # Persist resolved plan file so subsequent runs use it
    if ! $DRY_RUN; then
      update_conf_key ".claudeloop/.claudeloop.conf" PLAN_FILE "$PLAN_FILE"
    fi
  fi
}

# Initialize progress, detect plan changes, handle orphan recovery
init_and_recover_progress() {
  # Check for interrupted session (skip in dry-run and reset)
  if ! $DRY_RUN && ! $RESET_PROGRESS; then
    load_state || true
  fi

  # Recover progress from logs if requested
  if [ "$RECOVER_PROGRESS" = "true" ]; then
    if [ -f "$PROGRESS_FILE" ]; then
      cp "$PROGRESS_FILE" "${PROGRESS_FILE}.bak"
      printf '[%s] Backed up existing progress to %s\n' "$(date '+%H:%M:%S')" "${PROGRESS_FILE}.bak"
    fi
    recover_progress_from_logs ".claudeloop" "$PROGRESS_FILE" "$PLAN_FILE"
  fi

  # Initialize progress (files already cleaned by clean_claudeloop_dir if --reset)
  init_progress "$PROGRESS_FILE"

  # Detect and reconcile plan changes (no-op on fresh/reset runs)
  if ! $DRY_RUN && ! $RESET_PROGRESS; then
    detect_plan_changes "$PROGRESS_FILE"
  fi

  # Detect orphan logs (only when detect_plan_changes did NOT find changes)
  if ! $DRY_RUN && ! $RESET_PROGRESS && [ "$RECOVER_PROGRESS" != "true" ] \
     && [ "$_PLAN_HAD_CHANGES" != "true" ]; then
    detect_orphan_logs ".claudeloop" || exit 1
    handle_orphan_recovery
  fi

  # Create lock file (before --phase/--mark-complete so re-init after force-kill is correct)
  if ! $DRY_RUN; then
    create_lock

    # If we force-killed an existing instance, re-read progress to get its final state
    if [ "$FORCE_KILLED" = "true" ]; then
      init_progress "$PROGRESS_FILE"
      if ! $RESET_PROGRESS; then
        detect_plan_changes "$PROGRESS_FILE"
      fi
      # Detect orphan logs after force-kill re-read
      if ! $RESET_PROGRESS && [ "$RECOVER_PROGRESS" != "true" ] \
         && [ "$_PLAN_HAD_CHANGES" != "true" ]; then
        detect_orphan_logs ".claudeloop" || exit 1
        handle_orphan_recovery
      fi
    fi
  fi
}

# Apply --phase N and --mark-complete N overrides
apply_phase_overrides() {
  # Apply --phase N: mark phases before START_PHASE as completed (skip them)
  if [ -n "$START_PHASE" ]; then
    # Validate that START_PHASE exists in the plan
    _phase_found=false
    for _p in $PHASE_NUMBERS; do
      if [ "$_p" = "$START_PHASE" ]; then
        _phase_found=true
        break
      fi
    done
    if [ "$_phase_found" = false ]; then
      print_error "Phase $START_PHASE not found in plan (available: $PHASE_NUMBERS)"
      exit 1
    fi
    for _p in $PHASE_NUMBERS; do
      phase_less_than "$_p" "$START_PHASE" || break
      phase_set STATUS "$_p" "completed"
    done
    # Reset START_PHASE and all subsequent phases to pending
    _past_start=false
    for _p in $PHASE_NUMBERS; do
      if [ "$_p" = "$START_PHASE" ]; then _past_start=true; fi
      if [ "$_past_start" = true ]; then
        reset_phase_full "$_p"
      fi
    done
    # Persist immediately so Ctrl+C before first phase doesn't lose the reset
    if ! $DRY_RUN; then
      write_progress "$PROGRESS_FILE" "$PLAN_FILE"
    fi
    log_verbose "main: skipped phases before $START_PHASE (marked completed)"
  fi

  # Apply --mark-complete N: override status of a specific phase to completed
  if [ -n "$MARK_COMPLETE_PHASE" ]; then
    _mc_title=$(get_phase_title "$MARK_COMPLETE_PHASE")
    if [ -z "$_mc_title" ]; then
      print_error "Phase $MARK_COMPLETE_PHASE not found in plan"
      exit 1
    fi
    update_phase_status "$MARK_COMPLETE_PHASE" "completed"
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"
    print_success "Marked phase $MARK_COMPLETE_PHASE as completed"
  fi
}
