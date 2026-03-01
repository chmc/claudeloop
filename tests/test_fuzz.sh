#!/usr/bin/env bash
# bats file_tags=fuzz,slow

# Fuzz harness: random/adversarial inputs to find unknown crashes
# Deterministic via seeded LCG PRNG (FUZZ_SEED env var, default 42)

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  . "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  . "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  . "${BATS_TEST_DIRNAME}/../lib/dependencies.sh"

  # LCG PRNG: seed-based, deterministic
  _FUZZ_STATE="${FUZZ_SEED:-42}"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# LCG PRNG: returns pseudo-random number and updates state
# Usage: fuzz_rand; result is in $_FUZZ_RESULT
fuzz_rand() {
  _FUZZ_STATE=$(( (_FUZZ_STATE * 1103515245 + 12345) % 2147483648 ))
  _FUZZ_RESULT=$(( _FUZZ_STATE / 65536 % 32768 ))
}

# Pick a random item from a list of arguments
fuzz_pick() {
  fuzz_rand
  local idx=$(( _FUZZ_RESULT % $# + 1 ))
  eval "echo \"\${$idx}\""
}

# Generate a random fuzz plan file
# Args: $1 - output file path, $2 - variant index (0-9)
generate_fuzz_plan() {
  local outfile="$1"
  local variant="$2"

  case "$variant" in
    0) # Normal plan
      cat > "$outfile" << 'EOF'
## Phase 1: Normal task
Do something normal
EOF
      ;;
    1) # Empty title
      cat > "$outfile" << 'EOF'
## Phase 1:
No title here
EOF
      ;;
    2) # Shell metacharacters in title
      cat > "$outfile" << 'EOF'
## Phase 1: $(rm -rf /) `whoami` && echo pwned
Do the thing
EOF
      ;;
    3) # Very long title (1000 chars)
      printf '## Phase 1: ' > "$outfile"
      printf 'A%.0s' $(seq 1 1000) >> "$outfile"
      printf '\nDo it\n' >> "$outfile"
      ;;
    4) # Single quotes in title
      cat > "$outfile" << 'PLAN'
## Phase 1: It's a 'quoted' "plan"
Description here
PLAN
      ;;
    5) # Self-dependency
      cat > "$outfile" << 'EOF'
## Phase 1: Self
**Depends on:** Phase 1
Do it
EOF
      ;;
    6) # Non-existent dependency
      cat > "$outfile" << 'EOF'
## Phase 1: Orphan
**Depends on:** Phase 99
Do it
EOF
      ;;
    7) # Decimal phase number
      cat > "$outfile" << 'EOF'
## Phase 1.5: Decimal
Do it
EOF
      ;;
    8) # Special chars in body
      cat > "$outfile" << 'EOF'
## Phase 1: Special
Body with $VAR and `cmd` and $(subshell) and 'quotes' and "doubles"
Backslash \ and tab	and pipe | and redirect > /dev/null
EOF
      ;;
    9) # Duplicate phase number
      cat > "$outfile" << 'EOF'
## Phase 1: First
Do first

## Phase 1: Duplicate
Do duplicate
EOF
      ;;
  esac
}

# Generate a random fuzz progress file
# Args: $1 - output file path, $2 - variant index (0-7)
generate_fuzz_progress() {
  local outfile="$1"
  local variant="$2"

  case "$variant" in
    0) # Normal
      cat > "$outfile" << 'EOF'
### ⏳ Phase 1: Task
Status: pending
Attempts: 0
EOF
      ;;
    1) # Injection in status
      cat > "$outfile" << 'EOF'
### ⏳ Phase 1: Task
Status: pending'; touch /tmp/pwned; echo '
Attempts: 0
EOF
      ;;
    2) # Non-numeric attempts
      cat > "$outfile" << 'EOF'
### ⏳ Phase 1: Task
Status: pending
Attempts: abc
EOF
      ;;
    3) # Huge attempts
      cat > "$outfile" << 'EOF'
### ⏳ Phase 1: Task
Status: pending
Attempts: 99999999999
EOF
      ;;
    4) # Missing status
      cat > "$outfile" << 'EOF'
### ⏳ Phase 1: Task
Attempts: 1
EOF
      ;;
    5) # Truncated mid-line
      printf '### ⏳ Phase 1: Task\nStatus: pen' > "$outfile"
      ;;
    6) # Command substitution in time
      cat > "$outfile" << 'EOF'
### ⏳ Phase 1: Task
Status: pending
Attempts: 1
Attempt 1 Started: $(touch /tmp/pwned)
EOF
      ;;
    7) # Empty file
      : > "$outfile"
      ;;
  esac
}

# =============================================================================
# Fuzz tests
# =============================================================================

@test "FUZZ: parse_plan survives 100 random plans (exit 0 or 1)" {
  local i=0
  while [ "$i" -lt 100 ]; do
    fuzz_rand
    local variant=$(( _FUZZ_RESULT % 10 ))
    generate_fuzz_plan "$TEST_DIR/fuzz_plan_${i}.md" "$variant"
    run parse_plan "$TEST_DIR/fuzz_plan_${i}.md"
    if [ "$status" -gt 1 ]; then
      echo "CRASH on variant $variant (iteration $i): exit status $status"
      echo "Output: $output"
      cat "$TEST_DIR/fuzz_plan_${i}.md"
      return 1
    fi
    i=$((i + 1))
  done
}

@test "FUZZ: parse_plan creates no injection side-effect files" {
  local marker_dir="$TEST_DIR/markers"
  mkdir -p "$marker_dir"
  local i=0
  while [ "$i" -lt 50 ]; do
    fuzz_rand
    local variant=$(( _FUZZ_RESULT % 10 ))
    generate_fuzz_plan "$TEST_DIR/fuzz_plan_se_${i}.md" "$variant"
    # Override marker paths that injections might target
    run parse_plan "$TEST_DIR/fuzz_plan_se_${i}.md"
    i=$((i + 1))
  done
  # Check no files were created in /tmp by injection
  [ ! -f /tmp/pwned ]
  # Check marker dir is empty
  local count
  count=$(find "$marker_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}

@test "FUZZ: read_progress survives 100 random progress files" {
  # Set up minimal phase state
  PHASE_COUNT=1
  PHASE_NUMBERS="1"
  PHASE_TITLE_1="Task"
  PHASE_STATUS_1="pending"
  PHASE_ATTEMPTS_1=0
  PHASE_START_TIME_1=""
  PHASE_END_TIME_1=""
  PHASE_DEPENDENCIES_1=""

  local i=0
  while [ "$i" -lt 100 ]; do
    fuzz_rand
    local variant=$(( _FUZZ_RESULT % 8 ))
    generate_fuzz_progress "$TEST_DIR/fuzz_progress_${i}.md" "$variant"
    # Reset state before each read
    PHASE_STATUS_1="pending"
    PHASE_ATTEMPTS_1=0
    run read_progress "$TEST_DIR/fuzz_progress_${i}.md"
    if [ "$status" -gt 1 ]; then
      echo "CRASH on variant $variant (iteration $i): exit status $status"
      echo "Output: $output"
      return 1
    fi
    i=$((i + 1))
  done
}

@test "FUZZ: calculate_backoff survives adversarial inputs" {
  local inputs="0 1 2 5 10 50 100 -1 999999"
  for val in $inputs; do
    run calculate_backoff "$val"
    if [ "$status" -gt 1 ]; then
      echo "CRASH on input '$val': exit status $status, output: $output"
      return 1
    fi
  done
  # Also test empty string
  run calculate_backoff ""
  if [ "$status" -gt 1 ]; then
    echo "CRASH on empty string: exit status $status, output: $output"
    return 1
  fi
}

@test "FUZZ: phase_less_than survives adversarial inputs" {
  # Use a temp file with values to avoid word-splitting issues with special chars
  local values="0 1 2 2.5 -1 999999999 0.0 1e5"
  for a in $values; do
    for b in $values; do
      run phase_less_than "$a" "$b"
      if [ "$status" -gt 1 ]; then
        echo "CRASH on phase_less_than '$a' '$b': exit status $status"
        return 1
      fi
    done
  done
  # Test non-numeric values individually
  run phase_less_than "abc" "1"
  [ "$status" -le 1 ]
  run phase_less_than "1" "abc"
  [ "$status" -le 1 ]
  run phase_less_than "" ""
  [ "$status" -le 1 ]
}

@test "FUZZ: claudeloop --dry-run survives 10 random plans" {
  local i=0
  while [ "$i" -lt 10 ]; do
    fuzz_rand
    local variant=$(( _FUZZ_RESULT % 10 ))
    generate_fuzz_plan "$TEST_DIR/fuzz_int_${i}.md" "$variant"
    # 5 second timeout per run
    run timeout 5 "$BATS_TEST_DIRNAME/../claudeloop" --plan "$TEST_DIR/fuzz_int_${i}.md" --dry-run 2>&1
    # Status 124 = timeout, 0 = success, 1 = expected error; >1 and not 124 = crash
    if [ "$status" -gt 1 ] && [ "$status" -ne 124 ]; then
      echo "CRASH on variant $variant (iteration $i): exit status $status"
      echo "Output: $output"
      cat "$TEST_DIR/fuzz_int_${i}.md"
      return 1
    fi
    i=$((i + 1))
  done
}
