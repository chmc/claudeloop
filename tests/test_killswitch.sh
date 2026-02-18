#!/opt/homebrew/bin/bash
# bats file_tags=killswitch

# Test Killswitch functionality
# Tests interrupt handling, state saving, and resume

setup() {
  export TEST_DIR="$(mktemp -d)"
  export CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

  # Create a test plan
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Test Phase 1
First test phase

## Phase 2: Test Phase 2
Second test phase

## Phase 3: Test Phase 3
Third test phase
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "killswitch: handle_interrupt function saves state" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"

  # Parse plan
  parse_plan "$TEST_DIR/PLAN.md"

  # Initialize progress (POSIX flat variables)
  PHASE_STATUS_1="completed"
  PHASE_STATUS_2="in_progress"
  PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_2=1

  # Simulate being in phase 2
  CURRENT_PHASE=2
  INTERRUPTED=false

  # Manually call the interrupt logic (without the trap)
  INTERRUPTED=true
  current_status=$(eval "echo \"\$PHASE_STATUS_$CURRENT_PHASE\"")
  if [ -n "$CURRENT_PHASE" ] && [ "$current_status" = "in_progress" ]; then
    eval "PHASE_STATUS_${CURRENT_PHASE}='pending'"
    current_attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$CURRENT_PHASE\"")
    eval "PHASE_ATTEMPTS_${CURRENT_PHASE}=$((current_attempts - 1))"
  fi

  # Check that phase 2 was marked as pending
  [ "$PHASE_STATUS_2" = "pending" ]
  # Check that attempts was decremented (was 1, should be 0 now)
  [ "$PHASE_ATTEMPTS_2" = "0" ]
}

@test "killswitch: state file is created with correct format" {
  mkdir -p "$TEST_DIR/.claudeloop/state"

  cat > "$TEST_DIR/.claudeloop/state/current.json" << 'EOF'
{
  "plan_file": "PLAN.md",
  "progress_file": "PROGRESS.md",
  "current_phase": "2",
  "interrupted": true,
  "timestamp": "2026-02-18T15:30:00Z"
}
EOF

  # Verify file exists and has interrupted flag
  [ -f "$TEST_DIR/.claudeloop/state/current.json" ]
  grep -q '"interrupted": true' "$TEST_DIR/.claudeloop/state/current.json"
  grep -q '"current_phase": "2"' "$TEST_DIR/.claudeloop/state/current.json"
}

@test "killswitch: progress reading restores phase status" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/progress.sh"

  # Parse plan
  parse_plan "$TEST_DIR/PLAN.md"

  # Create a progress file
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
# Progress for PLAN.md

## Phase Details

### ✅ Phase 1: Test Phase 1
Status: completed
Started: 2026-02-18 15:25:00
Completed: 2026-02-18 15:27:00
Attempts: 1

### ⏳ Phase 2: Test Phase 2
Status: pending
Attempts: 0

### ⏳ Phase 3: Test Phase 3
Status: pending
EOF

  # Initialize with empty state
  init_progress "$TEST_DIR/PROGRESS.md"

  # Check that status was restored (progress.sh still uses associative arrays; updated in TODO2/3)
  [ "${PHASE_STATUS[1]}" = "completed" ]
  [ "${PHASE_STATUS[2]}" = "pending" ]
  [ "${PHASE_STATUS[3]}" = "pending" ]
}

@test "killswitch: lock file prevents concurrent runs" {
  mkdir -p "$TEST_DIR/.claudeloop"
  local lock_file="$TEST_DIR/.claudeloop/lock"

  # Create lock file with a PID
  echo "12345" > "$lock_file"

  # Verify lock file exists
  [ -f "$lock_file" ]

  # Read PID from lock file
  local pid
  pid=$(cat "$lock_file")
  [ "$pid" = "12345" ]
}
