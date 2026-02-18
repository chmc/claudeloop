#!/usr/bin/env bash
# bats file_tags=progress

# Tests for lib/progress.sh POSIX-compatible implementation

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  PHASE_COUNT=3
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_TITLE_3="Phase Three"
  PHASE_DEPENDENCIES_1=""
  PHASE_DEPENDENCIES_2=""
  PHASE_DEPENDENCIES_3=""
}

teardown() {
  rm -rf "$TEST_DIR"
}

# --- init_progress() ---

@test "init_progress: sets all phases to pending" {
  init_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "pending" ]
  [ "$PHASE_STATUS_2" = "pending" ]
  [ "$PHASE_STATUS_3" = "pending" ]
}

@test "init_progress: sets all attempt counts to 0" {
  init_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_ATTEMPTS_1" = "0" ]
  [ "$PHASE_ATTEMPTS_2" = "0" ]
  [ "$PHASE_ATTEMPTS_3" = "0" ]
}

@test "init_progress: reads existing file when present" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 1

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  init_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "pending" ]
}

# --- read_progress() ---

@test "read_progress: restores phase status" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed

### ❌ Phase 2: Phase Two
Status: failed

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "failed" ]
  [ "$PHASE_STATUS_3" = "pending" ]
}

@test "read_progress: restores start and end times" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Started: 2026-02-18 10:00:00
Completed: 2026-02-18 10:05:00
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_START_TIME_1" = "2026-02-18 10:00:00" ]
  [ "$PHASE_END_TIME_1" = "2026-02-18 10:05:00" ]
}

@test "read_progress: restores attempt count" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ❌ Phase 1: Phase One
Status: failed
Attempts: 3
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_ATTEMPTS_1" = "3" ]
}

@test "read_progress: returns 0 when file does not exist" {
  run read_progress "$TEST_DIR/nonexistent.md"
  [ "$status" -eq 0 ]
}

# --- write_progress() ---

@test "write_progress: creates the progress file" {
  PHASE_STATUS_1="pending"   PHASE_ATTEMPTS_1=0
  PHASE_STATUS_2="pending"   PHASE_ATTEMPTS_2=0
  PHASE_STATUS_3="pending"   PHASE_ATTEMPTS_3=0
  write_progress "$TEST_DIR/PROGRESS.md" "PLAN.md"
  [ -f "$TEST_DIR/PROGRESS.md" ]
}

@test "write_progress: does not leave .tmp file behind (atomic write)" {
  PHASE_STATUS_1="pending"   PHASE_ATTEMPTS_1=0
  PHASE_STATUS_2="pending"   PHASE_ATTEMPTS_2=0
  PHASE_STATUS_3="pending"   PHASE_ATTEMPTS_3=0
  write_progress "$TEST_DIR/PROGRESS.md" "PLAN.md"
  [ ! -f "$TEST_DIR/PROGRESS.md.tmp" ]
}

@test "write_progress: round-trip with read_progress is stable" {
  PHASE_STATUS_1="completed" PHASE_ATTEMPTS_1=1
  PHASE_STATUS_2="failed"    PHASE_ATTEMPTS_2=2
  PHASE_STATUS_3="pending"   PHASE_ATTEMPTS_3=0
  write_progress "$TEST_DIR/PROGRESS.md" "PLAN.md"
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "failed" ]
  [ "$PHASE_ATTEMPTS_2" = "2" ]
}

# --- update_phase_status() ---

@test "update_phase_status: sets status" {
  PHASE_STATUS_1="pending" PHASE_ATTEMPTS_1=0
  update_phase_status 1 "in_progress"
  [ "$PHASE_STATUS_1" = "in_progress" ]
}

@test "update_phase_status: sets PHASE_START_TIME for in_progress" {
  PHASE_ATTEMPTS_1=0 PHASE_START_TIME_1=""
  update_phase_status 1 "in_progress"
  [ -n "$PHASE_START_TIME_1" ]
}

@test "update_phase_status: sets PHASE_END_TIME for completed" {
  PHASE_ATTEMPTS_1=0 PHASE_END_TIME_1=""
  update_phase_status 1 "completed"
  [ -n "$PHASE_END_TIME_1" ]
}

@test "update_phase_status: sets PHASE_END_TIME for failed" {
  PHASE_ATTEMPTS_1=0 PHASE_END_TIME_1=""
  update_phase_status 1 "failed"
  [ -n "$PHASE_END_TIME_1" ]
}

@test "update_phase_status: increments PHASE_ATTEMPTS for in_progress" {
  PHASE_ATTEMPTS_1=0
  update_phase_status 1 "in_progress"
  [ "$PHASE_ATTEMPTS_1" = "1" ]
}

@test "update_phase_status: increments PHASE_ATTEMPTS on second attempt" {
  PHASE_ATTEMPTS_1=1
  update_phase_status 1 "in_progress"
  [ "$PHASE_ATTEMPTS_1" = "2" ]
}
