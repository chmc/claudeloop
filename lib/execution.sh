#!/bin/sh

# Phase Execution Pipeline Library
# Handles phase execution, Claude CLI pipeline, retry strategies, and result evaluation

# Capture current git state for prompt context injection
# Returns: git context string on stdout (empty if no git info)
capture_git_context() {
  local _git_stat _git_log_lines
  _git_stat=$(git diff --stat 2>/dev/null)
  _git_log_lines=$(git log --oneline -3 2>/dev/null)
  if [ -n "$_git_stat" ] || [ -n "$_git_log_lines" ]; then
    printf '\n## Current Git State\n'
    [ -n "$_git_log_lines" ] && printf 'Recent commits:\n%s\n' "$_git_log_lines"
    [ -n "$_git_stat" ] && printf 'Uncommitted changes:\n%s\n' "$_git_stat"
  fi
}

# Build default prompt for a phase (when no custom prompt template is used)
# Args: $1 - phase_num, $2 - title, $3 - description, $4 - git_context
# Returns: prompt string on stdout
build_default_prompt() {
  local _bdp_phase="$1" _bdp_title="$2" _bdp_desc="$3" _bdp_git="$4"
  printf '%s' "You are executing Phase $_bdp_phase of a multi-phase plan.

## Phase $_bdp_phase: $_bdp_title

$_bdp_desc

## Context
- This is a fresh Claude instance dedicated to this phase only
- Previous phases have been completed and committed to git
- Even if prior work for this phase exists in git, you MUST complete every subtask listed in the description above — do not assume the phase is done
- Review recent git history and existing code before implementing
- When done, ensure all changes are tested and working
- Commit your changes when complete
${_bdp_git}
## Task
Implement the above phase completely. Make sure to:
1. Read relevant existing code
2. Implement required changes
3. Test your implementation thoroughly
4. Commit your changes when complete"
}

# Apply retry strategy: archive log, build retry context, optionally replace prompt
# Args: $1 - phase_num, $2 - attempt, $3 - title, $4 - description,
#        $5 - git_context, $6 - log_file, $7 - current prompt
# Returns: modified prompt on stdout
apply_retry_strategy() {
  local _ars_phase="$1" _ars_attempt="$2" _ars_title="$3" _ars_desc="$4"
  local _ars_git="$5" _ars_log="$6" _ars_prompt="$7"
  local _fail_reason _strategy _prev_verify_log _retry_ctx

  _fail_reason=$(get_phase_fail_reason "$_ars_phase")
  _strategy=$(retry_strategy "$_ars_attempt" "$MAX_RETRIES")

  # Archive previous attempt log
  if [ -f "$_ars_log" ]; then
    cp "$_ars_log" "${_ars_log%.log}.attempt-$((_ars_attempt - 1)).log"
  fi

  _prev_verify_log=".claudeloop/logs/phase-$_ars_phase.verify.log"
  [ -f "$_prev_verify_log" ] || _prev_verify_log=""

  # For stripped/targeted strategies, replace the base prompt with a simpler one
  if [ "$_strategy" = "stripped" ] && [ -z "$PHASE_PROMPT_FILE" ]; then
    _ars_prompt="You are a fresh instance. Previous phases are done.

## Phase $_ars_phase: $_ars_title

$_ars_desc
${_ars_git}"
  elif [ "$_strategy" = "targeted" ] && [ -z "$PHASE_PROMPT_FILE" ]; then
    _ars_prompt="## Phase $_ars_phase: $_ars_title
${_ars_git}"
  fi

  # Build and inject retry context
  _retry_ctx=$(build_retry_context "$_strategy" "$_ars_attempt" "$MAX_RETRIES" "$_fail_reason" "$_ars_log" "$_prev_verify_log")
  if [ -n "$_retry_ctx" ]; then
    _ars_prompt="${_ars_prompt}

${_retry_ctx}"
  fi

  printf '%s' "$_ars_prompt"
}

# Run Claude CLI pipeline (backgrounded for interruptibility and timeout)
# Args: $1 - prompt, $2 - phase_num, $3 - log_file, $4 - raw_log
# Sets: _LAST_CLAUDE_EXIT (global), CURRENT_PIPELINE_PID, CURRENT_PIPELINE_PGID
# WARNING: Pure cut-paste extraction. Do not refactor internals — contains set -m/+m,
#          PGID-based cleanup, sentinel polling, and macOS bash 3.2 workarounds.
run_claude_pipeline() {
  local _rcp_prompt="$1" _rcp_phase="$2" _rcp_log="$3" _rcp_raw="$4"
  local _exit_tmp _claude_debug_flag
  _exit_tmp=$(mktemp)
  _claude_debug_flag=""
  if [ "$VERBOSE_MODE" = "true" ]; then
    _claude_debug_flag="--debug-file .claudeloop/logs/phase-$_rcp_phase.claude.debug"
  fi
  log_ts "Executing Claude CLI..."
  CURRENT_PIPELINE_PID=""
  CURRENT_PIPELINE_PGID=""

  # Sentinel file: created when stream processor (AWK) exits.
  # We poll for this instead of using `wait PID` because bash 3.2 (macOS /bin/sh)
  # with set -m makes `wait PID` block for the entire pipeline job, not just the
  # specified process — causing a deadlock when Claude CLI lingers after AWK exits.
  local _sentinel
  _sentinel=$(mktemp)
  rm -f "$_sentinel"

  # Use job control (set -m) so the background pipeline gets its own process group.
  # This lets the timer (and handle_interrupt) kill the entire pipeline by PGID,
  # not just the last process. Without set -m, kill -TERM $! only kills the last
  # process; with set -m, kill -TERM -- -$PGID kills every process in the job.
  set -m
  {
    _rc=0
    unset CLAUDECODE   # strip Claude Code marker — nested claude invocations require it unset
    if [ "$SKIP_PERMISSIONS" = "true" ]; then
      # shellcheck disable=SC2086
      printf '%s\n' "$_rcp_prompt" | claude --print --dangerously-skip-permissions \
        --output-format=stream-json --verbose --include-partial-messages \
        $_claude_debug_flag 2>&1 || _rc=$?
    else
      # shellcheck disable=SC2086
      printf '%s\n' "$_rcp_prompt" | claude --print \
        --output-format=stream-json --verbose --include-partial-messages \
        $_claude_debug_flag 2>&1 || _rc=$?
    fi
    printf '%s\n' "$_rc" > "$_exit_tmp"
  } | inject_heartbeats | { process_stream_json "$_rcp_log" "$_rcp_raw" "$HOOKS_ENABLED" "${LIVE_LOG:-}" "${SIMPLE_MODE:-false}" "${IDLE_TIMEOUT:-0}"; : > "$_sentinel"; } &
  CURRENT_PIPELINE_PID=$!
  # With set -m the pipeline's PGID = PID of the first process (jobs -p shows it)
  CURRENT_PIPELINE_PGID=$(jobs -p 2>/dev/null | tr -d '[:space:]')
  set +m

  # Phase timeout: kill entire pipeline PGID after MAX_PHASE_TIME seconds (0 = disabled)
  local _timer_pid _pl_pid _pl_pgid
  _timer_pid=""
  _pl_pid="$CURRENT_PIPELINE_PID"
  _pl_pgid="$CURRENT_PIPELINE_PGID"
  if [ "$MAX_PHASE_TIME" -gt 0 ] 2>/dev/null; then
    # Use set -m so the timer subshell gets its own process group (PGID=PID).
    # This lets us kill -TERM -- -$_timer_pid to kill both the subshell and
    # its `sleep` child, preventing orphaned sleep processes from holding open
    # bats (or other tool) internal file descriptors.
    set -m
    ( sleep "$MAX_PHASE_TIME" && kill -TERM -- "-${_pl_pgid}" 2>/dev/null && : > "$_sentinel" ) >/dev/null 2>&1 &
    _timer_pid=$!
    set +m
  fi

  # Wait for stream processor to finish (sentinel-based).
  # Note: bash 3.2's `wait PID` with set -m blocks for the entire pipeline job,
  # not just the specified process. The sentinel avoids this deadlock.
  while [ ! -f "$_sentinel" ]; do
    sleep "${_SENTINEL_POLL:-1}"
  done

  # Stream processor done — kill remaining pipeline processes (Claude CLI may linger)
  if [ -n "$CURRENT_PIPELINE_PGID" ] && [ "${CURRENT_PIPELINE_PGID:-0}" -gt 1 ]; then
    kill -TERM -- "-$CURRENT_PIPELINE_PGID" 2>/dev/null || true
  fi
  wait "$CURRENT_PIPELINE_PID" 2>/dev/null || true
  rm -f "$_sentinel"
  # Clear spinner remnants and show cursor
  printf '\r%-12s\r' '' >/dev/stderr
  CURRENT_PIPELINE_PID=""
  CURRENT_PIPELINE_PGID=""

  # Cancel timer if phase completed before timeout
  if [ -n "$_timer_pid" ]; then
    kill -- "-$_timer_pid" 2>/dev/null || true  # kill whole process group (subshell + sleep child)
    wait "$_timer_pid" 2>/dev/null || true
    _timer_pid=""
  fi

  _LAST_CLAUDE_EXIT=1
  if [ -f "$_exit_tmp" ]; then
    _LAST_CLAUDE_EXIT=$(cat "$_exit_tmp")
    rm -f "$_exit_tmp"
  fi
  case "$_LAST_CLAUDE_EXIT" in ''|*[!0-9]*) _LAST_CLAUDE_EXIT=1 ;; esac
}

# Rotate phase log to keep size manageable
# Args: $1 - log_file, $2 - phase_num
rotate_phase_log() {
  local _rpl_log="$1" _rpl_phase="$2"
  local response_header_lines response_lines total_lines
  response_header_lines=$(grep -n '^=== RESPONSE ===$' "$_rpl_log" | head -1 | cut -d: -f1)
  if [ -n "$response_header_lines" ]; then
    total_lines=$(wc -l < "$_rpl_log")
    response_lines=$((total_lines - response_header_lines))
    if [ "$response_lines" -gt 500 ]; then
      header=$(head -n "$response_header_lines" "$_rpl_log")
      tail_content=$(tail -n 500 "$_rpl_log")
      printf '%s\n%s\n' "$header" "$tail_content" > "${_rpl_log}.tmp" && mv "${_rpl_log}.tmp" "$_rpl_log"
      log_verbose "execute_phase: rotated log for phase $_rpl_phase ($response_lines → 500 response lines)"
    fi
  else
    # Old-format log: fall back to original rotation
    line_count=$(wc -l < "$_rpl_log")
    if [ "$line_count" -gt 500 ]; then
      tail -n 500 "$_rpl_log" > "${_rpl_log}.tmp" && mv "${_rpl_log}.tmp" "$_rpl_log"
      log_verbose "execute_phase: rotated log for phase $_rpl_phase ($line_count → 500 lines)"
    fi
  fi
}

# Evaluate phase result: check exit code, log quality, and determine pass/fail
# Args: $1 - phase_num, $2 - claude_exit, $3 - attempt, $4 - log_file, $5 - raw_log
# Returns: 0 on success (phase completed), 1 on failure
evaluate_phase_result() {
  local _epr_phase="$1" _epr_exit="$2" _epr_attempt="$3" _epr_log="$4" _epr_raw="$5"

  # Empty log means Claude produced no output — always a failure
  if is_empty_log "$_epr_log"; then
    phase_set FAIL_REASON "$_epr_phase" "empty_log"
    print_error "Phase $_epr_phase: Claude produced no output (empty log)."
    update_phase_status "$_epr_phase" "failed"
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"
    CURRENT_PHASE=""
    return 1
  fi

  if [ "$_epr_exit" -eq 0 ]; then
    if is_permission_error "$_epr_log"; then
      log_verbose "execute_phase: phase $_epr_phase exited 0 but requested permissions"
      print_error "Phase $_epr_phase: Claude requested write permissions but none were granted."
      print_error "Re-run with --dangerously-skip-permissions to bypass permission prompts."
      update_phase_status "$_epr_phase" "failed"
      write_progress "$PROGRESS_FILE" "$PLAN_FILE"
      CURRENT_PHASE=""
      return 1
    fi

    # Safety: check that Claude made write actions (not just reads)
    if ! has_write_actions "$_epr_raw"; then
      if has_trapped_tool_calls "$_epr_raw"; then
        phase_set FAIL_REASON "$_epr_phase" "trapped_tool_calls"
        log_verbose "execute_phase: phase $_epr_phase has tool calls trapped in thinking blocks"
        print_warning "Phase $_epr_phase: Tool calls trapped in thinking blocks — treating as failed"
      else
        phase_set FAIL_REASON "$_epr_phase" "no_write_actions"
        log_verbose "execute_phase: phase $_epr_phase exited 0 but no write actions in raw log"
        print_warning "Phase $_epr_phase: Claude exited successfully but made no changes — treating as failed"
      fi
      update_phase_status "$_epr_phase" "failed"
      write_progress "$PROGRESS_FILE" "$PLAN_FILE"
      CURRENT_PHASE=""
      return 1
    fi

    log_verbose "execute_phase: phase $_epr_phase succeeded"
    if ! run_adaptive_verification "$_epr_phase" "$_epr_attempt" "$_epr_log"; then
      return 1
    fi
    print_success "Phase $_epr_phase completed successfully"
    update_phase_status "$_epr_phase" "completed"
    auto_commit_changes "$_epr_phase" "auto-commit after phase completion"
    if [ "$REFACTOR_PHASES" = "true" ]; then
      phase_set REFACTOR_STATUS "$_epr_phase" "pending"
    fi
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"
    CURRENT_PHASE=""
    run_refactor_if_needed "$_epr_phase"
    return 0
  else
    if has_successful_session "$_epr_log"; then
      log_verbose "execute_phase: phase $_epr_phase exited non-zero ($_epr_exit) but successful session detected"
      if ! run_adaptive_verification "$_epr_phase" "$_epr_attempt" "$_epr_log"; then
        return 1
      fi
      print_warning "Phase $_epr_phase: Claude exited with code $_epr_exit but a successful session was detected — treating as completed."
      update_phase_status "$_epr_phase" "completed"
      auto_commit_changes "$_epr_phase" "auto-commit after phase completion"
      if [ "$REFACTOR_PHASES" = "true" ]; then
        phase_set REFACTOR_STATUS "$_epr_phase" "pending"
      fi
      write_progress "$PROGRESS_FILE" "$PLAN_FILE"
      CURRENT_PHASE=""
      run_refactor_if_needed "$_epr_phase"
      return 0
    fi
    phase_set FAIL_REASON "$_epr_phase" "no_session"
    log_verbose "execute_phase: phase $_epr_phase failed"
    print_error "Phase $_epr_phase failed"
    update_phase_status "$_epr_phase" "failed"
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"
    CURRENT_PHASE=""
    return 1
  fi
}

# Run adaptive verification based on retry tier (full/quick/skip)
# Args: $1 - phase number, $2 - attempt number, $3 - log file path
# Returns: 0 if verification passes (or skipped), 1 on failure
run_adaptive_verification() {
  local _rav_phase="$1" _rav_attempt="$2" _rav_log="$3"
  local _vmode
  _vmode=$(verify_mode "$_rav_attempt" "$MAX_RETRIES")
  if [ "$_vmode" = "full" ]; then
    if ! verify_phase "$_rav_phase" "$_rav_log"; then
      phase_set FAIL_REASON "$_rav_phase" "verification_failed"
      print_error "Phase $_rav_phase: verification failed"
      update_phase_status "$_rav_phase" "failed"
      write_progress "$PROGRESS_FILE" "$PLAN_FILE"
      CURRENT_PHASE=""
      return 1
    fi
  elif [ "$_vmode" = "quick" ]; then
    log_verbose "execute_phase: quick verification (skipping verify agent, attempt $_rav_attempt)"
  fi
  # skip mode: no verification at all
  return 0
}

# Execute a single phase
execute_phase() {
  local phase_num="$1"
  local title description log_file raw_log start_ts duration attempt
  title=$(get_phase_title "$phase_num")
  description=$(get_phase_description "$phase_num")
  log_file=".claudeloop/logs/phase-$phase_num.log"
  raw_log=".claudeloop/logs/phase-$phase_num.raw.json"

  # Set current phase for interrupt handler
  CURRENT_PHASE="$phase_num"
  mkdir -p ".claudeloop/logs"
  log_verbose "execute_phase: phase=$phase_num title=$title"

  # Update status
  update_phase_status "$phase_num" "in_progress"
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"

  attempt=$(get_phase_attempts "$phase_num")
  start_ts=$(date '+%s')
  print_phase_exec_header "$phase_num"

  # Build prompt
  local _git_context prompt
  _git_context=$(capture_git_context)

  if [ -n "$PHASE_PROMPT_FILE" ]; then
    if ! prompt=$(build_phase_prompt "$PHASE_PROMPT_FILE" "$phase_num" "$title" "$description" "$PLAN_FILE"); then
      print_error "Failed to build prompt from template: $PHASE_PROMPT_FILE"
      return 1
    fi
    [ -n "$_git_context" ] && prompt="${prompt}
${_git_context}"
  else
    prompt=$(build_default_prompt "$phase_num" "$title" "$description" "$_git_context")
  fi

  # Apply retry strategy on subsequent attempts
  if [ "$attempt" -gt 1 ]; then
    prompt=$(apply_retry_strategy "$phase_num" "$attempt" "$title" "$description" "$_git_context" "$log_file" "$prompt")
  fi

  # Write metadata + prompt header to log
  {
    printf '=== EXECUTION START phase=%s attempt=%s time=%s ===\n' \
      "$phase_num" "$attempt" "$(date '+%Y-%m-%dT%H:%M:%S')"
    printf '=== PROMPT ===\n'
    printf '%s\n' "$prompt"
    printf '=== RESPONSE ===\n'
  } > "$log_file"

  # Run Claude pipeline
  run_claude_pipeline "$prompt" "$phase_num" "$log_file" "$raw_log"
  local claude_exit="$_LAST_CLAUDE_EXIT"

  # Write metadata footer
  duration=$(( $(date '+%s') - start_ts ))
  printf '=== EXECUTION END exit_code=%s duration=%ss time=%s ===\n' \
    "$claude_exit" "$duration" "$(date '+%Y-%m-%dT%H:%M:%S')" >> "$log_file"

  # Rotate log and evaluate result
  rotate_phase_log "$log_file" "$phase_num"
  evaluate_phase_result "$phase_num" "$claude_exit" "$attempt" "$log_file" "$raw_log"
}
