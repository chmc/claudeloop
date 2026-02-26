#!/bin/sh

# Phase Verification Library
# Runs a read-only Claude instance to verify phase completion.
# Exit-code based: claude exit 0 + tool calls detected = pass.

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

  printf 'Verifying phase %s...\n' "$phase_num" >&2
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

## Reporting

If ALL checks pass, your task is complete.
If ANY check fails, report what failed."

  # Prepare verify log
  local verify_log=".claudeloop/logs/phase-$phase_num.verify.log"
  mkdir -p ".claudeloop/logs"

  # Run claude in a killable background process group
  local _exit_tmp _skip_flag
  _exit_tmp=$(mktemp)
  _skip_flag=""
  if [ "$SKIP_PERMISSIONS" = "true" ]; then
    _skip_flag="--dangerously-skip-permissions"
  fi

  set -m
  {
    _rc=0
    # shellcheck disable=SC2086
    printf '%s\n' "$prompt" | claude --print --verbose \
      $_skip_flag \
      > "$verify_log" 2>&1 || _rc=$?
    printf '%s' "$_rc" > "$_exit_tmp"
  } &
  CURRENT_PIPELINE_PID=$!
  CURRENT_PIPELINE_PGID=$!
  set +m

  # Timeout: reuse MAX_PHASE_TIME
  local _timer_pid _vp_pid _vp_pgid
  _timer_pid=""
  _vp_pid="$CURRENT_PIPELINE_PID"
  _vp_pgid="$CURRENT_PIPELINE_PGID"
  if [ "$MAX_PHASE_TIME" -gt 0 ] 2>/dev/null; then
    set -m
    ( sleep "$MAX_PHASE_TIME" && kill -TERM -- "-${_vp_pgid}" 2>/dev/null ) >/dev/null 2>&1 &
    _timer_pid=$!
    set +m
  fi

  wait "$CURRENT_PIPELINE_PID" || true
  CURRENT_PIPELINE_PID=""
  CURRENT_PIPELINE_PGID=""

  # Cancel timer
  if [ -n "$_timer_pid" ]; then
    kill -- "-$_timer_pid" 2>/dev/null || true
    wait "$_timer_pid" 2>/dev/null || true
    _timer_pid=""
  fi

  # Read exit code
  local verify_exit=1
  if [ -f "$_exit_tmp" ]; then
    verify_exit=$(cat "$_exit_tmp")
    rm -f "$_exit_tmp"
  fi

  # Exit code check FIRST
  if [ "$verify_exit" -ne 0 ]; then
    printf 'Verification failed (exit code %s)\n' "$verify_exit" >&2
    log_live "Verification failed for phase $phase_num (exit code $verify_exit)"
    return 1
  fi

  # Anti-skip check: grep for tool invocation evidence (only when exit=0)
  if ! grep -qiE 'ToolUse|Tool_use|tool_use|tool use|\[Tool|Bash|Read|Write|Edit|Glob|Grep' "$verify_log" 2>/dev/null; then
    printf 'Verification failed: no tool calls detected (verifier may have skipped checks)\n' >&2
    log_live "Verification failed for phase $phase_num: no tool calls detected"
    return 1
  fi

  printf 'Verification passed for phase %s\n' "$phase_num" >&2
  log_live "Verification passed for phase $phase_num"
  return 0
}
