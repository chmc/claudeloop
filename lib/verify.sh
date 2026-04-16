#!/bin/sh

# Phase Verification Library
# Runs a read-only Claude instance to verify phase completion.
# Verdict-based: requires explicit VERIFICATION_PASSED keyword + tool_use JSON events.

# Fallback definitions when sourced outside claudeloop (e.g. tests)
command -v _restore_isig >/dev/null 2>&1 || _restore_isig() { stty isig 2>/dev/null < /dev/tty || true; }
command -v _safe_disable_jobctl >/dev/null 2>&1 || _safe_disable_jobctl() { set +m; }
command -v _kill_pipeline_escalate >/dev/null 2>&1 || _kill_pipeline_escalate() {
  [ -n "${1:-}" ] || return 0
  local _kpe_pid="$1" _kpe_pgid="${2:-}" _kpe_timeout="${3:-${_KILL_ESCALATE_TIMEOUT:-3}}" _kpe_wait=0
  if [ -n "$_kpe_pgid" ] && [ "${_kpe_pgid:-0}" -gt 1 ]; then kill -TERM -- "-$_kpe_pgid" 2>/dev/null || true
  else kill -TERM "$_kpe_pid" 2>/dev/null || true; fi
  while [ "$_kpe_wait" -lt "$_kpe_timeout" ] && kill -0 "$_kpe_pid" 2>/dev/null; do sleep 1; _kpe_wait=$((_kpe_wait + 1)); done
  if kill -0 "$_kpe_pid" 2>/dev/null; then
    if [ -n "$_kpe_pgid" ] && [ "${_kpe_pgid:-0}" -gt 1 ]; then kill -KILL -- "-$_kpe_pgid" 2>/dev/null || true
    else kill -KILL "$_kpe_pid" 2>/dev/null || true; fi
  fi
  wait "$_kpe_pid" 2>/dev/null || true
}

# verify_phase(phase_num, log_file)
# Returns 0 if verification passes (or VERIFY_PHASES is disabled), 1 on failure.
verify_phase() {
  local phase_num="$1" log_file="$2"

  [ "$VERIFY_PHASES" = "true" ] || return 0

  local title description
  title=$(get_phase_title "$phase_num")
  description=$(get_phase_description "$phase_num")

  print_substep_header "🔍" "Verifying phase $phase_num..."

  # Extract tail of execution log for context
  local exec_tail=""
  if [ -f "$log_file" ]; then
    exec_tail=$(awk '
      /^=== RESPONSE ===$/ { found=1; next }
      /^=== EXECUTION END/ { exit }
      found { print }
    ' "$log_file" | tail -n 80)
  fi

  # Build verification prompt
  local prompt
  prompt="You are a verification agent. Your job is to independently verify that a phase was completed correctly. You are READ-ONLY — do NOT fix anything, only report.

## Phase $phase_num: $title

$description

## Execution Log (tail)

\`\`\`
${exec_tail}
\`\`\`

## Mandatory Verification Steps

You MUST actually execute commands. Do NOT skip testing. Do NOT assume. Run them and show output.

1. Run \`git diff HEAD~1\` (or appropriate range) to review what changed
2. Run the test suite if one exists (e.g. \`npm test\`, \`pytest\`, \`go test\`, \`bats\`, etc.)
3. Run linters if configured (e.g. \`eslint\`, \`shellcheck\`, \`flake8\`, etc.)
4. Check for errors, suspicious code, or incomplete work

If no test suite exists, focus on reviewing the git diff for correctness and obvious errors.

## Verdict (MANDATORY — you MUST output one)

After completing ALL steps, your FINAL line of output MUST be exactly one of:
  VERIFICATION_PASSED
  VERIFICATION_FAILED
WARNING: Omitting the verdict causes automatic failure. Do not end without it."

  # Prepare verify log files
  local verify_log=".claudeloop/logs/phase-$phase_num.verify.log"
  local verify_formatted_log=".claudeloop/logs/phase-$phase_num.verify.formatted.log"
  mkdir -p ".claudeloop/logs"
  : > "$verify_log"
  : > "$verify_formatted_log"

  # Run claude piped through process_stream_json (same pattern as execute_phase)
  local _exit_tmp
  _exit_tmp=$(mktemp)

  # Create named pipe for bidirectional stdio protocol
  local _verify_fifo
  _verify_fifo=$(mktemp -u).fifo
  mkfifo "$_verify_fifo"

  # Build prompt as stream-json message
  local _prompt_json
  _prompt_json=$(_build_stream_message "$prompt")

  # Sentinel file: created when stream processor (AWK) exits.
  local _sentinel
  _sentinel=$(mktemp)
  rm -f "$_sentinel"

  # Save terminal settings (Claude CLI may corrupt them via setRawMode/cfmakeraw)
  local _saved_stty=""
  _saved_stty=$(stty -g 2>/dev/null < /dev/tty) || true

  # Open FIFO in read-write mode — avoids blocking that happens with
  # write-only open when no reader exists yet. All pipeline stages inherit FD 7.
  # permission_filter writes control_responses to FD 7, which claude reads via stdin.
  exec 7<>"$_verify_fifo"

  set -m
  {
    _rc=0
    claude --input-format stream-json --output-format stream-json \
      --permission-prompt-tool stdio --verbose --include-partial-messages \
      < "$_verify_fifo" 7>&- 2>&1 || _rc=$?
    printf '%s\n' "$_rc" > "$_exit_tmp"
  } | permission_filter | inject_heartbeats 7>&- | { process_stream_json "$verify_formatted_log" "$verify_log" \
      "false" "${LIVE_LOG:-}" "${SIMPLE_MODE:-false}" "${VERIFY_IDLE_TIMEOUT:-120}" 7>&-; : > "$_sentinel"; } &
  CURRENT_PIPELINE_PID=$!
  CURRENT_PIPELINE_PGID=$(jobs -p 2>/dev/null | tr -d '[:space:]')
  _safe_disable_jobctl

  # Write prompt AFTER pipeline launch to avoid FIFO buffer deadlock (macOS 8KB limit).
  printf '%s\n' "$_prompt_json" >&7

  # Timeout: default 300s for verification (configurable via VERIFY_TIMEOUT)
  local _timer_pid _vp_pid _vp_pgid _verify_timeout
  _timer_pid=""
  _vp_pid="$CURRENT_PIPELINE_PID"
  _vp_pgid="$CURRENT_PIPELINE_PGID"
  _verify_timeout="${VERIFY_TIMEOUT:-300}"
  set -m
  ( sleep "$_verify_timeout" && kill -TERM -- "-${_vp_pgid}" 2>/dev/null; : > "$_sentinel" ) >/dev/null 2>&1 &
  _timer_pid=$!
  _safe_disable_jobctl

  # Wait for stream processor to finish (sentinel-based, same as execute_phase)
  _sentinel_polls=0
  _sentinel_max=$((_verify_timeout + 60))
  _sentinel_interval=${_SENTINEL_POLL:-1}
  # Pre-compute max polls as integer to avoid awk fork per iteration
  _sentinel_max_polls=$(awk "BEGIN{printf \"%d\", ${_sentinel_max} / ${_sentinel_interval}}" 2>/dev/null || echo 999999)
  while [ ! -f "$_sentinel" ]; do
    _restore_isig  # Re-enable Ctrl+C (Claude CLI may disable ISIG via raw mode)
    sleep "$_sentinel_interval"
    _sentinel_polls=$((_sentinel_polls + 1))
    if [ "$_sentinel_polls" -ge "${_sentinel_max_polls:-999999}" ]; then
      log_verbose "verify_phase: sentinel poll timeout after ${_sentinel_max}s"
      break
    fi
  done

  # Diagnostic: detect FD corruption (FD 1 pointing to FIFO instead of terminal)
  if command -v lsof >/dev/null 2>&1; then
    _fd1_type=$(lsof -p $$ -a -d 1 -F t 2>/dev/null | grep '^t' | head -1)
    case "$_fd1_type" in *FIFO*)
      log_verbose "verify_phase: WARNING — FD 1 corrupted to FIFO (pid=$$)"
    ;; esac
  fi

  # Close FIFO write end before kill/wait — reduces FIFO reference count and
  # prevents blocking on a readerless FIFO during cleanup
  exec 7>&- 2>/dev/null || true

  # Stream processor done — kill remaining pipeline processes (SIGTERM → SIGKILL escalation).
  _kill_pipeline_escalate "$CURRENT_PIPELINE_PID" "$CURRENT_PIPELINE_PGID"
  rm -f "$_sentinel"
  rm -f "$_verify_fifo"
  # Clear spinner remnants on current line (panel already cleaned by deactivate_panel)
  printf '\r%-12s\r' '' >/dev/stderr
  CURRENT_PIPELINE_PID=""
  CURRENT_PIPELINE_PGID=""

  # Restore terminal settings if Claude CLI corrupted them
  if [ -n "$_saved_stty" ]; then
    stty "$_saved_stty" 2>/dev/null < /dev/tty || true
  fi

  # Cancel timer
  if [ -n "$_timer_pid" ]; then
    kill -- "-$_timer_pid" 2>/dev/null || true
    wait "$_timer_pid" 2>/dev/null || true
    _timer_pid=""
  fi

  # Read exit code with guard against empty/non-numeric values
  local verify_exit=1
  if [ -f "$_exit_tmp" ]; then
    verify_exit=$(cat "$_exit_tmp")
    rm -f "$_exit_tmp"
  fi
  case "$verify_exit" in ''|*[!0-9]*) verify_exit=1 ;; esac

  check_verdict "$verify_log" "$phase_num" "Verification" "$verify_exit"
}

# check_verdict(log_file, phase_num, context_label, exit_code)
# Reusable verdict checker for verification and refactor-verification.
# Returns 0 (pass) or 1 (fail).
check_verdict() {
  local _cv_log="$1" _cv_phase="$2" _cv_label="$3" _cv_exit="$4"

  # Exit code check FIRST — but tolerate pipeline race condition
  if [ "$_cv_exit" -ne 0 ]; then
    if grep -q '"type":"result"' "$_cv_log" 2>/dev/null; then
      log_ts "$_cv_label: exit code $_cv_exit but result event found — treating as pipeline race"
    else
      print_error "$_cv_label failed for phase $_cv_phase (exit code $_cv_exit)"
      return 1
    fi
  fi

  # Verdict check 1: VERIFICATION_FAILED takes priority (even if PASSED also appears)
  if grep -q 'VERIFICATION_FAILED' "$_cv_log" 2>/dev/null; then
    print_error "$_cv_label failed for phase $_cv_phase: VERIFICATION_FAILED"
    return 1
  fi

  # Verdict check 2: tool calls were actually made (JSON-aware anti-skip)
  if ! grep -q '"type":"tool_use"' "$_cv_log" 2>/dev/null; then
    print_error "$_cv_label failed for phase $_cv_phase: no tool calls detected"
    return 1
  fi

  # Verdict check 3: explicit VERIFICATION_PASSED verdict required
  if ! grep -q 'VERIFICATION_PASSED' "$_cv_log" 2>/dev/null; then
    print_error "$_cv_label failed for phase $_cv_phase: no VERIFICATION_PASSED verdict"
    return 1
  fi

  print_success "$_cv_label passed for phase $_cv_phase"
  return 0
}
