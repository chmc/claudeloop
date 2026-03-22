#!/bin/sh

# Phase Execution Pipeline Library
# Handles phase execution, Claude CLI pipeline, result evaluation, and verification.
# Prompt building (capture_git_context, build_default_prompt, apply_retry_strategy)
# lives in lib/prompt.sh.

# Update fail reason and track consecutive same-reason failures
# Args: $1 - phase number, $2 - new fail reason
update_fail_reason() {
  local _ufr_phase="$1" _ufr_reason="$2"
  local _prev_reason _prev_consec
  _prev_reason=$(get_phase_fail_reason "$_ufr_phase")
  _prev_consec=$(get_phase_consec_fail "$_ufr_phase")
  phase_set FAIL_REASON "$_ufr_phase" "$_ufr_reason"
  # Also persist per-attempt for replay
  local _ufr_attempt
  _ufr_attempt=$(get_phase_attempts "$_ufr_phase")
  [ -n "$_ufr_attempt" ] && phase_set ATTEMPT_FAIL_REASON "$_ufr_phase" "$_ufr_reason" "$_ufr_attempt"
  if [ "$_ufr_reason" = "$_prev_reason" ]; then
    phase_set CONSEC_FAIL "$_ufr_phase" "$((_prev_consec + 1))"
  else
    phase_set CONSEC_FAIL "$_ufr_phase" "1"
  fi
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
  _sentinel_polls=0
  _sentinel_max=${_SENTINEL_MAX_WAIT:-1800}
  _sentinel_interval=${_SENTINEL_POLL:-1}
  while [ ! -f "$_sentinel" ]; do
    sleep "$_sentinel_interval"
    _sentinel_polls=$((_sentinel_polls + 1))
    # Use awk for float-safe comparison (_sentinel_interval may be 0.1 in tests)
    if awk "BEGIN{exit !(${_sentinel_polls} * ${_sentinel_interval} >= ${_sentinel_max})}" 2>/dev/null; then
      log_verbose "run_claude_pipeline: sentinel poll timeout after ${_sentinel_max}s"
      break
    fi
  done

  # Wait for Claude CLI to write exit code (avoids race with stream processor exit)
  _ec_wait=0
  _ec_max=${_EXIT_CODE_WAIT:-5}
  while [ ! -s "$_exit_tmp" ] && [ "$_ec_wait" -lt "$_ec_max" ]; do
    sleep 1
    _ec_wait=$((_ec_wait + 1))
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
    update_fail_reason "$_epr_phase" "empty_log"
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
      # Allow no-change completion if signal file exists AND Claude had a real session
      if has_signal_file "$_epr_phase" && has_successful_session "$_epr_log"; then
        log_verbose "execute_phase: phase $_epr_phase has no-changes signal file with successful session — accepting"
        print_success "Phase $_epr_phase completed (no code changes needed — signal file present)"
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
      if has_trapped_tool_calls "$_epr_raw"; then
        update_fail_reason "$_epr_phase" "trapped_tool_calls"
        log_verbose "execute_phase: phase $_epr_phase has tool calls trapped in thinking blocks"
        print_warning "Phase $_epr_phase: Tool calls trapped in thinking blocks — treating as failed"
      else
        update_fail_reason "$_epr_phase" "no_write_actions"
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
    update_fail_reason "$_epr_phase" "no_session"
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
      update_fail_reason "$_rav_phase" "verification_failed"
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
  mkdir -p ".claudeloop/signals"
  rm -f ".claudeloop/signals/phase-${phase_num}.md"
  log_verbose "execute_phase: phase=$phase_num title=$title"

  # Update status
  update_phase_status "$phase_num" "in_progress"
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"

  attempt=$(get_phase_attempts "$phase_num")
  # Compute and persist per-attempt strategy for replay
  local _ep_strategy="standard"
  if [ "$attempt" -gt 1 ]; then
    local _ep_fail_reason _ep_consec
    _ep_fail_reason=$(get_phase_fail_reason "$phase_num")
    _ep_consec=$(get_phase_consec_fail "$phase_num")
    _ep_strategy=$(retry_strategy "$attempt" "$MAX_RETRIES")
    _ep_strategy=$(escalate_strategy "$_ep_strategy" "$_ep_fail_reason" "$_ep_consec")
  fi
  phase_set ATTEMPT_STRATEGY "$phase_num" "$_ep_strategy" "$attempt"
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

  # Reset raw log so has_write_actions() only sees events from this attempt
  : > "$raw_log"

  # Capture pre-execution SHA for rollback on network failure
  local _pre_exec_sha=""
  _pre_exec_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

  # Run Claude pipeline
  run_claude_pipeline "$prompt" "$phase_num" "$log_file" "$raw_log"
  local claude_exit="$_LAST_CLAUDE_EXIT"

  # Write metadata footer
  duration=$(( $(date '+%s') - start_ts ))
  printf '=== EXECUTION END exit_code=%s duration=%ss time=%s ===\n' \
    "$claude_exit" "$duration" "$(date '+%Y-%m-%dT%H:%M:%S')" >> "$log_file"

  # Archive per-attempt raw.json for replay (before rotation/overwrite)
  cp "$raw_log" ".claudeloop/logs/phase-${phase_num}.attempt-${attempt}.raw.json"

  # Rotate log and evaluate result
  rotate_phase_log "$log_file" "$phase_num"
  if ! evaluate_phase_result "$phase_num" "$claude_exit" "$attempt" "$log_file" "$raw_log"; then
    # Rollback partial edits on failure if Claude made write actions
    # Only reset tracked files outside .claudeloop/ (infrastructure files are not Claude's edits)
    # Don't use git clean (would remove untracked files like test state)
    if [ -n "$_pre_exec_sha" ] && has_write_actions "$raw_log"; then
      local _dirty_files
      _dirty_files=$(git diff --name-only 2>/dev/null | grep -v '^\.claudeloop/' || true)
      if [ -n "$_dirty_files" ]; then
        log_verbose "execute_phase: rolling back partial edits to $_pre_exec_sha"
        echo "$_dirty_files" | xargs git checkout "$_pre_exec_sha" -- 2>/dev/null || true
      fi
    fi
    return 1
  fi
}
