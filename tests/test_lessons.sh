#!/usr/bin/env bats
# bats file_tags=lessons

# Unit tests for lib/lessons.sh

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  export TEST_DIR

  # Source libraries in dependency order
  . "$CLAUDELOOP_DIR/lib/parser.sh"
  . "$CLAUDELOOP_DIR/lib/phase_state.sh"
  . "$CLAUDELOOP_DIR/lib/ui.sh"
  . "$CLAUDELOOP_DIR/lib/lessons.sh"

  # Defaults
  SIMPLE_MODE=false
  LIVE_LOG=""

  # Set up minimal 2-phase plan
  PHASE_COUNT=2
  PHASE_NUMBERS="1 2"
  PHASE_TITLE_1="Setup"
  PHASE_DESCRIPTION_1="Initialize"
  PHASE_DEPENDENCIES_1=""
  PHASE_TITLE_2="Build"
  PHASE_DESCRIPTION_2="Build it"
  PHASE_DEPENDENCIES_2=""

  cd "$TEST_DIR"
  mkdir -p .claudeloop
}

# =============================================================================
# lessons_init
# =============================================================================

@test "lessons_init: creates lessons.md file" {
  lessons_init

  [ -f .claudeloop/lessons.md ]
}

@test "lessons_init: clears existing lessons.md" {
  mkdir -p .claudeloop
  echo "old content" > .claudeloop/lessons.md

  lessons_init

  [ -f .claudeloop/lessons.md ]
  [ ! -s .claudeloop/lessons.md ] || [ "$(cat .claudeloop/lessons.md)" = "" ]
}

@test "lessons_init: creates .claudeloop directory if missing" {
  rm -rf .claudeloop

  lessons_init

  [ -d .claudeloop ]
  [ -f .claudeloop/lessons.md ]
}

# =============================================================================
# lessons_write_phase - success case
# =============================================================================

@test "lessons_write_phase: writes success phase with correct format" {
  lessons_init
  phase_set ATTEMPTS "1" "1"

  lessons_write_phase "1" "Setup" 45 "success"

  [ -f .claudeloop/lessons.md ]
  grep -q "## Phase 1: Setup" .claudeloop/lessons.md
  grep -q "retries: 0" .claudeloop/lessons.md
  grep -q "duration: 45s" .claudeloop/lessons.md
  grep -q "exit: success" .claudeloop/lessons.md
}

@test "lessons_write_phase: retries = attempts - 1" {
  lessons_init
  phase_set ATTEMPTS "1" "3"

  lessons_write_phase "1" "Setup" 120 "success"

  grep -q "retries: 2" .claudeloop/lessons.md
}

@test "lessons_write_phase: zero retries when attempts is 1" {
  lessons_init
  phase_set ATTEMPTS "1" "1"

  lessons_write_phase "1" "Setup" 60 "success"

  grep -q "retries: 0" .claudeloop/lessons.md
}

# =============================================================================
# lessons_write_phase - failure case
# =============================================================================

@test "lessons_write_phase: writes error phase with correct format" {
  lessons_init
  phase_set ATTEMPTS "2" "5"

  lessons_write_phase "2" "Build" 312 "error"

  grep -q "## Phase 2: Build" .claudeloop/lessons.md
  grep -q "retries: 4" .claudeloop/lessons.md
  grep -q "duration: 312s" .claudeloop/lessons.md
  grep -q "exit: error" .claudeloop/lessons.md
}

# =============================================================================
# lessons_write_phase - multiple phases
# =============================================================================

@test "lessons_write_phase: appends multiple phases" {
  lessons_init
  phase_set ATTEMPTS "1" "1"
  phase_set ATTEMPTS "2" "2"

  lessons_write_phase "1" "Setup" 45 "success"
  lessons_write_phase "2" "Build" 180 "success"

  # Both phases present
  grep -q "## Phase 1: Setup" .claudeloop/lessons.md
  grep -q "## Phase 2: Build" .claudeloop/lessons.md

  # Count section headers
  local count
  count=$(grep -c "^## Phase" .claudeloop/lessons.md)
  [ "$count" -eq 2 ]
}

# =============================================================================
# lessons_write_phase - edge cases
# =============================================================================

@test "lessons_write_phase: handles zero duration" {
  lessons_init
  phase_set ATTEMPTS "1" "1"

  lessons_write_phase "1" "Quick" 0 "success"

  grep -q "duration: 0s" .claudeloop/lessons.md
}

@test "lessons_write_phase: handles decimal phase numbers" {
  lessons_init
  phase_set ATTEMPTS "2.5" "1"

  lessons_write_phase "2.5" "Substep" 30 "success"

  grep -q "## Phase 2.5: Substep" .claudeloop/lessons.md
}

@test "lessons_write_phase: handles missing attempts (defaults to 0 retries)" {
  lessons_init
  # Don't set ATTEMPTS

  lessons_write_phase "1" "NoAttempts" 10 "success"

  grep -q "retries: 0" .claudeloop/lessons.md
}

@test "lessons_write_phase: handles title with special characters" {
  lessons_init
  phase_set ATTEMPTS "1" "1"

  lessons_write_phase "1" "Setup: Initialize & Configure" 30 "success"

  grep -q "## Phase 1: Setup: Initialize & Configure" .claudeloop/lessons.md
}
