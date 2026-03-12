#!/bin/sh

# Auto-Refactoring Library
# Runs a Claude instance to refactor code after each phase, with verification and rollback.
# Refactor state is persisted to PROGRESS.md and can resume on restart.

# build_refactor_prompt(phase_num [pre_sha])
# Builds the refactoring prompt including phase context and git diff stats.
# When pre_sha is provided, shows accumulated diff from pre_sha..HEAD instead of HEAD~1.
build_refactor_prompt() {
  local _brp_phase="$1"
  local _brp_pre_sha="${2:-}"
  local _brp_title _brp_desc _brp_diff_stat
  _brp_title=$(get_phase_title "$_brp_phase")
  _brp_desc=$(get_phase_description "$_brp_phase")
  if [ -n "$_brp_pre_sha" ]; then
    _brp_diff_stat=$(git diff --stat "${_brp_pre_sha}..HEAD" 2>/dev/null || echo "(no diff available)")
  else
    _brp_diff_stat=$(git diff --stat HEAD~1 2>/dev/null || echo "(no diff available)")
  fi

  local _brp_file_sizes
  _brp_file_sizes=$(git ls-files -- ':!.claudeloop/' ':!*.lock' ':!package-lock.json' \
    ':!*.min.js' ':!*.min.css' ':!*.map' ':!*.png' ':!*.jpg' ':!*.jpeg' ':!*.gif' \
    ':!*.ico' ':!*.svg' ':!*.woff*' ':!*.ttf' ':!*.eot' ':!*.pdf' ':!*.wasm' \
    ':!*.zip' ':!*.tar*' ':!*.gz' 2>/dev/null | while read -r _f; do
      [ -f "$_f" ] && printf '%s %s\n' "$(wc -l < "$_f" | tr -d ' ')" "$_f"
    done | sort -rn | head -10)

  printf '%s' "You are a refactoring agent. Your ONLY job is to improve code structure.
You MUST NOT add features, change behavior, or fix bugs.

## Context
Phase $_brp_phase: $_brp_title
$_brp_desc

## Changes from this phase
$_brp_diff_stat

## Source files by size (largest first)
$_brp_file_sizes

## Rules
1. ONLY structural changes: extract functions, split files, improve organization
2. NO behavioral changes — all existing tests must continue to pass
3. NO new features or bug fixes
4. Run the test suite before and after your changes
5. Commit with message: \"refactor: restructure phase $_brp_phase output\"
6. MOVE code into new files — do NOT create copies. Delete the original after extracting.

## Steps
1. Read the largest file listed above
2. Any source file over 200 lines MUST be split into focused modules
3. Extract related functions into their own files (e.g., utils, handlers, types)
4. Update imports — keep the same public API from the original file
5. Run the test suite to verify nothing broke
6. Commit with message: \"refactor: restructure phase $_brp_phase output\"

If ALL files are under 200 lines and well-organized, do nothing."
}

# verify_refactor(phase_num [pre_sha])
# Runs a verification Claude to check that refactoring preserved behavior.
# When pre_sha is provided, uses accumulated diff from pre_sha..HEAD.
# Returns 0 (pass) or 1 (fail).
verify_refactor() {
  local _vr_phase="$1"
  local _vr_pre_sha="${2:-}"
  local _vr_title
  _vr_title=$(get_phase_title "$_vr_phase")

  local _vr_pre_sha_display
  if [ -n "$_vr_pre_sha" ]; then
    _vr_pre_sha_display="$_vr_pre_sha"
  else
    _vr_pre_sha_display="HEAD~1"
  fi

  local _vr_prompt
  _vr_prompt="You are a verification agent checking that a code refactoring did not introduce regressions.
The refactoring was purely structural — files split, functions extracted, code reorganized.

## What was refactored
Phase $_vr_phase: $_vr_title — structural improvements. Pre-refactor commit: $_vr_pre_sha_display

## Mandatory Steps
1. Run \`git diff --name-only $_vr_pre_sha_display..HEAD\` to see which files were changed
2. Run the test suite / build command (e.g. \`npm test\`, \`pytest\`, \`go test\`, \`bats\`, etc.)
3. If failures exist, determine whether they are pre-existing or new regressions

## Regression Rule (CRITICAL)
You are checking for REGRESSIONS, not absolute correctness.
- If errors are in code that was NOT changed by the refactoring → pre-existing → acceptable
- If errors moved between files during refactoring (e.g., from original to extracted module) → same error, acceptable
- Only fail if the refactoring INTRODUCED genuinely new errors
- When in doubt, pass — refactoring should not be blocked by pre-existing issues

## Verdict (MANDATORY)
Your FINAL line of output MUST be exactly one of:
  VERIFICATION_PASSED
  VERIFICATION_FAILED
WARNING: Omitting the verdict causes automatic failure. Do not end without outputting one."

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
# Main refactoring entry point with up to 5 attempts and git rollback.
# Persists state to PROGRESS.md for resume on restart.
# Between retries, work is preserved (no rollback). Only on final exhaustion
# are changes rolled back to pre-refactor state.
# Always returns 0 — refactoring failure is non-fatal.
refactor_phase() {
  local _rp_phase="$1"
  local _pre_sha _attempt _max_attempts

  _REFACTORING_PHASE="$_rp_phase"

  auto_commit_changes "$_rp_phase" "auto-commit before refactoring"

  # Use persisted SHA if resuming, otherwise capture fresh
  _pre_sha=$(get_phase_refactor_sha "$_rp_phase")
  if [ -z "$_pre_sha" ]; then
    _pre_sha=$(git rev-parse HEAD)
  fi
  _max_attempts=5

  # Resume from persisted attempt count
  _attempt=$(get_phase_refactor_attempts "$_rp_phase")
  case "$_attempt" in ''|*[!0-9]*) _attempt=0 ;; esac

  # Persist in_progress state + SHA before running
  phase_set REFACTOR_STATUS "$_rp_phase" "in_progress $_attempt/$_max_attempts"
  phase_set REFACTOR_SHA "$_rp_phase" "$_pre_sha"
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"

  print_substep_header "🔧" "Refactoring phase $_rp_phase..."

  while [ "$_attempt" -lt "$_max_attempts" ]; do
    _attempt=$((_attempt + 1))

    # Persist attempt count and status
    phase_set REFACTOR_ATTEMPTS "$_rp_phase" "$_attempt"
    phase_set REFACTOR_STATUS "$_rp_phase" "in_progress $_attempt/$_max_attempts"
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"

    # Build prompt (on retry: append error context from previous log)
    local _rp_prompt _rp_log _rp_raw
    _rp_log=".claudeloop/logs/phase-$_rp_phase.refactor.log"
    _rp_raw=".claudeloop/logs/phase-$_rp_phase.refactor.raw.json"
    mkdir -p ".claudeloop/logs"

    # Extract error context BEFORE clearing the log
    local _err_ctx=""
    if [ "$_attempt" -gt 1 ] && [ -f "$_rp_log" ]; then
      _err_ctx=$(extract_error_context "$_rp_log" 15)
    fi

    : > "$_rp_log"
    : > "$_rp_raw"

    _rp_prompt=$(build_refactor_prompt "$_rp_phase" "$_pre_sha")

    if [ -n "$_err_ctx" ]; then
      _rp_prompt="${_rp_prompt}

## Previous Attempt Failed (attempt $((_attempt - 1)) of $_max_attempts)

\`\`\`
$_err_ctx
\`\`\`"
    fi

    # Run refactoring
    run_claude_pipeline "$_rp_prompt" "$_rp_phase" "$_rp_log" "$_rp_raw"

    if [ "$_LAST_CLAUDE_EXIT" -ne 0 ]; then
      print_warning "Phase $_rp_phase: refactoring failed (exit code $_LAST_CLAUDE_EXIT)"
      # Preserve partial work from crash
      auto_commit_changes "$_rp_phase" "auto-commit after crash"
      continue
    fi

    # Auto-commit any uncommitted refactoring changes
    auto_commit_changes "$_rp_phase" "auto-commit after refactoring"

    # Check if any non-metadata files changed — if not, nothing was refactored
    local _code_changes
    _code_changes=$(git diff --name-only "$_pre_sha"..HEAD -- ':!.claudeloop/' 2>/dev/null)
    if [ -z "$_code_changes" ]; then
      log_ts "Nothing to refactor for phase $_rp_phase"
      phase_set REFACTOR_STATUS "$_rp_phase" "completed"
      phase_set REFACTOR_SHA "$_rp_phase" ""
      phase_set REFACTOR_ATTEMPTS "$_rp_phase" ""
      write_progress "$PROGRESS_FILE" "$PLAN_FILE"
      _REFACTORING_PHASE=""
      return 0
    fi

    # Verify refactoring (pass pre_sha for accumulated diff scope)
    if verify_refactor "$_rp_phase" "$_pre_sha"; then
      print_success "Phase $_rp_phase refactored successfully"
      phase_set REFACTOR_STATUS "$_rp_phase" "completed"
      phase_set REFACTOR_SHA "$_rp_phase" ""
      phase_set REFACTOR_ATTEMPTS "$_rp_phase" ""
      write_progress "$PROGRESS_FILE" "$PLAN_FILE"
      _REFACTORING_PHASE=""
      return 0
    fi

    # Verification failed — preserve work (auto-commit any linter fixes/test artifacts)
    print_warning "Phase $_rp_phase: refactor verification failed"
    auto_commit_changes "$_rp_phase" "auto-commit after verify failure"
  done

  # All attempts exhausted — discard and rollback to pre-refactor state
  print_warning "Refactoring failed after $_max_attempts attempts, rolling back"
  git reset --hard "$_pre_sha" 2>/dev/null && git clean -fd 2>/dev/null || true
  phase_set REFACTOR_STATUS "$_rp_phase" "discarded"
  phase_set REFACTOR_SHA "$_rp_phase" ""
  phase_set REFACTOR_ATTEMPTS "$_rp_phase" ""
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"
  _REFACTORING_PHASE=""
  return 0
}

# run_refactor_if_needed(phase_num)
# Guard: only runs if REFACTOR_PHASES is enabled.
run_refactor_if_needed() {
  [ "$REFACTOR_PHASES" = "true" ] || return 0
  refactor_phase "$1"
}

# resume_pending_refactors()
# Called on startup to resume any interrupted or pending refactors from a previous run.
# Gates on REFACTOR_PHASES=true — stale state is harmless without the flag.
resume_pending_refactors() {
  [ "$REFACTOR_PHASES" = "true" ] || return 0

  for phase_num in $PHASE_NUMBERS; do
    local refactor_status
    refactor_status=$(get_phase_refactor_status "$phase_num")
    case "$refactor_status" in
      in_progress*)
        print_warning "Resuming interrupted refactoring for Phase $phase_num..."
        local pre_sha
        pre_sha=$(get_phase_refactor_sha "$phase_num")
        if [ -n "$pre_sha" ]; then
          # Validate SHA still exists (could be gc'd)
          if ! git cat-file -t "$pre_sha" >/dev/null 2>&1; then
            print_warning "Pre-refactor SHA $pre_sha no longer exists, marking discarded for Phase $phase_num"
            phase_set REFACTOR_STATUS "$phase_num" "discarded"
            phase_set REFACTOR_ATTEMPTS "$phase_num" ""
            write_progress "$PROGRESS_FILE" "$PLAN_FILE"
            continue
          fi
        fi
        # refactor_phase reads persisted SHA and attempt count, continues from there
        refactor_phase "$phase_num"
        ;;
      pending)
        print_warning "Completing pending refactoring for Phase $phase_num..."
        refactor_phase "$phase_num"
        ;;
    esac
  done
}
