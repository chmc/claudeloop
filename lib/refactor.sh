#!/bin/sh

# Auto-Refactoring Library
# Runs a Claude instance to refactor code after each phase, with verification and rollback.

# build_refactor_prompt(phase_num)
# Builds the refactoring prompt including phase context and git diff stats.
build_refactor_prompt() {
  local _brp_phase="$1"
  local _brp_title _brp_desc _brp_diff_stat
  _brp_title=$(get_phase_title "$_brp_phase")
  _brp_desc=$(get_phase_description "$_brp_phase")
  _brp_diff_stat=$(git diff --stat HEAD~1 2>/dev/null || echo "(no diff available)")

  printf '%s' "You are a refactoring agent. Your ONLY job is to improve code structure.
You MUST NOT add features, change behavior, or fix bugs.

## Context
Phase $_brp_phase: $_brp_title
$_brp_desc

## Changes from this phase
$_brp_diff_stat

## Rules
1. ONLY structural changes: extract functions, split files, improve organization
2. NO behavioral changes — all existing tests must continue to pass
3. NO new features or bug fixes
4. Run the test suite before and after your changes
5. Commit with message: \"refactor: restructure phase $_brp_phase output\"

## Strategy
- Large files: split into logical modules
- Long functions: extract helper functions
- Repeated patterns: extract into shared utilities
- Keep public API/exports identical
- If the code is already well-structured, do nothing and exit"
}

# verify_refactor(phase_num)
# Runs a verification Claude to check that refactoring preserved behavior.
# Returns 0 (pass) or 1 (fail).
verify_refactor() {
  local _vr_phase="$1"
  local _vr_title
  _vr_title=$(get_phase_title "$_vr_phase")

  local _vr_prompt
  _vr_prompt="You are a verification agent. Your job is to verify that a code refactoring did not break anything.
The refactoring was purely structural — files were split, functions extracted, code reorganized.
No features were added or removed.

## What was refactored
Phase $_vr_phase: $_vr_title — structural improvements to code from this phase.

## Mandatory Verification Steps

You MUST actually execute commands. Do NOT skip testing.

1. Run \`git diff HEAD~1\` to review what the refactoring changed
2. Run the test suite (e.g. \`npm test\`, \`pytest\`, \`go test\`, \`bats\`, etc.)
3. Run linters if configured
4. Verify the refactoring was purely structural (no behavioral changes)

## Verdict (MANDATORY)
- If ALL checks pass: output exactly VERIFICATION_PASSED
- If ANY check fails: output exactly VERIFICATION_FAILED followed by what failed"

  local _vr_formatted=".claudeloop/logs/phase-$_vr_phase.refactor-verify.log"
  local _vr_raw=".claudeloop/logs/phase-$_vr_phase.refactor-verify.raw.json"
  mkdir -p ".claudeloop/logs"
  : > "$_vr_formatted"
  : > "$_vr_raw"

  print_substep_header "🔍" "Verifying refactoring for phase $_vr_phase..."

  run_claude_pipeline "$_vr_prompt" "$_vr_phase" "$_vr_formatted" "$_vr_raw"
  local _vr_exit="$_LAST_CLAUDE_EXIT"

  check_verdict "$_vr_raw" "$_vr_phase" "Refactor verification" "$_vr_exit"
}

# refactor_phase(phase_num)
# Main refactoring entry point with up to 3 attempts and git rollback.
# Always returns 0 — refactoring failure is non-fatal.
refactor_phase() {
  local _rp_phase="$1"
  local _pre_sha _attempt _max_attempts

  _pre_sha=$(git rev-parse HEAD)
  _PRE_REFACTOR_SHA="$_pre_sha"
  _max_attempts=3

  print_substep_header "🔧" "Refactoring phase $_rp_phase..."

  _attempt=0
  while [ "$_attempt" -lt "$_max_attempts" ]; do
    _attempt=$((_attempt + 1))

    # Build prompt (on retry: append error context)
    local _rp_prompt _rp_log _rp_raw
    _rp_prompt=$(build_refactor_prompt "$_rp_phase")
    _rp_log=".claudeloop/logs/phase-$_rp_phase.refactor.log"
    _rp_raw=".claudeloop/logs/phase-$_rp_phase.refactor.raw.json"
    mkdir -p ".claudeloop/logs"
    : > "$_rp_log"
    : > "$_rp_raw"

    if [ "$_attempt" -gt 1 ]; then
      local _err_ctx
      _err_ctx=$(extract_error_context "$_rp_log" 15)
      if [ -n "$_err_ctx" ]; then
        _rp_prompt="${_rp_prompt}

## Previous Attempt Failed (attempt $((_attempt - 1)) of $_max_attempts)

\`\`\`
$_err_ctx
\`\`\`"
      fi
    fi

    # Run refactoring
    run_claude_pipeline "$_rp_prompt" "$_rp_phase" "$_rp_log" "$_rp_raw"

    if [ "$_LAST_CLAUDE_EXIT" -ne 0 ]; then
      print_warning "Phase $_rp_phase: refactoring failed (exit code $_LAST_CLAUDE_EXIT), rolling back"
      git reset --hard "$_pre_sha" 2>/dev/null && git clean -fd 2>/dev/null || true
      continue
    fi

    # Check if SHA changed — if not, nothing was refactored
    local _post_sha
    _post_sha=$(git rev-parse HEAD)
    if [ "$_post_sha" = "$_pre_sha" ]; then
      log_ts "Nothing to refactor for phase $_rp_phase"
      _PRE_REFACTOR_SHA=""
      return 0
    fi

    # Verify refactoring
    if verify_refactor "$_rp_phase"; then
      print_success "Phase $_rp_phase refactored successfully"
      _PRE_REFACTOR_SHA=""
      return 0
    fi

    # Verification failed — rollback
    print_warning "Phase $_rp_phase: refactor verification failed, rolling back"
    git reset --hard "$_pre_sha" 2>/dev/null && git clean -fd 2>/dev/null || true
  done

  # All attempts exhausted
  print_warning "Refactoring failed after $_max_attempts attempts, continuing without"
  git reset --hard "$_pre_sha" 2>/dev/null && git clean -fd 2>/dev/null || true
  _PRE_REFACTOR_SHA=""
  return 0
}

# run_refactor_if_needed(phase_num)
# Guard: only runs if REFACTOR_PHASES is enabled.
run_refactor_if_needed() {
  [ "$REFACTOR_PHASES" = "true" ] || return 0
  refactor_phase "$1"
}
