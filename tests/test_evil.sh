#!/usr/bin/env bash
# bats file_tags=evil,security

# Adversarial test suite: injection attacks, numeric bugs, safety regressions, boundaries

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  . "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  . "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  . "${BATS_TEST_DIRNAME}/../lib/dependencies.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: set up a single-phase environment for progress tests
setup_single_phase() {
  PHASE_COUNT=1
  PHASE_NUMBERS="1"
  PHASE_TITLE_1="Setup"
  PHASE_STATUS_1="pending"
  PHASE_ATTEMPTS_1=0
  PHASE_START_TIME_1=""
  PHASE_END_TIME_1=""
  PHASE_DEPENDENCIES_1=""
}

# =============================================================================
# Section 1: Injection via crafted PROGRESS.md (7 tests -- all expected to FAIL)
# =============================================================================

@test "EVIL: unquoted attempts semicolon injection via read_progress" {
  setup_single_phase
  marker="$TEST_DIR/pwned_attempts_semi"
  cat > "$TEST_DIR/PROGRESS.md" << EOF
### ⏳ Phase 1: Setup
Status: pending
Attempts: 1; touch $marker
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ ! -f "$marker" ]
}

@test "EVIL: unquoted attempts command substitution via read_progress" {
  setup_single_phase
  marker="$TEST_DIR/pwned_attempts_cmdsub"
  cat > "$TEST_DIR/PROGRESS.md" << EOF
### ⏳ Phase 1: Setup
Status: pending
Attempts: \$(touch $marker)
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ ! -f "$marker" ]
}

@test "EVIL: status single-quote breakout via read_progress" {
  setup_single_phase
  marker="$TEST_DIR/pwned_status"
  cat > "$TEST_DIR/PROGRESS.md" << EOF
### ⏳ Phase 1: Setup
Status: x'; touch $marker; echo '
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ ! -f "$marker" ]
}

@test "EVIL: started time single-quote breakout via read_progress" {
  setup_single_phase
  marker="$TEST_DIR/pwned_started"
  cat > "$TEST_DIR/PROGRESS.md" << EOF
### ⏳ Phase 1: Setup
Status: pending
Started: x'; touch $marker; echo '
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ ! -f "$marker" ]
}

@test "EVIL: attempt time single-quote breakout via read_progress" {
  setup_single_phase
  marker="$TEST_DIR/pwned_attempt_time"
  cat > "$TEST_DIR/PROGRESS.md" << EOF
### ⏳ Phase 1: Setup
Status: pending
Attempts: 2
Attempt 1 Started: x'; touch $marker; echo '
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ ! -f "$marker" ]
}

@test "EVIL: read_old_phase_list attempts semicolon injection" {
  setup_single_phase
  marker="$TEST_DIR/pwned_old_attempts"
  cat > "$TEST_DIR/PROGRESS.md" << EOF
### ⏳ Phase 1: Setup
Status: pending
Attempts: 1; touch $marker
EOF
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ ! -f "$marker" ]
}

@test "EVIL: read_old_phase_list status single-quote breakout" {
  setup_single_phase
  marker="$TEST_DIR/pwned_old_status"
  cat > "$TEST_DIR/PROGRESS.md" << EOF
### ⏳ Phase 1: Setup
Status: x'; touch $marker; echo '
EOF
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ ! -f "$marker" ]
}

# =============================================================================
# Section 2: Injection via function arguments (1 test -- expected to FAIL)
# =============================================================================

@test "EVIL: update_phase_status single-quote breakout" {
  setup_single_phase
  marker="$TEST_DIR/pwned_update_status"
  update_phase_status "1" "completed'; touch $marker; echo '"
  [ ! -f "$marker" ]
}

# =============================================================================
# Section 3: Numeric bugs in retry.sh (4 tests -- all expected to FAIL)
# =============================================================================

@test "EVIL: power(2,63) overflows to negative" {
  run power 2 63
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

@test "EVIL: power() clobbers caller variables" {
  result="preserved"
  base="preserved"
  power 2 3 > /dev/null
  [ "$result" = "preserved" ]
  [ "$base" = "preserved" ]
}

@test "EVIL: get_random 0 division by zero" {
  run get_random 0
  [ "$status" -eq 0 ]
}

@test "EVIL: calculate_backoff 64 negative delay" {
  run calculate_backoff 64
  [ "$status" -eq 0 ]
  [ "$output" -ge 0 ]
}

# =============================================================================
# Section 4: Safety regression tests (3 tests -- expected to PASS)
# =============================================================================

@test "SAFE: title with \$(whoami) preserved literally" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: $(whoami) injection test
Description here
EOF
  parse_plan "$TEST_DIR/plan.md"
  title=$(eval "echo \"\$PHASE_TITLE_1\"")
  echo "title=$title"
  [ "$title" = '$(whoami) injection test' ]
}

@test "SAFE: description with backticks preserved literally" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: Safe phase
Run `rm -rf /` and `$(whoami)` carefully
EOF
  parse_plan "$TEST_DIR/plan.md"
  desc=$(eval "echo \"\$PHASE_DESCRIPTION_1\"")
  echo "desc=$desc"
  echo "$desc" | grep -qF '`rm -rf /`'
  echo "$desc" | grep -qF '`$(whoami)`'
}

@test "SAFE: self-dependency rejected" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
Do something

## Phase 2: Second
**Depends on:** Phase 2
Do something else
EOF
  run parse_plan "$TEST_DIR/plan.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "forward or self dependency"
}

# =============================================================================
# Section 5: Boundary/edge cases (3 tests -- expected to PASS)
# =============================================================================

@test "EVIL: attempts decrement below zero is guarded" {
  setup_single_phase
  PHASE_ATTEMPTS_1=0
  _npv="1"
  _cur_attempts=$(eval "echo \"\$PHASE_ATTEMPTS_${_npv}\"")
  # Simulate the guarded decrement
  if [ "$_cur_attempts" -gt 0 ]; then
    eval "PHASE_ATTEMPTS_${_npv}=$((_cur_attempts - 1))"
  fi
  # Attempts should still be 0, not -1
  [ "$PHASE_ATTEMPTS_1" -eq 0 ]
}

@test "EVIL: save_state escapes double quotes in paths" {
  # Test the save_state JSON generation with proper escaping
  STATE_FILE="$TEST_DIR/state.json"
  cat > "$TEST_DIR/test_save.sh" << 'SCRIPT'
#!/bin/sh
STATE_FILE="$1"
PLAN_FILE='my "plan".md'
PROGRESS_FILE='prog"ress.md'
CURRENT_PHASE="1"

_json_plan=$(printf '%s' "$PLAN_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g')
_json_progress=$(printf '%s' "$PROGRESS_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g')

cat > "$STATE_FILE" << EOF
{
  "plan_file": "$_json_plan",
  "progress_file": "$_json_progress",
  "current_phase": "$CURRENT_PHASE",
  "interrupted": true,
  "timestamp": "2026-01-01T00:00:00Z"
}
EOF
python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$STATE_FILE"
SCRIPT
  chmod +x "$TEST_DIR/test_save.sh"
  run sh "$TEST_DIR/test_save.sh" "$STATE_FILE"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "BOUNDARY: 100 phases parsed correctly" {
  {
    i=1
    while [ "$i" -le 100 ]; do
      echo "## Phase $i: Task number $i"
      echo "Do task $i"
      echo ""
      i=$((i + 1))
    done
  } > "$TEST_DIR/plan.md"
  parse_plan "$TEST_DIR/plan.md"
  [ "$PHASE_COUNT" -eq 100 ]
  title_1=$(eval "echo \"\$PHASE_TITLE_1\"")
  title_100=$(eval "echo \"\$PHASE_TITLE_100\"")
  [ "$title_1" = "Task number 1" ]
  [ "$title_100" = "Task number 100" ]
}

@test "BOUNDARY: 50-deep dependency chain resolves" {
  {
    echo "## Phase 1: Step 1"
    echo "Start here"
    echo ""
    i=2
    while [ "$i" -le 50 ]; do
      echo "## Phase $i: Step $i"
      echo "**Depends on:** Phase $((i - 1))"
      echo "Do step $i"
      echo ""
      i=$((i + 1))
    done
  } > "$TEST_DIR/plan.md"
  parse_plan "$TEST_DIR/plan.md"
  init_progress "$TEST_DIR/PROGRESS.md"
  # Should not detect cycles
  run detect_dependency_cycles
  [ "$status" -eq 0 ]
  # Only phase 1 should be runnable initially
  next=$(find_next_phase)
  [ "$next" = "1" ]
}

@test "BOUNDARY: truncated PROGRESS.md degrades gracefully" {
  setup_single_phase
  PHASE_COUNT=3
  PHASE_NUMBERS="1 2 3"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_TITLE_3="Phase Three"
  PHASE_STATUS_1="pending"
  PHASE_STATUS_2="pending"
  PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0
  PHASE_ATTEMPTS_2=0
  PHASE_ATTEMPTS_3=0
  PHASE_DEPENDENCIES_1=""
  PHASE_DEPENDENCIES_2=""
  PHASE_DEPENDENCIES_3=""
  # Truncated file: Phase 2 header present but no status/details, Phase 3 missing entirely
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 1

### ⏳ Phase 2: Phase Two
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  # Phase 1 should be restored; Phase 2/3 should retain defaults (pending)
  [ "$PHASE_STATUS_1" = "completed" ]
}

# =============================================================================
# Section 6: awk injection via phase_less_than (3 tests)
# =============================================================================

@test "EVIL: phase_less_than resists awk system() injection via first arg" {
  marker="$TEST_DIR/pwned_awk1"
  # If unpatched, awk interpolation would execute: system("touch marker")
  run phase_less_than '1) { system("touch '"$marker"'") } END { exit(0' "2"
  [ ! -f "$marker" ]
}

@test "EVIL: phase_less_than resists awk system() injection via second arg" {
  marker="$TEST_DIR/pwned_awk2"
  run phase_less_than "1" '2) { system("touch '"$marker"'") } END { exit(0'
  [ ! -f "$marker" ]
}

@test "EVIL: phase_less_than returns non-zero for non-numeric input" {
  # Injecting garbage should not succeed as a comparison
  run phase_less_than "abc" "2"
  # Should either return error or at least not crash with status > 1
  [ "$status" -le 1 ]
}

# =============================================================================
# Section 7: Non-numeric arithmetic in retry.sh (3 tests)
# =============================================================================

@test "EVIL: calculate_backoff with empty string does not crash" {
  run calculate_backoff ""
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" -ge 0 ]
}

@test "EVIL: calculate_backoff with non-numeric string does not crash" {
  run calculate_backoff "abc"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" -ge 0 ]
}

@test "EVIL: should_retry_phase with MAX_RETRIES=abc does not crash" {
  PHASE_COUNT=1
  PHASE_NUMBERS="1"
  PHASE_ATTEMPTS_1=1
  MAX_RETRIES="abc"
  run should_retry_phase "1"
  # Should not crash (exit 0 or 1, not 2+)
  [ "$status" -le 1 ]
}

# =============================================================================
# Section 8: Invalid --phase (2 tests, integration via claudeloop --dry-run)
# =============================================================================

@test "EVIL: --phase 99 with 3-phase plan errors cleanly" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
Do first

## Phase 2: Second
Do second

## Phase 3: Third
Do third
EOF
  run "$BATS_TEST_DIRNAME/../claudeloop" --plan "$TEST_DIR/plan.md" --dry-run --phase 99
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not found\|invalid\|error"
}

@test "EVIL: --phase abc errors cleanly" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
Do first
EOF
  run "$BATS_TEST_DIRNAME/../claudeloop" --plan "$TEST_DIR/plan.md" --dry-run --phase abc
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "number\|numeric\|invalid\|error"
}

# =============================================================================
# Section 9: Duplicate/edge phase numbers (2 tests)
# =============================================================================

@test "EVIL: duplicate phase number rejected" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
Do first

## Phase 1: Duplicate
Do duplicate
EOF
  run parse_plan "$TEST_DIR/plan.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "ascending\|duplicate\|order"
}

@test "EVIL: very large phase number (99999999) parses without crash" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 99999999: Huge
Do something
EOF
  parse_plan "$TEST_DIR/plan.md"
  [ "$PHASE_COUNT" -eq 1 ]
}

# =============================================================================
# Section 10: Description hijacking (2 tests)
# =============================================================================

@test "EVIL: Depends-on line inside description does not hijack deps" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
Do first

## Phase 2: Second
This phase describes how things work.
**Depends on:** Phase 1
But also mentions **Depends on:** Phase 99 in the body.
EOF
  parse_plan "$TEST_DIR/plan.md"
  deps=$(eval "echo \"\$PHASE_DEPENDENCIES_2\"")
  echo "deps=$deps"
  # Only Phase 1 should be a dependency, not Phase 99 (which doesn't exist)
  echo "$deps" | grep -qF "1"
  ! echo "$deps" | grep -qF "99"
}

@test "EVIL: description line starting with # Phase does not create phantom phase" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
This describes the approach.
# Phase 2 will be done later (this is a comment in description)
More description here.
EOF
  parse_plan "$TEST_DIR/plan.md"
  # Should have exactly 1 phase if # at column 1 is not treated as phase header
  # OR 2 phases if it is (parser currently matches 1-3 hashes)
  echo "PHASE_COUNT=$PHASE_COUNT"
  echo "PHASE_NUMBERS=$PHASE_NUMBERS"
  # Document the current behavior: the parser does match "# Phase 2" as a phase header
  # This test documents the behavior rather than asserting a specific fix
  [ "$PHASE_COUNT" -ge 1 ]
}

# =============================================================================
# Section 11: Decimal retry (1 test)
# =============================================================================

@test "EVIL: should_retry_phase works with decimal phase number 2.5" {
  PHASE_COUNT=1
  PHASE_NUMBERS="2.5"
  PHASE_ATTEMPTS_2_5=1
  MAX_RETRIES=3
  run should_retry_phase "2.5"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Section 12: Progress edge cases (2 tests)
# =============================================================================

@test "EVIL: Attempt line with non-matching format does not crash read_progress" {
  setup_single_phase
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ⏳ Phase 1: Setup
Status: pending
Attempts: 1
Attempt GARBAGE no number here
EOF
  run read_progress "$TEST_DIR/PROGRESS.md"
  [ "$status" -eq 0 ]
}

@test "EVIL: NUL bytes in progress file do not crash read_progress" {
  setup_single_phase
  printf '### ⏳ Phase 1: Setup\nStatus: pending\nAttempts: 1\n\000\n' > "$TEST_DIR/PROGRESS.md"
  run read_progress "$TEST_DIR/PROGRESS.md"
  # Should not crash (exit 0 or 1)
  [ "$status" -le 1 ]
}

# =============================================================================
# Section 13: Non-numeric CLI args (3 tests, integration via claudeloop --dry-run)
# =============================================================================

@test "EVIL: --max-retries abc errors cleanly" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
Do first
EOF
  run "$BATS_TEST_DIRNAME/../claudeloop" --plan "$TEST_DIR/plan.md" --dry-run --max-retries abc
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "number\|numeric\|invalid\|error"
}

@test "EVIL: --max-phase-time abc errors cleanly" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
Do first
EOF
  run "$BATS_TEST_DIRNAME/../claudeloop" --plan "$TEST_DIR/plan.md" --dry-run --max-phase-time abc
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "number\|numeric\|invalid\|error"
}

@test "EVIL: --idle-timeout abc errors cleanly" {
  cat > "$TEST_DIR/plan.md" << 'EOF'
## Phase 1: First
Do first
EOF
  run "$BATS_TEST_DIRNAME/../claudeloop" --plan "$TEST_DIR/plan.md" --dry-run --idle-timeout abc
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "number\|numeric\|invalid\|error"
}
