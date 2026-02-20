#!/usr/bin/env bash
# bats file_tags=progress

# Tests for lib/progress.sh POSIX-compatible implementation

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
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
