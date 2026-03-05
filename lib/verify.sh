#!/bin/sh

# Phase Verification Library
# Runs a read-only Claude instance to verify phase completion.
# Verdict-based: requires explicit VERIFICATION_PASSED keyword + tool_use JSON events.

# verify_phase(phase_num, log_file)
# Returns 0 if verification passes (or VERIFY_PHASES is disabled), 1 on failure.
verify_phase() {
  local phase_num="$1" log_file="$2"

  [ "$VERIFY_PHASES" = "true" ] || return 0

  local phase_var
  phase_var=$(phase_to_var "$phase_num")
  local title description
  title=$(eval "echo \"\$PHASE_TITLE_${phase_var}\"")
  description=$(eval "echo \"\$PHASE_DESCRIPTION_${phase_var}\"")

  printf '[%s] Verifying phase %s...\n' "$(date '+%H:%M:%S')" "$phase_num" >&2
  log_live "Verifying phase $phase_num..."

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

## Verdict (MANDATORY)

After completing ALL verification steps above, you MUST output your verdict as the LAST thing you write.
Do NOT skip this. Do NOT just end silently.

- If ALL checks pass: output exactly the word VERIFICATION_PASSED on its own line
- If ANY check fails: output exactly the word VERIFICATION_FAILED on its own line, followed by a brief summary of what failed"

  # Prepare verify log files
  local verify_log=".claudeloop/logs/phase-$phase_num.verify.log"
  local verify_formatted_log=".claudeloop/logs/phase-$phase_num.verify.formatted.log"
  mkdir -p ".claudeloop/logs"
  : > "$verify_log"
  : > "$verify_formatted_log"

  # Run claude piped through process_stream_json (same pattern as execute_phase)
  local _exit_tmp _skip_flag
  _exit_tmp=$(mktemp)
  _skip_flag=""
  if [ "$SKIP_PERMISSIONS" = "true" ]; then
    _skip_flag="--dangerously-skip-permissions"
  fi

  # Sentinel file: created when stream processor (AWK) exits.
  local _sentinel
  _sentinel=$(mktemp)
  rm -f "$_sentinel"

  set -m
  {
    _rc=0
    # shellcheck disable=SC2086
    printf '%s\n' "$prompt" | claude --print --output-format=stream-json --verbose \
      --include-partial-messages \
      $_skip_flag 2>&1 || _rc=$?
    printf '%s\n' "$_rc" > "$_exit_tmp"
  } | inject_heartbeats | { process_stream_json "$verify_formatted_log" "$verify_log" \
      "false" "${LIVE_LOG:-}" "${SIMPLE_MODE:-false}" "0"; : > "$_sentinel"; } &
  CURRENT_PIPELINE_PID=$!
  CURRENT_PIPELINE_PGID=$(jobs -p 2>/dev/null | tr -d '[:space:]')
  set +m

  # Timeout: use MAX_PHASE_TIME if set, otherwise default 300s for verification
  local _timer_pid _vp_pid _vp_pgid _verify_timeout
  _timer_pid=""
  _vp_pid="$CURRENT_PIPELINE_PID"
  _vp_pgid="$CURRENT_PIPELINE_PGID"
  _verify_timeout="${VERIFY_TIMEOUT:-300}"
  if [ "$MAX_PHASE_TIME" -gt 0 ] 2>/dev/null && [ "$_verify_timeout" -eq 300 ]; then
    _verify_timeout="$MAX_PHASE_TIME"
  fi
  set -m
  ( sleep "$_verify_timeout" && kill -TERM -- "-${_vp_pgid}" 2>/dev/null && : > "$_sentinel" ) >/dev/null 2>&1 &
  _timer_pid=$!
  set +m

  # Wait for stream processor to finish (sentinel-based, same as execute_phase)
  while [ ! -f "$_sentinel" ]; do
    sleep 1
  done

  # Stream processor done — kill remaining pipeline processes (Claude CLI may linger)
  if [ -n "$CURRENT_PIPELINE_PGID" ] && [ "${CURRENT_PIPELINE_PGID:-0}" -gt 1 ]; then
    kill -TERM -- "-$CURRENT_PIPELINE_PGID" 2>/dev/null || true
  fi
  wait "$CURRENT_PIPELINE_PID" 2>/dev/null || true
  rm -f "$_sentinel"
  # Clear spinner remnants and reset scroll region
  printf '\033[r\033[?25h\r%-12s\r' '' >/dev/stderr
  CURRENT_PIPELINE_PID=""
  CURRENT_PIPELINE_PGID=""

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

  # Exit code check FIRST
  if [ "$verify_exit" -ne 0 ]; then
    printf '[%s] Verification failed (exit code %s)\n' "$(date '+%H:%M:%S')" "$verify_exit" >&2
    log_live "Verification failed for phase $phase_num (exit code $verify_exit)"
    return 1
  fi

  # Verdict check 1: VERIFICATION_FAILED takes priority (even if PASSED also appears)
  if grep -q 'VERIFICATION_FAILED' "$verify_log" 2>/dev/null; then
    printf '[%s] Verification failed: verifier reported VERIFICATION_FAILED\n' "$(date '+%H:%M:%S')" >&2
    log_live "Verification failed for phase $phase_num: VERIFICATION_FAILED"
    return 1
  fi

  # Verdict check 2: tool calls were actually made (JSON-aware anti-skip)
  if ! grep -q '"type":"tool_use"' "$verify_log" 2>/dev/null; then
    printf '[%s] Verification failed: no tool calls detected (verifier may have skipped checks)\n' "$(date '+%H:%M:%S')" >&2
    log_live "Verification failed for phase $phase_num: no tool calls detected"
    return 1
  fi

  # Verdict check 3: explicit VERIFICATION_PASSED verdict required
  if ! grep -q 'VERIFICATION_PASSED' "$verify_log" 2>/dev/null; then
    printf '[%s] Verification failed: no VERIFICATION_PASSED verdict found\n' "$(date '+%H:%M:%S')" >&2
    log_live "Verification failed for phase $phase_num: no VERIFICATION_PASSED verdict"
    return 1
  fi

  printf '[%s] Verification passed for phase %s\n' "$(date '+%H:%M:%S')" "$phase_num" >&2
  log_live "Verification passed for phase $phase_num"
  return 0
}
