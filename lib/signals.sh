#!/bin/sh
# Signal handling: interrupt, cleanup, terminal restoration

# Restore terminal ISIG flag (Ctrl+C → SIGINT generation).
# Claude CLI may disable ISIG via setRawMode (Node.js cfmakeraw) — this re-enables it.
# No-op when not connected to a terminal (pipes, CI).
_restore_isig() {
  stty isig 2>/dev/null < /dev/tty || true
}

# Re-arm INT/TERM trap after set +m.
# Defensive: bash 3.2 may reset signal disposition when toggling job control.
_safe_disable_jobctl() {
  set +m
  trap handle_interrupt INT TERM
}

# Signal handler for graceful shutdown
handle_interrupt() {
  set +e          # bash 3.2 does not exempt trap handlers from set -e
  _restore_isig   # re-enable Ctrl+C in case Claude CLI disabled ISIG
  # Close FIFO write end before kill — prevents blocking on readerless FIFO
  exec 7>&- 2>/dev/null || true
  # Kill running claude pipeline immediately with SIGTERM → SIGKILL escalation (1s timeout)
  if [ -n "${CURRENT_PIPELINE_PID:-}" ]; then
    _kill_pipeline_escalate "${CURRENT_PIPELINE_PID}" "${CURRENT_PIPELINE_PGID:-}" 1
    CURRENT_PIPELINE_PID=""
    CURRENT_PIPELINE_PGID=""
  fi
  INTERRUPTED=true
  echo ""
  print_warning "Interrupt received (Ctrl+C)"
  print_warning "Saving state and shutting down gracefully..."
  log_verbose "handle_interrupt: CURRENT_PHASE=$CURRENT_PHASE"

  # Note: refactor state is persisted in PROGRESS.md — resume_pending_refactors handles recovery
  if [ -n "${_REFACTORING_PHASE:-}" ]; then
    print_warning "Refactoring of Phase $_REFACTORING_PHASE interrupted (will resume on restart)"
    _REFACTORING_PHASE=""
  fi

  # Mark current phase as pending if it was in progress
  if [ -n "$CURRENT_PHASE" ]; then
    local _status
    _status=$(get_phase_status "$CURRENT_PHASE")
    if [ "$_status" = "in_progress" ]; then
      print_warning "Marking Phase $CURRENT_PHASE as pending for retry"
      reset_phase_for_retry "$CURRENT_PHASE"
    fi
  fi

  # Save progress (only after progress has been fully loaded from disk)
  if [ "${_PROGRESS_LOADED:-}" = "true" ]; then
    write_progress "$PROGRESS_FILE" "$PLAN_FILE" "skip_recorder"
    # Fork recorder as detached background process (reads from disk)
    # trap '' HUP: prevent SIGHUP on macOS where /bin/sh is zsh
    if command -v generate_replay >/dev/null 2>&1; then
      ( trap '' HUP; generate_replay "$(dirname "$PROGRESS_FILE")" ) </dev/null >/dev/null 2>&1 &
    fi
  fi

  # Save state for resume
  save_state

  # Cleanup
  remove_lock

  echo ""
  print_success "State saved successfully"
  print_success "Resume with: $0 --continue"
  exit 130
}

# Cleanup on exit
cleanup() {
  remove_lock
  if [ "$INTERRUPTED" = false ]; then
    clear_state
  fi
}
