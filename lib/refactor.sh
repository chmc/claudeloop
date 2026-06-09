#!/bin/sh

# Auto-Refactoring Library
# Runs a Claude instance to refactor code after each phase, with verification and rollback.
# Refactor state is persisted to PROGRESS.md and can resume on restart.

# build_refactor_analysis(pre_sha)
# Runs code smell detectors on files changed since pre_sha (or HEAD~1).
# Returns formatted analysis string, empty if no issues found.
# Separated from build_refactor_prompt so callers can cache the result across retries.
build_refactor_analysis() {
  local _bra_pre_sha="${1:-}"
  local _bra_changed_files _bra_long_blocks _bra_duplicates _bra_nesting _bra_fanout
  if [ -n "$_bra_pre_sha" ]; then
    _bra_changed_files=$(git diff --name-only ':!.claudeloop/' "${_bra_pre_sha}..HEAD" 2>/dev/null)
  else
    _bra_changed_files=$(git diff --name-only ':!.claudeloop/' HEAD~1 2>/dev/null)
  fi
  _bra_changed_files=$(printf '%s\n' "$_bra_changed_files" | \
    grep -E '\.(sh|js|ts|jsx|tsx|go|java|c|cpp|rs|css|py|rb)$' || true)

  [ -z "$_bra_changed_files" ] && return 0

  # Word-split intentional: git diff --name-only produces newline-separated paths, no spaces
  # shellcheck disable=SC2086
  _bra_long_blocks=$(detect_long_blocks 50 $_bra_changed_files 2>/dev/null)
  # shellcheck disable=SC2086
  _bra_duplicates=$(detect_duplicates 10 $_bra_changed_files 2>/dev/null)
  # shellcheck disable=SC2086
  _bra_nesting=$(detect_nesting 4 $_bra_changed_files 2>/dev/null)
  # shellcheck disable=SC2086
  _bra_fanout=$(detect_fanout 10 $_bra_changed_files 2>/dev/null)

  local _bra_result=""
  [ -n "$_bra_long_blocks" ] && _bra_result="${_bra_result}### Long Blocks (>50 lines) — candidates to split
${_bra_long_blocks}
"
  [ -n "$_bra_duplicates" ] && _bra_result="${_bra_result}### Potential Duplicates — candidates to consolidate
${_bra_duplicates}
"
  [ -n "$_bra_nesting" ] && _bra_result="${_bra_result}### Deep Nesting (>4 levels) — candidates to flatten
${_bra_nesting}
"
  [ -n "$_bra_fanout" ] && _bra_result="${_bra_result}### High Coupling (>10 imports) — candidates to split
${_bra_fanout}
"
  printf '%s' "$_bra_result"
}

# build_refactor_prompt(phase_num [pre_sha [analysis]])
# Builds the refactoring prompt including phase context and git diff stats.
# When pre_sha is provided, shows accumulated diff from pre_sha..HEAD instead of HEAD~1.
# When analysis is provided (pre-computed smell output), uses it directly — avoids recomputing on retries.
build_refactor_prompt() {
  local _brp_phase="$1"
  local _brp_pre_sha="${2:-}"
  local _brp_analysis_provided="${3+yes}"  # "yes" if $3 was passed (even empty), "" if unset
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

  # Run code smell detectors on changed code files (graceful — empty on failure).
  # Accepts pre-computed analysis string to avoid recomputing on retries.
  local _brp_analysis=""
  if [ "$_brp_analysis_provided" = "yes" ]; then
    _brp_analysis="$3"
  else
    _brp_analysis=$(build_refactor_analysis "$_brp_pre_sha")
  fi

  printf '%s' "You are a refactoring agent. Your ONLY job is to improve code structure.
You MUST NOT add features, change behavior, or fix bugs.

## Context
Phase $_brp_phase: $_brp_title
$_brp_desc

## Changes from this phase
$_brp_diff_stat

## Source files by size (largest first)
$_brp_file_sizes
${_brp_analysis:+
## Code Smell Analysis (heuristic candidates — use your judgment)
$_brp_analysis}

## Rules
1. ONLY structural changes: extract functions, split files, improve organization
2. NO behavioral changes — all existing tests must continue to pass
3. NO new features or bug fixes
4. Run the test suite before and after your changes
5. Commit with message: \"refactor: restructure phase $_brp_phase output\"
6. MOVE code into new files — do NOT create copies. Delete the original after extracting.
7. INCREMENTAL ONLY: only refactor code changed by this phase — ignore pre-existing issues elsewhere

## Steps
1. Read the largest file listed above
2. Any source file over 350 lines MUST be split into focused modules
3. Extract related functions into their own files (e.g., utils, handlers, types)
4. Address code smell candidates above if relevant to this phase's changes:
   - Long blocks: extract into named functions
   - Duplicates: consolidate into shared utility
   - Deep nesting: flatten via early returns or extraction
   - High coupling: split file by responsibility cluster
5. Update imports — keep the same public API from the original file
6. Run the test suite to verify nothing broke
7. Commit with message: \"refactor: restructure phase $_brp_phase output\"

If ALL files are under 350 lines, well-organized, and no smell candidates apply, do nothing."
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
  $(provider_verdict_pass_keyword)
  $(provider_verdict_fail_keyword)
WARNING: Omitting the verdict causes automatic failure. Do not end without outputting one."

  local _vr_formatted=".claudeloop/logs/phase-$_vr_phase.refactor-verify.log"
  local _vr_raw=".claudeloop/logs/phase-$_vr_phase.refactor-verify.raw.json"
  mkdir -p ".claudeloop/logs"
  : > "$_vr_formatted"
  : > "$_vr_raw"

  print_substep_header "🔍" "Verifying refactoring for phase $_vr_phase..."

  run_claude_pipeline "$_vr_prompt" "$_vr_phase" "$_vr_formatted" "$_vr_raw" "verify"
  local _vr_exit="$_LAST_CLAUDE_EXIT"

  check_verdict "$_vr_raw" "$_vr_phase" "Refactor verification" "$_vr_exit"
}

# refactor_phase(phase_num)
# Main refactoring entry point with up to REFACTOR_MAX_RETRIES attempts (default 20) and git rollback.
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
  _max_attempts=${REFACTOR_MAX_RETRIES:-20}

  # Resume from persisted attempt count
  _attempt=$(get_phase_refactor_attempts "$_rp_phase")
  case "$_attempt" in ''|*[!0-9]*) _attempt=0 ;; esac

  # Persist in_progress state + SHA before running
  phase_set REFACTOR_STATUS "$_rp_phase" "in_progress $_attempt/$_max_attempts"
  phase_set REFACTOR_SHA "$_rp_phase" "$_pre_sha"
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"

  print_substep_header "🔧" "Refactoring phase $_rp_phase..."

  # Compute smell analysis once — results don't change between retries
  local _rp_analysis
  _rp_analysis=$(build_refactor_analysis "$_pre_sha")

  local _has_crash_changes=false

  while [ "$_attempt" -lt "$_max_attempts" ]; do
    _attempt=$((_attempt + 1))

    # Persist attempt count and status
    phase_set REFACTOR_ATTEMPTS "$_rp_phase" "$_attempt"
    phase_set REFACTOR_STATUS "$_rp_phase" "in_progress $_attempt/$_max_attempts"
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"

    # Capture HEAD before this iteration — used to detect if THIS run made changes
    local _iter_sha
    _iter_sha=$(git rev-parse HEAD)

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

    _rp_prompt=$(build_refactor_prompt "$_rp_phase" "$_pre_sha" "$_rp_analysis")

    if [ -n "$_err_ctx" ]; then
      _rp_prompt="${_rp_prompt}

## Previous Attempt Failed (attempt $((_attempt - 1)) of $_max_attempts)

\`\`\`
$_err_ctx
\`\`\`"
    fi

    # Run refactoring
    run_claude_pipeline "$_rp_prompt" "$_rp_phase" "$_rp_log" "$_rp_raw" "refactor"

    if [ "$_LAST_CLAUDE_EXIT" -ne 0 ]; then
      if is_auth_error "$_rp_log"; then
        print_error "Phase $_rp_phase: refactoring hit authentication error — aborting retries"
        break
      fi
      if has_successful_session "$_rp_log"; then
        log_ts "Phase $_rp_phase: exit code $_LAST_CLAUDE_EXIT but successful session detected — continuing"
      else
        print_warning "Phase $_rp_phase: refactoring failed (exit code $_LAST_CLAUDE_EXIT)"
        # Preserve partial work from crash
        auto_commit_changes "$_rp_phase" "auto-commit after crash"
        _has_crash_changes=true
        continue
      fi
    fi

    # Auto-commit any uncommitted refactoring changes
    auto_commit_changes "$_rp_phase" "auto-commit after refactoring"

    # Check if THIS iteration made changes; if crash left prior changes, fall through to verify
    local _code_changes
    _code_changes=$(git diff --name-only "$_iter_sha"..HEAD -- ':!.claudeloop/' 2>/dev/null)
    if [ -z "$_code_changes" ] && [ "$_has_crash_changes" = "false" ]; then
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
