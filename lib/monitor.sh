#!/bin/sh
# Monitor mode: follow live.log of a running claudeloop instance

# Monitor mode: follow .claudeloop/live.log of a running claudeloop instance
run_monitor() {
  trap 'printf "\n"; exit 0' INT TERM
  trap - EXIT   # don't run cleanup — monitor never owns the lock

  local _live_log=".claudeloop/live.log"
  local _max_wait="${_MONITOR_WAIT_TIMEOUT:-30}"
  local _wait=0

  while [ ! -f "$_live_log" ]; do
    if [ "$_wait" -ge "$_max_wait" ]; then
      print_error "No live log found in .claudeloop/ after ${_max_wait}s"
      printf 'Start claudeloop first: claudeloop --plan PLAN.md\n'
      exit 1
    fi
    printf 'Waiting for claudeloop to start...\r'
    sleep 1
    _wait=$((_wait + 1))
  done

  local _running=false _lock_pid=""
  if [ -f "$LOCK_FILE" ]; then
    _lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
    [ -n "$_lock_pid" ] && kill -0 "$_lock_pid" 2>/dev/null && _running=true
  fi

  printf '\n'
  if [ "$_running" = true ]; then
    printf '%b● RUNNING%b  PID: %s  |  Plan: %s\n' \
      "$COLOR_GREEN" "$COLOR_RESET" "$_lock_pid" "$PLAN_FILE"
  else
    printf '%b○ COMPLETED%b  Plan: %s\n' \
      "$COLOR_YELLOW" "$COLOR_RESET" "$PLAN_FILE"
  fi
  printf 'Following .claudeloop/live.log — Ctrl+C to stop\n\n'

  _colorizer='
    {
      line = $0
      if      (line ~ /✗/)                { print "\033[0;31m" line "\033[0m" }
      else if (line ~ /✓/)                { print "\033[0;32m" line "\033[0m" }
      else if (line ~ /[⚠⏸]/)            { print "\033[1;33m" line "\033[0m" }
      else if (line ~ /▶ Executing Phase/) { print "\033[0;34m" line "\033[0m" }
      else if (line ~ /─/)                { print "\033[0;34m" line "\033[0m" }
      else if (line ~ /Attempt [0-9]/)    { print "\033[1;33m" line "\033[0m" }
      else if (line ~ /\[Tasks:/ || line ~ /\[Todos:/) { print "\033[0;32m" line "\033[0m" }
      else {
        gsub(/\[Tool: [^]]*\]/, "\033[0;36m&\033[0m", line)
        gsub(/\[Result \[error\][^]]*\]/, "\033[0;31m&\033[0m", line)
        gsub(/\[Rate limit: [^]]*\]/, "\033[1;33m&\033[0m", line)
        gsub(/\[Warning: [^]]*\]/, "\033[1;33m&\033[0m", line)
        print line
      }
      fflush()
    }
  '

  if [ -n "${_MONITOR_NO_FOLLOW:-}" ]; then
    tail -n 20 "$_live_log" 2>/dev/null | awk "$_colorizer" || true
    return 0
  fi

  tail -F "$_live_log" 2>/dev/null | awk "$_colorizer"
}
