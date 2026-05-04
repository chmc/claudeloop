#!/bin/sh
# Main execution loop: phase orchestration with retry/backoff

# Main execution loop
main_loop() {
  local continue_execution=true
  local _net_retries=0
  local _overload_retries=0
  local _server_retries=0

  while $continue_execution; do
    # Check for interruption
    if $INTERRUPTED; then
      print_warning "Execution interrupted"
      return 130
    fi

    # Find next runnable phase
    local next_phase
    log_verbose "main_loop: finding next runnable phase"
    if ! next_phase=$(find_next_phase); then
      # No runnable phases - check why
      local has_pending=false
      local has_failed=false

      for _ml_phase in $PHASE_NUMBERS; do
        local _status
        _status=$(get_phase_status "$_ml_phase")
        if [ "$_status" = "pending" ]; then
          has_pending=true
        fi
        if [ "$_status" = "failed" ]; then
          has_failed=true
        fi
      done

      if ! $has_pending && ! $has_failed; then
        # All phases completed
        print_success "All phases completed!"
        return 0
      elif $has_pending; then
        print_error "Remaining phases are blocked by dependencies"
        return 1
      else
        print_error "Some phases failed and no more phases can run"
        return 1
      fi
    fi

    log_verbose "main_loop: next runnable phase is $next_phase"

    # Execute the next phase
    if execute_phase "$next_phase"; then
      log_verbose "main_loop: phase $next_phase succeeded, continuing"
      _net_retries=0
      _overload_retries=0
      _server_retries=0
      # Success - continue to next phase
      continue
    else
      local _log_file _raw_file
      _log_file=".claudeloop/logs/phase-${next_phase}.log"
      _raw_file=".claudeloop/logs/phase-${next_phase}.raw.json"
      if is_overload_error "$_log_file" "$_raw_file"; then
        _overload_retries=$((_overload_retries + 1))
        reset_phase_for_retry "$next_phase"
        # Exponential backoff: 5, 10, 20, 40, 80, 120, 120... (cap 120s)
        local _ol_delay=0
        if [ "${BASE_DELAY:-5}" -gt 0 ]; then
          _ol_delay=$((5 * (1 << (_overload_retries - 1))))
          [ "$_ol_delay" -gt 120 ] && _ol_delay=120
        fi
        log_verbose "main_loop: overload error on phase $next_phase (retry $_overload_retries), waiting ${_ol_delay}s"
        write_progress "$PROGRESS_FILE" "$PLAN_FILE"
        print_overload_wait "$next_phase" "$_overload_retries" "$_ol_delay"
        sleep "$_ol_delay"
        if [ "$_overload_retries" -ge 20 ]; then
          if [ -t 0 ] && [ "$YES_MODE" != "true" ]; then
            printf 'API overloaded for an extended period. Press Enter to keep retrying or Ctrl+C to exit: '
            read -r _dummy 2>/dev/null || return 1
            _overload_retries=0
          fi
        fi
        continue
      fi
      if is_server_error "$_log_file" "$_raw_file" || is_timeout_error "$_log_file"; then
        _server_retries=$((_server_retries + 1))
        reset_phase_for_retry "$next_phase"
        # Exponential backoff: 5, 10, 20, 40, 80, 160, 300, 300... (cap 300s)
        local _sv_delay=0
        if [ "${BASE_DELAY:-5}" -gt 0 ]; then
          _sv_delay=$((5 * (1 << (_server_retries - 1))))
          [ "$_sv_delay" -gt 300 ] && _sv_delay=300
        fi
        log_verbose "main_loop: server/timeout error on phase $next_phase (retry $_server_retries), waiting ${_sv_delay}s"
        write_progress "$PROGRESS_FILE" "$PLAN_FILE"
        print_server_error_wait "$next_phase" "$_server_retries" "$_sv_delay"
        sleep "$_sv_delay"
        if [ "$_server_retries" -ge 20 ]; then
          if [ -t 0 ] && [ "$YES_MODE" != "true" ]; then
            printf 'API server errors for an extended period. Press Enter to keep retrying or Ctrl+C to exit: '
            read -r _dummy 2>/dev/null || return 1
            _server_retries=0
          fi
        fi
        continue
      fi
      if is_rate_limit_error "$_log_file"; then
        # Rate-limit/quota error: restore attempt counter (same pattern as handle_interrupt)
        reset_phase_for_retry "$next_phase"
        log_verbose "main_loop: rate-limit error on phase $next_phase, attempts restored"
        write_progress "$PROGRESS_FILE" "$PLAN_FILE"
        print_quota_wait "$next_phase" "$QUOTA_RETRY_INTERVAL"
        sleep "$QUOTA_RETRY_INTERVAL"
        continue
      fi
      if is_network_error "$_log_file"; then
        _net_retries=$((_net_retries + 1))
        reset_phase_for_retry "$next_phase"
        # Exponential backoff: 5, 10, 20, 40, 80, 160, 300, 300... (0 when BASE_DELAY=0)
        local _net_delay=0
        if [ "${BASE_DELAY:-5}" -gt 0 ]; then
          _net_delay=$((5 * (1 << (_net_retries - 1))))
          [ "$_net_delay" -gt 300 ] && _net_delay=300
        fi
        log_verbose "main_loop: network error on phase $next_phase (retry $_net_retries), waiting ${_net_delay}s"
        write_progress "$PROGRESS_FILE" "$PLAN_FILE"
        print_network_wait "$next_phase" "$_net_retries" "$_net_delay"
        sleep "$_net_delay"
        # Cap: after 20 retries, prompt user (or fail in non-interactive mode)
        if [ "$_net_retries" -ge 20 ]; then
          if [ -t 0 ] && [ "$YES_MODE" != "true" ]; then
            printf 'Network unavailable for an extended period. Press Enter to keep retrying or Ctrl+C to exit: '
            read -r _dummy 2>/dev/null || return 1
            _net_retries=0
          fi
        fi
        continue
      fi
      if is_empty_log "$_log_file"; then
        print_error "Phase $next_phase: Claude produced no output (empty log). Check the claude CLI."
        if ! [ -t 0 ] || [ "$YES_MODE" = "true" ]; then
          return 1
        else
          printf 'Press Enter to retry phase %s once the issue is resolved, or Ctrl+C to abort: ' "$next_phase"
          read -r _dummy 2>/dev/null || return 1
        fi
        reset_phase_for_retry "$next_phase"
        write_progress "$PROGRESS_FILE" "$PLAN_FILE"
        continue
      fi
      if is_permission_error "$_log_file"; then
        print_error "Phase $next_phase: Claude requested write permissions."
        print_warning "Grant the permission in the Claude UI (or re-run with --dangerously-skip-permissions)."
        if ! [ -t 0 ] || [ "$YES_MODE" = "true" ]; then
          return 1
        else
          printf 'Press Enter to retry phase %s, or Ctrl+C to abort: ' "$next_phase"
          read -r _dummy 2>/dev/null || return 1
        fi
        reset_phase_for_retry "$next_phase"
        write_progress "$PROGRESS_FILE" "$PLAN_FILE"
        continue
      fi
      if is_auth_error "$_log_file"; then
        print_error "Phase $next_phase: authentication error — check your API key or session."
        print_error "This is a permanent error — retrying will not help."
        return 1
      fi
      # Normal error: existing retry logic (unchanged)
      if should_retry_phase "$next_phase"; then
        local _attempts _fail_reason _consec
        _attempts=$(get_phase_attempts "$next_phase")
        _fail_reason=$(get_phase_fail_reason "$next_phase")
        _consec=$(get_phase_consec_fail "$next_phase")

        # Diagnostic warning at exactly 5 consecutive model-behavior failures
        case "$_fail_reason" in
          trapped_tool_calls|no_write_actions|empty_log)
            if [ "$_consec" -eq 5 ]; then
              print_warning "Phase $next_phase: 5 consecutive model-behavior failures. The model may not support tool_use properly. Consider using --model to try a different model."
            fi ;;
        esac

        # Zero backoff for model-behavior failures (waiting won't help)
        local delay
        case "$_fail_reason" in
          trapped_tool_calls|no_write_actions|empty_log) delay=0 ;;
          *) delay=$(calculate_backoff "$_attempts") ;;
        esac
        log_verbose "main_loop: scheduling retry of phase $next_phase in ${delay}s (attempt $_attempts)"
        if [ "$delay" -gt 0 ]; then
          print_warning "Retrying phase $next_phase after $delay seconds..."
          sleep "$delay"
        else
          print_warning "Retrying phase $next_phase immediately (model-behavior failure)..."
        fi
        continue
      else
        print_error "Phase $next_phase failed after ${MAX_RETRIES} attempts"
        lessons_write_final_failure "$next_phase"
        return 1
      fi
    fi
  done
}
