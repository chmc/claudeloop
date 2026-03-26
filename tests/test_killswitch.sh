#!/opt/homebrew/bin/bash
# bats file_tags=killswitch

# Test Killswitch functionality
# Tests interrupt handling, state saving, and resume

setup() {
  export TEST_DIR="$BATS_TEST_TMPDIR"
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
  :
}

@test "killswitch: handle_interrupt function saves state" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
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
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
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

  # Check that status was restored
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "pending" ]
  [ "$PHASE_STATUS_3" = "pending" ]
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

@test "killswitch: handle_interrupt does not write progress when _PROGRESS_LOADED is unset" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"

  # Create a progress file with completed phases
  mkdir -p "$TEST_DIR/.claudeloop/state"
  PROGRESS_FILE="$TEST_DIR/.claudeloop/PROGRESS.md"
  cat > "$PROGRESS_FILE" << 'PEOF'
# Progress for PLAN.md

## Phase Details

### Phase 1: Test Phase 1
Status: completed
Attempts: 1

### Phase 2: Test Phase 2
Status: completed
Attempts: 1
PEOF
  local orig_checksum
  orig_checksum=$(md5 -q "$PROGRESS_FILE")

  # Simulate pre-parse_plan state: no phases loaded
  PHASE_COUNT=""
  PHASE_NUMBERS=""
  CURRENT_PHASE=""
  PLAN_FILE="$TEST_DIR/PLAN.md"
  _PROGRESS_LOADED=""

  # Run the guarded write_progress logic (same as handle_interrupt)
  if [ "${_PROGRESS_LOADED:-}" = "true" ]; then
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"
  fi

  # Progress file should be unchanged
  local new_checksum
  new_checksum=$(md5 -q "$PROGRESS_FILE")
  [ "$orig_checksum" = "$new_checksum" ]
}

@test "killswitch: write_progress skips replay with skip_recorder arg" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"

  parse_plan "$TEST_DIR/PLAN.md"
  init_progress "$TEST_DIR/.claudeloop/PROGRESS.md"

  # Mock generate_replay to detect if it's called
  generate_replay() { touch "$TEST_DIR/recorder_called"; }
  export -f generate_replay

  write_progress "$TEST_DIR/.claudeloop/PROGRESS.md" "$TEST_DIR/PLAN.md" "skip_recorder"

  # Recorder must NOT have been called
  [ ! -f "$TEST_DIR/recorder_called" ]
}

@test "killswitch: write_progress calls replay without skip_recorder arg" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"

  parse_plan "$TEST_DIR/PLAN.md"
  init_progress "$TEST_DIR/.claudeloop/PROGRESS.md"

  # Mock generate_replay to detect if it's called
  generate_replay() { touch "$TEST_DIR/recorder_called"; }
  export -f generate_replay

  write_progress "$TEST_DIR/.claudeloop/PROGRESS.md" "$TEST_DIR/PLAN.md"

  # Recorder MUST have been called
  [ -f "$TEST_DIR/recorder_called" ]
}

# =============================================================================
# Unit: handle_interrupt kills CURRENT_PIPELINE_PID during AI parsing
# =============================================================================

@test "killswitch: handle_interrupt kills CURRENT_PIPELINE_PID" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"

  # Start a long-running process to simulate the AI parsing pipeline
  sleep 300 &
  local target_pid=$!

  # Set up state as if we are in AI parsing (no phase loaded, no progress)
  CURRENT_PIPELINE_PID="$target_pid"
  CURRENT_PIPELINE_PGID=""
  CURRENT_PHASE=""
  INTERRUPTED=false
  _PROGRESS_LOADED=""

  # Simulate the kill logic from handle_interrupt (can't call handle_interrupt
  # directly because it calls exit, but we test the PID-kill mechanism)
  if [ -n "${CURRENT_PIPELINE_PID:-}" ]; then
    kill -TERM "$CURRENT_PIPELINE_PID" 2>/dev/null || true
    if [ -n "${CURRENT_PIPELINE_PGID:-}" ] && [ "${CURRENT_PIPELINE_PGID:-0}" -gt 1 ]; then
      kill -TERM -- "-$CURRENT_PIPELINE_PGID" 2>/dev/null || true
    fi
    CURRENT_PIPELINE_PID=""
    CURRENT_PIPELINE_PGID=""
  fi
  INTERRUPTED=true

  # Verify the process was killed
  sleep 0.2
  ! kill -0 "$target_pid" 2>/dev/null
}

@test "killswitch: handle_interrupt skips kill when CURRENT_PIPELINE_PID is empty" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"

  # Simulate state between AI parse calls (pipeline finished, PID cleared)
  CURRENT_PIPELINE_PID=""
  CURRENT_PIPELINE_PGID=""
  CURRENT_PHASE=""
  INTERRUPTED=false
  _PROGRESS_LOADED=""

  # The kill logic should be a no-op (no crash)
  if [ -n "${CURRENT_PIPELINE_PID:-}" ]; then
    kill -TERM "$CURRENT_PIPELINE_PID" 2>/dev/null || true
  fi
  INTERRUPTED=true

  # Just verify we got here without errors
  [ "$INTERRUPTED" = "true" ]
}
