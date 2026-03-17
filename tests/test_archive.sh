#!/usr/bin/env bats
# bats file_tags=archive

# Unit tests for lib/archive.sh

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  export TEST_DIR

  # Source libraries in dependency order
  . "$CLAUDELOOP_DIR/lib/parser.sh"
  . "$CLAUDELOOP_DIR/lib/phase_state.sh"
  . "$CLAUDELOOP_DIR/lib/progress.sh"
  . "$CLAUDELOOP_DIR/lib/ui.sh"
  . "$CLAUDELOOP_DIR/lib/archive.sh"

  # Defaults
  SIMPLE_MODE=false
  LIVE_LOG=""
  YES_MODE=false
  RESUME_MODE=false
  DRY_RUN=false

  # Set up minimal 2-phase plan
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Setup"
  PHASE_DESCRIPTION_1="Initialize"
  PHASE_DEPENDENCIES_1=""
  PHASE_TITLE_2="Build"
  PHASE_DESCRIPTION_2="Build it"
  PHASE_DEPENDENCIES_2=""

  PLAN_FILE="$TEST_DIR/PLAN.md"
  PROGRESS_FILE="$TEST_DIR/.claudeloop/PROGRESS.md"
  LOCK_FILE="$TEST_DIR/.claudeloop/lock"

  cd "$TEST_DIR"
}

# Helper: create typical run state
_create_run_state() {
  mkdir -p .claudeloop/state .claudeloop/logs .claudeloop/signals
  cat > .claudeloop/PROGRESS.md << 'EOF'
# Progress

### Phase 1: Setup
Status: completed
Attempts: 1

### Phase 2: Build
Status: completed
Attempts: 1
EOF
  echo '{"current_phase":"2"}' > .claudeloop/state/current.json
  echo "phase 1 log" > .claudeloop/logs/phase-1.log
  echo "phase 2 log" > .claudeloop/logs/phase-2.log
  echo "live output" > .claudeloop/live.log
  cat > "$PLAN_FILE" << 'EOF'
## Phase 1: Setup
Initialize

## Phase 2: Build
Build it
EOF
}

# =============================================================================
# archive_current_run
# =============================================================================

@test "archive_current_run: archives all run-state files into timestamped directory" {
  _create_run_state

  run archive_current_run --internal
  [ "$status" -eq 0 ]

  # Archive dir should exist
  local archive_dir
  archive_dir=$(ls -d .claudeloop/archive/*/ 2>/dev/null | head -1)
  [ -n "$archive_dir" ]

  # Archived files present
  [ -f "${archive_dir}PROGRESS.md" ]
  [ -f "${archive_dir}state/current.json" ]
  [ -d "${archive_dir}logs" ]
  [ -f "${archive_dir}plan.md" ]
  [ -f "${archive_dir}metadata.txt" ]
  [ -f "${archive_dir}live.log" ]

  # Original state moved away
  [ ! -f .claudeloop/PROGRESS.md ]
  [ ! -d .claudeloop/state ]
  [ ! -d .claudeloop/logs ]
  [ ! -f .claudeloop/live.log ]
}

@test "archive_current_run: creates correct metadata.txt with phase counts" {
  _create_run_state

  # Set up phase state for metadata generation
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"

  run archive_current_run --internal
  [ "$status" -eq 0 ]

  local archive_dir
  archive_dir=$(ls -d .claudeloop/archive/*/ 2>/dev/null | head -1)
  grep -q "phase_count=2" "${archive_dir}metadata.txt"
  grep -q "completed=2" "${archive_dir}metadata.txt"
  grep -q "plan_file=" "${archive_dir}metadata.txt"
}

@test "archive_current_run: preserves .claudeloop.conf and lock, copies conf to archive" {
  _create_run_state
  echo "BASE_DELAY=0" > .claudeloop/.claudeloop.conf
  echo "$$" > .claudeloop/lock

  run archive_current_run --internal
  [ "$status" -eq 0 ]

  # Originals preserved
  [ -f .claudeloop/.claudeloop.conf ]
  [ -f .claudeloop/lock ]

  # Config copied to archive
  local archive_dir
  archive_dir=$(ls -d .claudeloop/archive/*/ 2>/dev/null | head -1)
  [ -f "${archive_dir}.claudeloop.conf" ]
  grep -q "BASE_DELAY=0" "${archive_dir}.claudeloop.conf"
}

@test "archive_current_run: nothing to archive when no state exists" {
  mkdir -p .claudeloop
  run archive_current_run --internal
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to archive"* ]]
}

@test "archive_current_run: refuses with active lock PID (external mode)" {
  _create_run_state
  # Write a PID that looks alive (our own PID)
  echo "$$" > .claudeloop/lock

  run archive_current_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"running"* ]] || [[ "$output" == *"lock"* ]]
}

@test "archive_current_run: --internal flag skips lock check" {
  _create_run_state
  echo "$$" > .claudeloop/lock

  run archive_current_run --internal
  [ "$status" -eq 0 ]
  # Should succeed despite lock being held by us
  local archive_dir
  archive_dir=$(ls -d .claudeloop/archive/*/ 2>/dev/null | head -1)
  [ -n "$archive_dir" ]
}

@test "archive_current_run: removes stale lock and proceeds (external mode)" {
  _create_run_state
  # Write a PID that is definitely not running
  echo "99999" > .claudeloop/lock

  run archive_current_run
  [ "$status" -eq 0 ]
  local archive_dir
  archive_dir=$(ls -d .claudeloop/archive/*/ 2>/dev/null | head -1)
  [ -n "$archive_dir" ]
}

@test "archive_current_run: handles missing live-*.log gracefully" {
  _create_run_state
  rm -f .claudeloop/live.log

  run archive_current_run --internal
  [ "$status" -eq 0 ]
}

@test "archive_current_run: copies plan file (does not move original)" {
  _create_run_state

  run archive_current_run --internal
  [ "$status" -eq 0 ]

  # Original plan still exists
  [ -f "$PLAN_FILE" ]

  # Copy in archive
  local archive_dir
  archive_dir=$(ls -d .claudeloop/archive/*/ 2>/dev/null | head -1)
  [ -f "${archive_dir}plan.md" ]
}

# =============================================================================
# list_archives
# =============================================================================

@test "list_archives: prints table of archived runs" {
  _create_run_state
  archive_current_run --internal

  run list_archives
  [ "$status" -eq 0 ]
  [[ "$output" == *"20"* ]]  # contains timestamp year
}

@test "list_archives: no archived runs found" {
  mkdir -p .claudeloop
  run list_archives
  [ "$status" -eq 0 ]
  [[ "$output" == *"No archived runs"* ]]
}

@test "list_archives: handles missing metadata.txt gracefully" {
  mkdir -p .claudeloop/archive/20260316-120000
  echo "dummy" > .claudeloop/archive/20260316-120000/PROGRESS.md

  run list_archives
  [ "$status" -eq 0 ]
  [[ "$output" == *"20260316-120000"* ]]
}

# =============================================================================
# restore_archive
# =============================================================================

@test "restore_archive: moves files back and removes archive dir" {
  _create_run_state
  archive_current_run --internal

  local archive_name
  archive_name=$(ls .claudeloop/archive/ 2>/dev/null | head -1)
  [ -n "$archive_name" ]

  run restore_archive "$archive_name"
  [ "$status" -eq 0 ]

  [ -f .claudeloop/PROGRESS.md ]
  [ -d .claudeloop/logs ]
  [ -d .claudeloop/state ]
  [ ! -d ".claudeloop/archive/$archive_name" ]
}

@test "restore_archive: errors when active state exists" {
  _create_run_state
  mkdir -p .claudeloop/archive/20260316-120000
  echo "dummy" > .claudeloop/archive/20260316-120000/PROGRESS.md

  run restore_archive "20260316-120000"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Active state exists"* ]] || [[ "$output" == *"active"* ]]
}

@test "restore_archive: errors when archive not found" {
  mkdir -p .claudeloop
  run restore_archive "nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"No archive"* ]]
}

# =============================================================================
# is_run_complete
# =============================================================================

@test "is_run_complete: returns true when all phases completed" {
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"

  run is_run_complete
  [ "$status" -eq 0 ]
}

@test "is_run_complete: returns false when any phase is pending" {
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "pending"

  run is_run_complete
  [ "$status" -eq 1 ]
}

@test "is_run_complete: returns false when any phase is failed" {
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "failed"

  run is_run_complete
  [ "$status" -eq 1 ]
}

@test "is_run_complete: returns false when PHASE_COUNT is 0" {
  PHASE_COUNT=0
  PHASE_NUMBERS=""

  run is_run_complete
  [ "$status" -eq 1 ]
}

# =============================================================================
# prompt_archive_completed_run
# =============================================================================

@test "prompt_archive_completed_run: archives in YES_MODE" {
  _create_run_state
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"
  YES_MODE=true

  run prompt_archive_completed_run --internal
  [ "$status" -eq 0 ]

  # Should have archived
  local archive_dir
  archive_dir=$(ls -d .claudeloop/archive/*/ 2>/dev/null | head -1)
  [ -n "$archive_dir" ]
}

@test "prompt_archive_completed_run: skips when user says no (interactive)" {
  _create_run_state
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"

  # Use _ARCHIVE_FORCE_INTERACTIVE to bypass TTY check, pipe "n"
  run sh -c '
. "'"$CLAUDELOOP_DIR"'/lib/parser.sh"
. "'"$CLAUDELOOP_DIR"'/lib/phase_state.sh"
. "'"$CLAUDELOOP_DIR"'/lib/progress.sh"
. "'"$CLAUDELOOP_DIR"'/lib/ui.sh"
. "'"$CLAUDELOOP_DIR"'/lib/archive.sh"
SIMPLE_MODE=false
LIVE_LOG=""
YES_MODE=false
_ARCHIVE_FORCE_INTERACTIVE=1
PHASE_COUNT=2
PHASE_NUMBERS="1 2"
PHASE_TITLE_1="Setup"
PHASE_DESCRIPTION_1="Initialize"
PHASE_TITLE_2="Build"
PHASE_DESCRIPTION_2="Build it"
PLAN_FILE="'"$PLAN_FILE"'"
PROGRESS_FILE="'"$PROGRESS_FILE"'"
LOCK_FILE="'"$LOCK_FILE"'"
phase_set STATUS "1" "completed"
phase_set STATUS "2" "completed"
cd "'"$TEST_DIR"'"
printf "n\n" | prompt_archive_completed_run --internal
# Check state was NOT archived
if [ -f .claudeloop/PROGRESS.md ]; then exit 0; else exit 1; fi
'
  [ "$status" -eq 0 ]
}

# =============================================================================
# run_ai_parsing: all-completed progress skips re-parse prompt (Bug fix)
# =============================================================================

@test "all-completed progress file detected by grep check" {
  _create_run_state  # all "Status: completed"
  RESET_PROGRESS=false

  # Run the grep logic from run_ai_parsing inline
  _sc=$(grep -c "^Status: " "$PROGRESS_FILE" 2>/dev/null) || _sc=0
  [ "$_sc" -gt 0 ]
  # No non-completed status lines → grep -qv should fail (exit 1)
  run sh -c 'grep "^Status: " "'"$PROGRESS_FILE"'" | grep -qv "^Status: completed"'
  [ "$status" -eq 1 ]
}

@test "partial-completed progress file not detected as all-complete" {
  mkdir -p .claudeloop
  cat > "$PROGRESS_FILE" << 'EOF'
# Progress

### Phase 1: Setup
Status: completed
Attempts: 1

### Phase 2: Build
Status: pending
Attempts: 0
EOF

  _sc=$(grep -c "^Status: " "$PROGRESS_FILE" 2>/dev/null) || _sc=0
  [ "$_sc" -gt 0 ]
  # Has non-completed status → grep -qv should succeed (exit 0)
  run sh -c 'grep "^Status: " "'"$PROGRESS_FILE"'" | grep -qv "^Status: completed"'
  [ "$status" -eq 0 ]
}

@test "empty progress file not detected as all-complete" {
  mkdir -p .claudeloop
  : > "$PROGRESS_FILE"

  _sc=$(grep -c "^Status: " "$PROGRESS_FILE" 2>/dev/null) || _sc=0
  [ "$_sc" -eq 0 ]
}

@test "archive_current_run: moves ai-verify-reason.txt to archive" {
  _create_run_state
  echo "AI verification failed: missing tests" > .claudeloop/ai-verify-reason.txt

  archive_current_run --internal

  # Moved to archive
  local _archive_dir
  _archive_dir=$(ls -d .claudeloop/archive/*/ | head -1)
  [ -f "${_archive_dir}ai-verify-reason.txt" ]
  grep -q "AI verification failed" "${_archive_dir}ai-verify-reason.txt"

  # Original removed
  [ ! -f .claudeloop/ai-verify-reason.txt ]
}

@test "archive_current_run: handles missing ai-verify-reason.txt gracefully" {
  _create_run_state
  # No ai-verify-reason.txt created

  run archive_current_run --internal
  [ "$status" -eq 0 ]
}

@test "restore_archive: skips .claudeloop.conf (snapshot only)" {
  _create_run_state
  echo "BASE_DELAY=0" > .claudeloop/.claudeloop.conf

  archive_current_run --internal

  # Remove the original conf (archive has a copy)
  rm -f .claudeloop/.claudeloop.conf

  local archive_name
  archive_name=$(ls .claudeloop/archive/ 2>/dev/null | head -1)

  # Verify the archive has the conf snapshot
  [ -f ".claudeloop/archive/${archive_name}/.claudeloop.conf" ]

  run restore_archive "$archive_name"
  [ "$status" -eq 0 ]

  # .claudeloop.conf should NOT be restored from archive
  [ ! -f .claudeloop/.claudeloop.conf ]
}

@test "archive_current_run: ai-parsed-plan.md is NOT moved (persists for reuse)" {
  mkdir -p .claudeloop/logs
  printf 'test\n' > .claudeloop/PROGRESS.md
  printf 'parsed plan content\n' > .claudeloop/ai-parsed-plan.md
  PLAN_FILE=".claudeloop/ai-parsed-plan.md"

  archive_current_run --internal

  # Plan is copied to archive as plan.md
  local _archive_dir
  _archive_dir=$(ls -d .claudeloop/archive/*/ | head -1)
  [ -f "${_archive_dir}plan.md" ]
  # ai-parsed-plan.md is NOT moved — it persists for reuse
  [ ! -f "${_archive_dir}ai-parsed-plan.md" ]
  [ -f ".claudeloop/ai-parsed-plan.md" ]
}

@test "archive_current_run: ai-parsed-plan.md persists even with external plan file" {
  _create_run_state
  printf 'parsed plan content\n' > .claudeloop/ai-parsed-plan.md

  archive_current_run --internal

  local _archive_dir
  _archive_dir=$(ls -d .claudeloop/archive/*/ | head -1)
  [ ! -f "${_archive_dir}ai-parsed-plan.md" ]
  [ -f ".claudeloop/ai-parsed-plan.md" ]
}

@test "prompt_archive_completed_run: sets _ARCHIVE_COMPLETED=true in YES_MODE" {
  _create_run_state
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"
  YES_MODE=true

  prompt_archive_completed_run --internal

  [ "$_ARCHIVE_COMPLETED" = "true" ]
}

@test "prompt_archive_completed_run: prints archiving feedback message" {
  _create_run_state
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"
  YES_MODE=true

  local _output
  _output=$(prompt_archive_completed_run --internal 2>&1)

  echo "$_output" | grep -q "Archiving completed run"
}

@test "prompt_archive_completed_run: sets _ARCHIVE_DECLINED=true when user says no" {
  _create_run_state
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"

  # Use redirect instead of pipe to avoid subshell (pipe loses variable changes)
  _ARCHIVE_FORCE_INTERACTIVE=1
  prompt_archive_completed_run --internal <<< "n"

  [ "$_ARCHIVE_DECLINED" = "true" ]
  # State should NOT be archived
  [ -f .claudeloop/PROGRESS.md ]
}

@test "prompt_archive_completed_run: preserves .claudeloop.conf after archive" {
  _create_run_state
  echo "BASE_DELAY=0" > .claudeloop/.claudeloop.conf
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"
  YES_MODE=true

  prompt_archive_completed_run --internal

  [ -f .claudeloop/.claudeloop.conf ]
}

@test "prompt_archive_completed_run: archive/ conf and parsed plan remain after archive" {
  _create_run_state
  echo "BASE_DELAY=0" > .claudeloop/.claudeloop.conf
  printf 'parsed plan\n' > .claudeloop/ai-parsed-plan.md
  phase_set STATUS "1" "completed"
  phase_set STATUS "2" "completed"
  YES_MODE=true

  prompt_archive_completed_run --internal

  # archive/, .claudeloop.conf, and ai-parsed-plan.md should remain
  local _remaining
  _remaining=$(ls -A .claudeloop/ | grep -v '^archive$' | grep -v '^\.claudeloop\.conf$' | grep -v '^ai-parsed-plan\.md$' || true)
  [ -z "$_remaining" ]
  [ -f .claudeloop/.claudeloop.conf ]
  [ -f .claudeloop/ai-parsed-plan.md ]
}

# --- archive_current_run mkdir failure ---

@test "archive_current_run: returns 1 when archive directory cannot be created" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p .claudeloop
  echo "dummy" > .claudeloop/PROGRESS.md
  PROGRESS_FILE=".claudeloop/PROGRESS.md"
  PLAN_FILE=""

  # Make archive parent read-only so mkdir fails
  mkdir -p .claudeloop/archive
  chmod 000 .claudeloop/archive

  run archive_current_run
  chmod 755 .claudeloop/archive  # restore for cleanup
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to create archive directory"* ]]
}
