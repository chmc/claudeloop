#!/usr/bin/env bash
# bats file_tags=progress

# Tests for lib/progress.sh POSIX-compatible implementation

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  . "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  . "${BATS_TEST_DIRNAME}/../lib/ui.sh"
  . "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  PHASE_COUNT=3
  PHASE_NUMBERS="1 2 3"
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

@test "read_progress: normalizes in_progress to pending" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### 🔄 Phase 1: Phase One
Status: in_progress

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "pending" ]
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

@test "update_phase_status: clears PHASE_END_TIME when transitioning to in_progress" {
  PHASE_ATTEMPTS_1=1
  PHASE_END_TIME_1="2026-02-23 10:09:03"
  update_phase_status 1 "in_progress"
  [ -z "$PHASE_END_TIME_1" ]
}

@test "generate_phase_details: shows Completed line for completed status" {
  PHASE_STATUS_1="completed"  PHASE_ATTEMPTS_1=1 PHASE_START_TIME_1="2026-02-23 10:00:00" PHASE_END_TIME_1="2026-02-23 10:05:00"
  PHASE_STATUS_2="pending"    PHASE_ATTEMPTS_2=0 PHASE_START_TIME_2=""                    PHASE_END_TIME_2=""
  PHASE_STATUS_3="pending"    PHASE_ATTEMPTS_3=0 PHASE_START_TIME_3=""                    PHASE_END_TIME_3=""
  result=$(generate_phase_details)
  echo "$result" | grep -q "Completed: 2026-02-23 10:05:00"
}

@test "generate_phase_details: does not show Completed line for in_progress status" {
  PHASE_STATUS_1="in_progress" PHASE_ATTEMPTS_1=2 PHASE_START_TIME_1="2026-02-23 10:09:08" PHASE_END_TIME_1="2026-02-23 10:09:03"
  PHASE_STATUS_2="pending"     PHASE_ATTEMPTS_2=0 PHASE_START_TIME_2=""                    PHASE_END_TIME_2=""
  PHASE_STATUS_3="pending"     PHASE_ATTEMPTS_3=0 PHASE_START_TIME_3=""                    PHASE_END_TIME_3=""
  result=$(generate_phase_details)
  ! echo "$result" | grep -q "^Completed:"
}

# --- read_old_phase_list() ---

@test "read_old_phase_list: sets _OLD_PHASE_COUNT=0 when file absent" {
  read_old_phase_list "$TEST_DIR/nonexistent.md"
  [ "$_OLD_PHASE_COUNT" = "0" ]
}

@test "read_old_phase_list: returns 0 when file absent" {
  run read_old_phase_list "$TEST_DIR/nonexistent.md"
  [ "$status" -eq 0 ]
}

@test "read_old_phase_list: parses titles, statuses, and attempts" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 2

### ⏳ Phase 2: Phase Two
Status: pending
EOF
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ "$_OLD_PHASE_COUNT" = "2" ]
  [ "$_OLD_PHASE_TITLE_1" = "Phase One" ]
  [ "$_OLD_PHASE_STATUS_1" = "completed" ]
  [ "$_OLD_PHASE_ATTEMPTS_1" = "2" ]
  [ "$_OLD_PHASE_TITLE_2" = "Phase Two" ]
  [ "$_OLD_PHASE_STATUS_2" = "pending" ]
}

@test "read_old_phase_list: parses timestamps" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Started: 2026-02-18 10:00:00
Completed: 2026-02-18 10:05:00
EOF
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ "$_OLD_PHASE_START_TIME_1" = "2026-02-18 10:00:00" ]
  [ "$_OLD_PHASE_END_TIME_1" = "2026-02-18 10:05:00" ]
}

@test "read_old_phase_list: parses Depends on line" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed

### ✅ Phase 2: Phase Two
Status: completed

### ⏳ Phase 3: Phase Three
Status: pending
Depends on: Phase 1 ✅ Phase 2 ✅
EOF
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ "$_OLD_PHASE_DEPS_3" = "1 2" ]
}

@test "read_old_phase_list: normalizes in_progress to pending" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### 🔄 Phase 1: Phase One
Status: in_progress

### ⏳ Phase 2: Phase Two
Status: pending
EOF
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ "$_OLD_PHASE_STATUS_1" = "pending" ]
}

@test "read_old_phase_list: sets count=0 for empty file" {
  touch "$TEST_DIR/PROGRESS.md"
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ "$_OLD_PHASE_COUNT" = "0" ]
}

# --- detect_plan_changes() ---

@test "detect_plan_changes: no-op when progress file absent" {
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  detect_plan_changes "$TEST_DIR/nonexistent.md" > "$TEST_DIR/out.txt" 2>&1
  [ ! -s "$TEST_DIR/out.txt" ]
  [ "$PHASE_STATUS_1" = "pending" ]
}

@test "detect_plan_changes: silent when plan unchanged; carries statuses forward" {
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 1

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > "$TEST_DIR/out.txt" 2>&1
  [ ! -s "$TEST_DIR/out.txt" ]
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "pending" ]
}

@test "detect_plan_changes: reports renumbered phase and carries status" {
  # New plan has phases swapped: Phase Two first, then Phase One
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Phase Two"
  PHASE_TITLE_2="Phase One"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 1

### ⏳ Phase 2: Phase Two
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > "$TEST_DIR/out.txt" 2>&1
  grep -q "renumbered" "$TEST_DIR/out.txt"
  # Phase Two was old #2 (pending), now #1 → status pending
  [ "$PHASE_STATUS_1" = "pending" ]
  # Phase One was old #1 (completed), now #2 → status completed
  [ "$PHASE_STATUS_2" = "completed" ]
}

@test "detect_plan_changes: reports added phase and leaves it pending" {
  PHASE_COUNT=4
  PHASE_NUMBERS="1 2 3 4"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_TITLE_3="Phase Three"
  PHASE_TITLE_4="Phase Four"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3="" PHASE_DEPENDENCIES_4=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending" PHASE_STATUS_4="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0 PHASE_ATTEMPTS_4=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > "$TEST_DIR/out.txt" 2>&1
  grep -q "Phase added" "$TEST_DIR/out.txt"
  grep -q "Phase Four" "$TEST_DIR/out.txt"
  [ "$PHASE_STATUS_4" = "pending" ]
}

@test "detect_plan_changes: reports removed phase" {
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > "$TEST_DIR/out.txt" 2>&1
  grep -q "Phase removed" "$TEST_DIR/out.txt"
  grep -q "Phase Three" "$TEST_DIR/out.txt"
}

@test "detect_plan_changes: reports dependency change" {
  PHASE_COUNT=3
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_TITLE_3="Phase Three"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3="2"
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ⏳ Phase 1: Phase One
Status: pending

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > "$TEST_DIR/out.txt" 2>&1
  grep -q "Dependencies changed" "$TEST_DIR/out.txt"
  grep -q "Phase Three" "$TEST_DIR/out.txt"
}

@test "detect_plan_changes: no dep change reported when same deps after renumbering" {
  # Old: Phase Three depends on Phase One (old #1); New: Phase Three depends on Phase One (now #2)
  PHASE_COUNT=3
  PHASE_TITLE_1="Phase Two"
  PHASE_TITLE_2="Phase One"
  PHASE_TITLE_3="Phase Three"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3="2"
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ⏳ Phase 1: Phase One
Status: pending

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
Depends on: Phase 1 ⏳
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > "$TEST_DIR/out.txt" 2>&1
  ! grep -q "Dependencies changed" "$TEST_DIR/out.txt"
}

@test "detect_plan_changes: carries attempts and timestamps for matched phases" {
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  PHASE_START_TIME_1="" PHASE_END_TIME_1=""
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Started: 2026-02-18 10:00:00
Completed: 2026-02-18 10:05:00
Attempts: 3

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_ATTEMPTS_1" = "3" ]
  [ "$PHASE_START_TIME_1" = "2026-02-18 10:00:00" ]
  [ "$PHASE_END_TIME_1" = "2026-02-18 10:05:00" ]
}

@test "detect_plan_changes: duplicate title — first old match wins" {
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase One"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 1

### ❌ Phase 2: Phase One
Status: failed
Attempts: 2
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "failed" ]
}

@test "detect_plan_changes: no output when nothing changed" {
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ⏳ Phase 1: Phase One
Status: pending

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > "$TEST_DIR/out.txt" 2>&1
  [ ! -s "$TEST_DIR/out.txt" ]
}

@test "detect_plan_changes: prints summary when changes detected" {
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase New"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 1

### ⏳ Phase 2: Phase Two
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > "$TEST_DIR/out.txt" 2>&1
  grep -q "Plan has changed since last run" "$TEST_DIR/out.txt"
}

# --- Decimal phase number tests ---

setup_decimal_progress() {
  PHASE_COUNT=4
  PHASE_NUMBERS="1 2 2.5 3"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_TITLE_2_5="Phase Two Point Five"
  PHASE_TITLE_3="Phase Three"
  PHASE_DEPENDENCIES_1=""
  PHASE_DEPENDENCIES_2=""
  PHASE_DEPENDENCIES_2_5="2"
  PHASE_DEPENDENCIES_3="2.5"
}

@test "init_progress: initializes decimal phase to pending" {
  setup_decimal_progress
  init_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_2_5" = "pending" ]
  [ "$PHASE_ATTEMPTS_2_5" = "0" ]
}

@test "write_progress: includes decimal phase in output" {
  setup_decimal_progress
  PHASE_STATUS_1="completed" PHASE_ATTEMPTS_1=1
  PHASE_STATUS_2="completed" PHASE_ATTEMPTS_2=1
  PHASE_STATUS_2_5="pending"  PHASE_ATTEMPTS_2_5=0
  PHASE_STATUS_3="pending"   PHASE_ATTEMPTS_3=0
  write_progress "$TEST_DIR/PROGRESS.md" "PLAN.md"
  grep -q "Phase 2.5" "$TEST_DIR/PROGRESS.md"
}

@test "read_progress: restores decimal phase status" {
  setup_decimal_progress
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed

### ✅ Phase 2: Phase Two
Status: completed

### ⏳ Phase 2.5: Phase Two Point Five
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2_5" = "pending" ]
}

@test "update_phase_status: updates decimal phase status" {
  setup_decimal_progress
  PHASE_STATUS_2_5="pending"
  PHASE_ATTEMPTS_2_5=0
  update_phase_status "2.5" "in_progress"
  [ "$PHASE_STATUS_2_5" = "in_progress" ]
  [ "$PHASE_ATTEMPTS_2_5" = "1" ]
}

@test "write_progress then read_progress: decimal round-trip stable" {
  setup_decimal_progress
  PHASE_STATUS_1="completed"   PHASE_ATTEMPTS_1=1
  PHASE_STATUS_2="completed"   PHASE_ATTEMPTS_2=1
  PHASE_STATUS_2_5="completed" PHASE_ATTEMPTS_2_5=2
  PHASE_STATUS_3="pending"     PHASE_ATTEMPTS_3=0
  write_progress "$TEST_DIR/PROGRESS.md" "PLAN.md"
  PHASE_STATUS_2_5="pending" PHASE_ATTEMPTS_2_5=0
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_2_5" = "completed" ]
  [ "$PHASE_ATTEMPTS_2_5" = "2" ]
}

# --- Per-attempt start times ---

@test "update_phase_status: records attempt 1 start time in attempt_time_1" {
  PHASE_ATTEMPTS_1=0
  update_phase_status 1 "in_progress"
  [ -n "$PHASE_ATTEMPT_TIME_1_1" ]
}

@test "update_phase_status: records attempt 2 start time in attempt_time_2 on retry" {
  PHASE_ATTEMPTS_1=1
  update_phase_status 1 "in_progress"
  [ -n "$PHASE_ATTEMPT_TIME_1_2" ]
}

@test "update_phase_status: clears stale attempt_time on decrement (simulate interrupt)" {
  # Simulate: 2 attempts recorded, but attempt_time_2 was cleared (interrupt during attempt 2).
  # generate_phase_details must emit "Attempt 1 Started" but skip the empty attempt 2 time.
  PHASE_STATUS_1="failed"     PHASE_ATTEMPTS_1=2    PHASE_START_TIME_1="2026-02-22 10:00:00" PHASE_END_TIME_1="2026-02-22 10:10:00"
  PHASE_STATUS_2="pending"    PHASE_ATTEMPTS_2=0    PHASE_START_TIME_2=""                    PHASE_END_TIME_2=""
  PHASE_STATUS_3="pending"    PHASE_ATTEMPTS_3=0    PHASE_START_TIME_3=""                    PHASE_END_TIME_3=""
  PHASE_ATTEMPT_TIME_1_1="2026-02-22 10:00:00"
  PHASE_ATTEMPT_TIME_1_2=""  # cleared by decrement
  result=$(generate_phase_details)
  echo "$result" | grep -q "Attempt 1 Started: 2026-02-22 10:00:00"
  ! echo "$result" | grep -q "Attempt 2 Started"
}

@test "generate_phase_details: includes Attempt N Started lines when attempts > 1" {
  PHASE_STATUS_1="failed"     PHASE_ATTEMPTS_1=2    PHASE_START_TIME_1="2026-02-22 10:00:00" PHASE_END_TIME_1="2026-02-22 10:10:00"
  PHASE_STATUS_2="pending"    PHASE_ATTEMPTS_2=0    PHASE_START_TIME_2=""                    PHASE_END_TIME_2=""
  PHASE_STATUS_3="pending"    PHASE_ATTEMPTS_3=0    PHASE_START_TIME_3=""                    PHASE_END_TIME_3=""
  PHASE_ATTEMPT_TIME_1_1="2026-02-22 10:00:00"
  PHASE_ATTEMPT_TIME_1_2="2026-02-22 10:05:00"
  result=$(generate_phase_details)
  echo "$result" | grep -q "Attempt 1 Started: 2026-02-22 10:00:00"
  echo "$result" | grep -q "Attempt 2 Started: 2026-02-22 10:05:00"
}

@test "read_progress: restores per-attempt start times" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ❌ Phase 1: Phase One
Status: failed
Started: 2026-02-22 10:00:00
Attempts: 2
Attempt 1 Started: 2026-02-22 10:00:00
Attempt 2 Started: 2026-02-22 10:05:00
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_ATTEMPT_TIME_1_1" = "2026-02-22 10:00:00" ]
  [ "$PHASE_ATTEMPT_TIME_1_2" = "2026-02-22 10:05:00" ]
}

@test "detect_plan_changes: transfers per-attempt times to matched phase" {
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ❌ Phase 1: Phase One
Status: failed
Started: 2026-02-22 10:00:00
Attempts: 2
Attempt 1 Started: 2026-02-22 10:00:00
Attempt 2 Started: 2026-02-22 10:05:00

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_ATTEMPT_TIME_1_1" = "2026-02-22 10:00:00" ]
  [ "$PHASE_ATTEMPT_TIME_1_2" = "2026-02-22 10:05:00" ]
}

# --- Fix 1: Unmatched phases must be reset ---

@test "detect_plan_changes: all unmatched phases reset to pending (collision bug)" {
  # Simulate: old PROGRESS.md had 6 completed phases with different titles
  PHASE_COUNT=6
  PHASE_NUMBERS="1 2 3 4 5 6"
  PHASE_TITLE_1="New Alpha"
  PHASE_TITLE_2="New Beta"
  PHASE_TITLE_3="New Gamma"
  PHASE_TITLE_4="New Delta"
  PHASE_TITLE_5="New Epsilon"
  PHASE_TITLE_6="New Zeta"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3=""
  PHASE_DEPENDENCIES_4="" PHASE_DEPENDENCIES_5="" PHASE_DEPENDENCIES_6=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_STATUS_4="pending" PHASE_STATUS_5="pending" PHASE_STATUS_6="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  PHASE_ATTEMPTS_4=0 PHASE_ATTEMPTS_5=0 PHASE_ATTEMPTS_6=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Old Alpha
Status: completed
Started: 2026-03-01 10:00:00
Completed: 2026-03-01 10:05:00
Attempts: 1

### ✅ Phase 2: Old Beta
Status: completed
Started: 2026-03-01 10:10:00
Completed: 2026-03-01 10:15:00
Attempts: 1

### ✅ Phase 3: Old Gamma
Status: completed
Started: 2026-03-01 10:20:00
Completed: 2026-03-01 10:25:00
Attempts: 1

### ✅ Phase 4: Old Delta
Status: completed
Started: 2026-03-01 10:30:00
Completed: 2026-03-01 10:35:00
Attempts: 1

### ✅ Phase 5: Old Epsilon
Status: completed
Started: 2026-03-01 10:40:00
Completed: 2026-03-01 10:45:00
Attempts: 1

### ✅ Phase 6: Old Zeta
Status: completed
Started: 2026-03-01 10:50:00
Completed: 2026-03-01 10:55:00
Attempts: 1
EOF
  # init_progress reads by number, polluting PHASE_STATUS with old "completed" values
  init_progress "$TEST_DIR/PROGRESS.md"
  # detect_plan_changes should reset all unmatched phases
  YES_MODE=true
  detect_plan_changes "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "pending" ]
  [ "$PHASE_STATUS_2" = "pending" ]
  [ "$PHASE_STATUS_3" = "pending" ]
  [ "$PHASE_STATUS_4" = "pending" ]
  [ "$PHASE_STATUS_5" = "pending" ]
  [ "$PHASE_STATUS_6" = "pending" ]
  [ "$PHASE_ATTEMPTS_1" = "0" ]
  [ "$PHASE_ATTEMPTS_2" = "0" ]
}

@test "detect_plan_changes: mixed — matched keep status, unmatched reset" {
  PHASE_COUNT=6
  PHASE_NUMBERS="1 2 3 4 5 6"
  PHASE_TITLE_1="Keep One"
  PHASE_TITLE_2="Keep Two"
  PHASE_TITLE_3="Keep Three"
  PHASE_TITLE_4="New Four"
  PHASE_TITLE_5="New Five"
  PHASE_TITLE_6="New Six"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3=""
  PHASE_DEPENDENCIES_4="" PHASE_DEPENDENCIES_5="" PHASE_DEPENDENCIES_6=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_STATUS_4="pending" PHASE_STATUS_5="pending" PHASE_STATUS_6="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  PHASE_ATTEMPTS_4=0 PHASE_ATTEMPTS_5=0 PHASE_ATTEMPTS_6=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Keep One
Status: completed
Started: 2026-03-01 10:00:00
Completed: 2026-03-01 10:05:00
Attempts: 2

### ✅ Phase 2: Keep Two
Status: completed
Attempts: 1

### ❌ Phase 3: Keep Three
Status: failed
Attempts: 3

### ✅ Phase 4: Old Four
Status: completed
Attempts: 1

### ✅ Phase 5: Old Five
Status: completed
Attempts: 1

### ✅ Phase 6: Old Six
Status: completed
Attempts: 1
EOF
  init_progress "$TEST_DIR/PROGRESS.md"
  detect_plan_changes "$TEST_DIR/PROGRESS.md"
  # Matched phases keep their status
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_ATTEMPTS_1" = "2" ]
  [ "$PHASE_STATUS_2" = "completed" ]
  [ "$PHASE_STATUS_3" = "failed" ]
  [ "$PHASE_ATTEMPTS_3" = "3" ]
  # Unmatched phases reset
  [ "$PHASE_STATUS_4" = "pending" ]
  [ "$PHASE_ATTEMPTS_4" = "0" ]
  [ "$PHASE_STATUS_5" = "pending" ]
  [ "$PHASE_STATUS_6" = "pending" ]
}

# --- Fix 2: Backup + drastic change guard ---

@test "detect_plan_changes: creates .bak when changes detected" {
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="New Phase"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed

### ⏳ Phase 2: Phase Two
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > /dev/null 2>&1
  [ -f "$TEST_DIR/PROGRESS.md.bak" ]
}

@test "detect_plan_changes: no .bak when no changes" {
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ⏳ Phase 1: Phase One
Status: pending

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > /dev/null 2>&1
  [ ! -f "$TEST_DIR/PROGRESS.md.bak" ]
}

@test "detect_plan_changes: drastic change warning when >50% removed, count>4" {
  # New plan has 3 phases, old had 8 — 5 removed (62.5%)
  PHASE_COUNT=3
  PHASE_NUMBERS="1 2 3"
  PHASE_TITLE_1="Alpha"
  PHASE_TITLE_2="Beta"
  PHASE_TITLE_3="Gamma"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Alpha
Status: completed

### ✅ Phase 2: Beta
Status: completed

### ✅ Phase 3: Gamma
Status: completed

### ✅ Phase 4: Delta
Status: completed

### ✅ Phase 5: Epsilon
Status: completed

### ✅ Phase 6: Zeta
Status: completed

### ✅ Phase 7: Eta
Status: completed

### ✅ Phase 8: Theta
Status: completed
EOF
  YES_MODE=true
  output=$(detect_plan_changes "$TEST_DIR/PROGRESS.md" 2>&1)
  echo "$output" | grep -q "Drastic plan change"
}

@test "detect_plan_changes: no drastic warning for minor removals" {
  # New plan has 4 phases, old had 5 — 1 removed (20%)
  PHASE_COUNT=4
  PHASE_NUMBERS="1 2 3 4"
  PHASE_TITLE_1="A"
  PHASE_TITLE_2="B"
  PHASE_TITLE_3="C"
  PHASE_TITLE_4="D"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3="" PHASE_DEPENDENCIES_4=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending" PHASE_STATUS_4="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0 PHASE_ATTEMPTS_4=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ⏳ Phase 1: A
Status: pending

### ⏳ Phase 2: B
Status: pending

### ⏳ Phase 3: C
Status: pending

### ⏳ Phase 4: D
Status: pending

### ⏳ Phase 5: E
Status: pending
EOF
  output=$(detect_plan_changes "$TEST_DIR/PROGRESS.md" 2>&1)
  ! echo "$output" | grep -q "Drastic plan change"
}

@test "detect_plan_changes: YES_MODE proceeds automatically on drastic change" {
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Alpha"
  PHASE_TITLE_2="Beta"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Alpha
Status: completed

### ✅ Phase 2: Beta
Status: completed

### ✅ Phase 3: Gamma
Status: completed

### ✅ Phase 4: Delta
Status: completed

### ✅ Phase 5: Epsilon
Status: completed
EOF
  YES_MODE=true
  run detect_plan_changes "$TEST_DIR/PROGRESS.md"
  [ "$status" -eq 0 ]
}

@test "detect_plan_changes: non-interactive aborts on drastic change" {
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Alpha"
  PHASE_TITLE_2="Beta"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Alpha
Status: completed

### ✅ Phase 2: Beta
Status: completed

### ✅ Phase 3: Gamma
Status: completed

### ✅ Phase 4: Delta
Status: completed

### ✅ Phase 5: Epsilon
Status: completed
EOF
  YES_MODE=false
  # Pipe from /dev/null to ensure non-interactive (stdin is not a TTY)
  run detect_plan_changes "$TEST_DIR/PROGRESS.md" < /dev/null
  [ "$status" -eq 1 ]
}

# --- recover_progress_from_logs() ---

setup_recovery() {
  # Source retry.sh for has_successful_session
  . "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  PHASE_COUNT=3
  PHASE_NUMBERS="1 2 3"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_TITLE_3="Phase Three"
  PHASE_DEPENDENCIES_1=""
  PHASE_DEPENDENCIES_2="1"
  PHASE_DEPENDENCIES_3="2"
  mkdir -p "$TEST_DIR/.claudeloop/logs"
}

@test "recover_progress_from_logs: completed phase (exit_code=0, VERIFICATION_PASSED)" {
  setup_recovery
  VERIFY_PHASES=true
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
some output
=== EXECUTION END exit_code=0 duration=60s time=2026-03-01T10:01:00 ===
EOF
  printf '{"type":"text","text":"VERIFICATION_PASSED"}\n' > "$TEST_DIR/.claudeloop/logs/phase-1.verify.log"
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_ATTEMPTS_1" = "1" ]
  [ "$PHASE_START_TIME_1" = "2026-03-01 10:00:00" ]
  [ "$PHASE_END_TIME_1" = "2026-03-01 10:01:00" ]
}

@test "recover_progress_from_logs: completed phase (exit_code=0, no verify.log)" {
  setup_recovery
  VERIFY_PHASES=false
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
output
=== EXECUTION END exit_code=0 duration=30s time=2026-03-01T10:00:30 ===
EOF
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_STATUS_1" = "completed" ]
}

@test "recover_progress_from_logs: failed phase (exit_code=1)" {
  setup_recovery
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
error output
=== EXECUTION END exit_code=1 duration=10s time=2026-03-01T10:00:10 ===
EOF
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_STATUS_1" = "failed" ]
}

@test "recover_progress_from_logs: failed phase (exit_code=0, VERIFICATION_FAILED)" {
  setup_recovery
  VERIFY_PHASES=true
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
output
=== EXECUTION END exit_code=0 duration=30s time=2026-03-01T10:00:30 ===
EOF
  printf '{"type":"text","text":"VERIFICATION_FAILED"}\n' > "$TEST_DIR/.claudeloop/logs/phase-1.verify.log"
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_STATUS_1" = "failed" ]
}

@test "recover_progress_from_logs: failed phase (exit_code=0, verify.log exists but no PASSED)" {
  setup_recovery
  VERIFY_PHASES=true
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
output
=== EXECUTION END exit_code=0 duration=30s time=2026-03-01T10:00:30 ===
EOF
  printf '{"type":"text","text":"some other output"}\n' > "$TEST_DIR/.claudeloop/logs/phase-1.verify.log"
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_STATUS_1" = "failed" ]
}

@test "recover_progress_from_logs: interrupted phase (no EXECUTION END) → pending" {
  setup_recovery
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
partial output...
EOF
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_STATUS_1" = "pending" ]
}

@test "recover_progress_from_logs: attempt counting from archived logs" {
  setup_recovery
  # 2 archived attempts + current = 3 total
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.attempt-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T09:00:00 ===
first try
=== EXECUTION END exit_code=1 duration=10s time=2026-03-01T09:00:10 ===
EOF
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.attempt-2.log" << 'EOF'
=== EXECUTION START phase=1 attempt=2 time=2026-03-01T09:30:00 ===
second try
=== EXECUTION END exit_code=1 duration=10s time=2026-03-01T09:30:10 ===
EOF
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=3 time=2026-03-01T10:00:00 ===
third try
=== EXECUTION END exit_code=0 duration=30s time=2026-03-01T10:00:30 ===
EOF
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_ATTEMPTS_1" = "3" ]
  [ "$PHASE_STATUS_1" = "completed" ]
}

@test "recover_progress_from_logs: phases with no logs → pending" {
  setup_recovery
  # No log files at all for phase 2 and 3
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
output
=== EXECUTION END exit_code=0 duration=30s time=2026-03-01T10:00:30 ===
EOF
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "pending" ]
  [ "$PHASE_ATTEMPTS_2" = "0" ]
  [ "$PHASE_STATUS_3" = "pending" ]
}

@test "recover_progress_from_logs: has_successful_session fallback" {
  setup_recovery
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
[Session: completed, turns=5, duration=120s]
=== EXECUTION END exit_code=1 duration=120s time=2026-03-01T10:02:00 ===
EOF
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ "$PHASE_STATUS_1" = "completed" ]
}

@test "recover_progress_from_logs: warns about unknown phase logs" {
  setup_recovery
  cat > "$TEST_DIR/.claudeloop/logs/phase-99.log" << 'EOF'
=== EXECUTION START phase=99 attempt=1 time=2026-03-01T10:00:00 ===
output
=== EXECUTION END exit_code=0 duration=30s time=2026-03-01T10:00:30 ===
EOF
  output=$(recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md" 2>&1)
  echo "$output" | grep -q "not in current plan"
}

@test "recover_progress_from_logs: writes valid PROGRESS.md" {
  setup_recovery
  cat > "$TEST_DIR/.claudeloop/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
output
=== EXECUTION END exit_code=0 duration=30s time=2026-03-01T10:00:30 ===
EOF
  cat > "$TEST_DIR/.claudeloop/logs/phase-2.log" << 'EOF'
=== EXECUTION START phase=2 attempt=1 time=2026-03-01T10:05:00 ===
output
=== EXECUTION END exit_code=1 duration=10s time=2026-03-01T10:05:10 ===
EOF
  recover_progress_from_logs "$TEST_DIR/.claudeloop" "$TEST_DIR/PROGRESS.md" "test-plan.md"
  [ -f "$TEST_DIR/PROGRESS.md" ]
  grep -q "Status: completed" "$TEST_DIR/PROGRESS.md"
  grep -q "Status: failed" "$TEST_DIR/PROGRESS.md"
  grep -q "Status: pending" "$TEST_DIR/PROGRESS.md"
}

# --- detect_plan_changes: _PLAN_HAD_CHANGES flag ---

@test "detect_plan_changes: sets _PLAN_HAD_CHANGES=true when changes found" {
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="New Phase"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed

### ⏳ Phase 2: Phase Two
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > /dev/null 2>&1
  [ "$_PLAN_HAD_CHANGES" = "true" ]
}

@test "detect_plan_changes: sets _PLAN_HAD_CHANGES=false when no changes" {
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ⏳ Phase 1: Phase One
Status: pending

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > /dev/null 2>&1
  [ "$_PLAN_HAD_CHANGES" = "false" ]
}

# --- detect_orphan_logs() ---

setup_orphan() {
  PHASE_COUNT=6
  PHASE_NUMBERS="1 2 3 4 5 6"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_TITLE_3="Phase Three"
  PHASE_TITLE_4="Phase Four"
  PHASE_TITLE_5="Phase Five"
  PHASE_TITLE_6="Phase Six"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3=""
  PHASE_DEPENDENCIES_4="" PHASE_DEPENDENCIES_5="" PHASE_DEPENDENCIES_6=""
  for _p in $PHASE_NUMBERS; do
    eval "PHASE_STATUS_$(phase_to_var "$_p")=completed"
    eval "PHASE_ATTEMPTS_$(phase_to_var "$_p")=1"
  done
  YES_MODE=false
}

@test "detect_orphan_logs: no logs dir — empty orphans, no output" {
  setup_orphan
  run detect_orphan_logs "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_orphan_logs: all logs match plan phases — no warning" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  run detect_orphan_logs "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_orphan_logs: orphan logs present (phases 7-11) — warns" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7 8 9 10 11; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  YES_MODE=true
  detect_orphan_logs "$TEST_DIR/.claudeloop" > /dev/null 2>&1
  # Check _ORPHAN_LOG_PHASES contains 7 8 9 10 11
  echo "$_ORPHAN_LOG_PHASES" | grep -q "7"
  echo "$_ORPHAN_LOG_PHASES" | grep -q "11"
}

@test "detect_orphan_logs: skips .attempt-*.log, .verify.log, .raw.json, .formatted.log" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  touch "$TEST_DIR/.claudeloop/logs/phase-1.log"
  touch "$TEST_DIR/.claudeloop/logs/phase-7.attempt-1.log"
  touch "$TEST_DIR/.claudeloop/logs/phase-7.verify.log"
  touch "$TEST_DIR/.claudeloop/logs/phase-7.raw.json"
  touch "$TEST_DIR/.claudeloop/logs/phase-7.formatted.log"
  YES_MODE=true
  detect_orphan_logs "$TEST_DIR/.claudeloop" > /dev/null 2>&1
  [ -z "$_ORPHAN_LOG_PHASES" ]
}

@test "detect_orphan_logs: decimal phase orphan phase-2.5.log detected" {
  PHASE_COUNT=3
  PHASE_NUMBERS="1 2 3"
  PHASE_TITLE_1="A" PHASE_TITLE_2="B" PHASE_TITLE_3="C"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2="" PHASE_DEPENDENCIES_3=""
  PHASE_STATUS_1="completed" PHASE_STATUS_2="completed" PHASE_STATUS_3="completed"
  PHASE_ATTEMPTS_1=1 PHASE_ATTEMPTS_2=1 PHASE_ATTEMPTS_3=1
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  touch "$TEST_DIR/.claudeloop/logs/phase-1.log"
  touch "$TEST_DIR/.claudeloop/logs/phase-2.5.log"
  YES_MODE=true
  detect_orphan_logs "$TEST_DIR/.claudeloop" > /dev/null 2>&1
  [ "$_ORPHAN_LOG_PHASES" = "2.5" ]
}

@test "detect_orphan_logs: YES_MODE continues without prompt, returns 0" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7 8; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  YES_MODE=true
  run detect_orphan_logs "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
}

@test "detect_orphan_logs: interactive recover sets _ORPHAN_RECOVERY_ACTION when ai-plan exists" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  # Create ai-parsed-plan.md so [r]ecover is offered
  printf '# Plan\n## Phase 1\nDo something\n' > "$TEST_DIR/.claudeloop/ai-parsed-plan.md"
  _ORPHAN_FORCE_TTY=true
  printf 'r\n' > "$TEST_DIR/input"
  detect_orphan_logs "$TEST_DIR/.claudeloop" < "$TEST_DIR/input" > /dev/null 2>&1
  [ "$_ORPHAN_RECOVERY_ACTION" = "recover" ]
  # Phases should be unchanged (not reset inline)
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "completed" ]
}

@test "detect_orphan_logs: recovery not offered when ai-parsed-plan.md absent" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  # No ai-parsed-plan.md → no [r]ecover option; 'r' should abort
  _ORPHAN_FORCE_TTY=true
  printf 'r\n' > "$TEST_DIR/input"
  run detect_orphan_logs "$TEST_DIR/.claudeloop" < "$TEST_DIR/input"
  [ "$status" -eq 1 ]
}

@test "detect_orphan_logs: YES_MODE sets _ORPHAN_RECOVERY_ACTION=continue" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7 8; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  YES_MODE=true
  detect_orphan_logs "$TEST_DIR/.claudeloop" > /dev/null 2>&1
  [ "$_ORPHAN_RECOVERY_ACTION" = "continue" ]
}

@test "detect_orphan_logs: interactive continue sets _ORPHAN_RECOVERY_ACTION=continue" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  _ORPHAN_FORCE_TTY=true
  printf 'c\n' > "$TEST_DIR/input"
  detect_orphan_logs "$TEST_DIR/.claudeloop" < "$TEST_DIR/input" > /dev/null 2>&1
  [ "$_ORPHAN_RECOVERY_ACTION" = "continue" ]
}

@test "detect_orphan_logs: prompt mentions plan switch when ai-parsed-plan.md exists" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  printf '# Plan\n' > "$TEST_DIR/.claudeloop/ai-parsed-plan.md"
  _ORPHAN_FORCE_TTY=true
  printf 'c\n' > "$TEST_DIR/input"
  output=$(detect_orphan_logs "$TEST_DIR/.claudeloop" < "$TEST_DIR/input" 2>&1)
  echo "$output" | grep -q "ai-parsed-plan.md"
  echo "$output" | grep -q "recover"
}

@test "detect_orphan_logs: non-interactive sets _ORPHAN_RECOVERY_ACTION=continue" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  _ORPHAN_FORCE_TTY=false
  detect_orphan_logs "$TEST_DIR/.claudeloop" < /dev/null > /dev/null 2>&1
  [ "$_ORPHAN_RECOVERY_ACTION" = "continue" ]
}

@test "detect_orphan_logs: interactive abort returns 1" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  _ORPHAN_FORCE_TTY=true
  printf 'a\n' > "$TEST_DIR/input"
  run detect_orphan_logs "$TEST_DIR/.claudeloop" < "$TEST_DIR/input"
  [ "$status" -eq 1 ]
}

@test "detect_orphan_logs: end-to-end — 6 completed + orphan logs 7-11 → orphan warning" {
  setup_orphan
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  for i in 1 2 3 4 5 6 7 8 9 10 11; do
    touch "$TEST_DIR/.claudeloop/logs/phase-${i}.log"
  done
  YES_MODE=true
  output=$(detect_orphan_logs "$TEST_DIR/.claudeloop" 2>&1)
  echo "$output" | grep -qi "orphan"
  echo "$output" | grep -q "7"
  echo "$output" | grep -q "11"
}

# =============================================================================
# Bug fix: read_progress reads last line without trailing newline
# =============================================================================

@test "read_progress: reads last phase when file has no trailing newline" {
  # printf without \n at the end — no trailing newline
  printf '### ✅ Phase 1: Phase One\nStatus: completed\nAttempts: 2\n\n### ⏳ Phase 2: Phase Two\nStatus: pending\nAttempts: 0\n\n### ❌ Phase 3: Phase Three\nStatus: failed\nAttempts: 3' > "$TEST_DIR/PROGRESS.md"
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_3" = "failed" ]
  [ "$PHASE_ATTEMPTS_3" = "3" ]
}

# =============================================================================
# Bug fix: read_old_phase_list reads last line without trailing newline
# =============================================================================

@test "read_old_phase_list: reads last phase when file has no trailing newline" {
  printf '### ✅ Phase 1: Phase One\nStatus: completed\nAttempts: 1\n\n### ❌ Phase 2: Phase Two\nStatus: failed\nAttempts: 5' > "$TEST_DIR/PROGRESS.md"
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ "$_OLD_PHASE_COUNT" -eq 2 ]
  [ "$_OLD_PHASE_STATUS_2" = "failed" ]
  [ "$_OLD_PHASE_ATTEMPTS_2" = "5" ]
}

# =============================================================================
# Refactor state persistence in PROGRESS.md
# =============================================================================

@test "generate_phase_details: writes Refactor line for non-empty REFACTOR_STATUS" {
  init_progress "$TEST_DIR/PROGRESS.md"
  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" "pending"
  local output
  output=$(generate_phase_details)
  echo "$output" | grep -q "Refactor: pending"
}

@test "generate_phase_details: writes Refactor SHA for in_progress refactor" {
  init_progress "$TEST_DIR/PROGRESS.md"
  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" "in_progress"
  phase_set REFACTOR_SHA "1" "abc123def"
  local output
  output=$(generate_phase_details)
  echo "$output" | grep -q "Refactor: in_progress"
  echo "$output" | grep -q "Refactor SHA: abc123def"
}

@test "generate_phase_details: no Refactor line when REFACTOR_STATUS is empty" {
  init_progress "$TEST_DIR/PROGRESS.md"
  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" ""
  local output
  output=$(generate_phase_details)
  ! echo "$output" | grep -q "Refactor:"
}

@test "read_progress: restores REFACTOR_STATUS and REFACTOR_SHA" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Refactor: in_progress
Refactor SHA: deadbeef123

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  init_progress "$TEST_DIR/PROGRESS.md"
  [ "$(phase_get REFACTOR_STATUS 1)" = "in_progress" ]
  [ "$(phase_get REFACTOR_SHA 1)" = "deadbeef123" ]
  [ "$(phase_get REFACTOR_STATUS 2)" = "" ]
}

@test "read_progress: does NOT normalize REFACTOR_STATUS in_progress to pending" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Refactor: in_progress
Refactor SHA: abc123
EOF
  init_progress "$TEST_DIR/PROGRESS.md"
  # Unlike STATUS which normalizes in_progress→pending, REFACTOR_STATUS must NOT
  [ "$(phase_get REFACTOR_STATUS 1)" = "in_progress" ]
}

@test "write_progress + read_progress: round-trip refactor state" {
  init_progress "$TEST_DIR/PROGRESS.md"
  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" "in_progress"
  phase_set REFACTOR_SHA "1" "sha256abc"
  phase_set STATUS "2" "completed"
  phase_set REFACTOR_STATUS "2" "completed"
  write_progress "$TEST_DIR/PROGRESS.md" "test-plan.md"
  # Reset and re-read
  phase_set REFACTOR_STATUS "1" ""
  phase_set REFACTOR_SHA "1" ""
  phase_set REFACTOR_STATUS "2" ""
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$(phase_get REFACTOR_STATUS 1)" = "in_progress" ]
  [ "$(phase_get REFACTOR_SHA 1)" = "sha256abc" ]
  [ "$(phase_get REFACTOR_STATUS 2)" = "completed" ]
}

@test "read_old_phase_list: parses Refactor and Refactor SHA" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Refactor: pending

### ✅ Phase 2: Phase Two
Status: completed
Refactor: in_progress
Refactor SHA: deadbeef
EOF
  read_old_phase_list "$TEST_DIR/PROGRESS.md"
  [ "$(old_phase_get REFACTOR_STATUS 1)" = "pending" ]
  [ "$(old_phase_get REFACTOR_SHA 1)" = "" ]
  [ "$(old_phase_get REFACTOR_STATUS 2)" = "in_progress" ]
  [ "$(old_phase_get REFACTOR_SHA 2)" = "deadbeef" ]
}

@test "detect_plan_changes: carries over REFACTOR_STATUS and REFACTOR_SHA" {
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_DEPENDENCIES_1="" PHASE_DEPENDENCIES_2=""
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 1
Refactor: pending

### ✅ Phase 2: Phase Two
Status: completed
Attempts: 1
Refactor: in_progress
Refactor SHA: abc123
EOF
  detect_plan_changes "$TEST_DIR/PROGRESS.md" > /dev/null 2>&1
  [ "$(phase_get REFACTOR_STATUS 1)" = "pending" ]
  [ "$(phase_get REFACTOR_STATUS 2)" = "in_progress" ]
  [ "$(phase_get REFACTOR_SHA 2)" = "abc123" ]
}

@test "reset_phase_full: clears REFACTOR_STATUS and REFACTOR_SHA" {
  phase_set REFACTOR_STATUS "1" "pending"
  phase_set REFACTOR_SHA "1" "abc123"
  reset_phase_full "1"
  [ "$(phase_get REFACTOR_STATUS 1)" = "" ]
  [ "$(phase_get REFACTOR_SHA 1)" = "" ]
}
