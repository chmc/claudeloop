#!/usr/bin/env bash
# bats file_tags=phase_state

# Test Phase State Abstraction Layer
# Tests written FIRST (TDD approach)

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  . "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"

  # Set up a basic plan for testing
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Create the initial setup.

## Phase 2: Implementation
Implement the feature.

## Phase 2.5: Integration
Integrate components.

## Phase 3: Testing
Add tests.
EOF
  parse_plan "$TEST_DIR/PLAN.md"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# --- phase_get / phase_set ---

@test "phase_get: returns empty for unset field" {
  result=$(phase_get STATUS 1)
  [ -z "$result" ]
}

@test "phase_set: sets and phase_get retrieves a value" {
  phase_set STATUS 1 "pending"
  result=$(phase_get STATUS 1)
  [ "$result" = "pending" ]
}

@test "phase_set: handles decimal phase numbers" {
  phase_set STATUS 2.5 "in_progress"
  result=$(phase_get STATUS 2.5)
  [ "$result" = "in_progress" ]
}

@test "phase_set: handles values with single quotes" {
  phase_set TITLE 1 "it's a test"
  result=$(phase_get TITLE 1)
  [ "$result" = "it's a test" ]
}

@test "phase_set: handles values with double quotes" {
  phase_set TITLE 1 'say "hello"'
  result=$(phase_get TITLE 1)
  [ "$result" = 'say "hello"' ]
}

@test "phase_set: handles values with dollar signs" {
  phase_set TITLE 1 'cost is $100'
  result=$(phase_get TITLE 1)
  [ "$result" = 'cost is $100' ]
}

@test "phase_set: handles values with backticks" {
  phase_set TITLE 1 'run `cmd` now'
  result=$(phase_get TITLE 1)
  [ "$result" = 'run `cmd` now' ]
}

@test "phase_set: handles values with backslashes" {
  phase_set TITLE 1 'path\to\file'
  result=$(phase_get TITLE 1)
  [ "$result" = 'path\to\file' ]
}

@test "phase_set: handles empty values" {
  phase_set START_TIME 1 "2024-01-01"
  phase_set START_TIME 1 ""
  result=$(phase_get START_TIME 1)
  [ -z "$result" ]
}

# --- Compound keys (attempt_num) ---

@test "phase_get: supports compound keys with attempt_num" {
  phase_set ATTEMPT_TIME 1 "2024-01-01 10:00:00" 3
  result=$(phase_get ATTEMPT_TIME 1 3)
  [ "$result" = "2024-01-01 10:00:00" ]
}

@test "phase_set: multiple attempt times on same phase" {
  phase_set ATTEMPT_TIME 2 "10:00" 1
  phase_set ATTEMPT_TIME 2 "11:00" 2
  phase_set ATTEMPT_TIME 2 "12:00" 3
  [ "$(phase_get ATTEMPT_TIME 2 1)" = "10:00" ]
  [ "$(phase_get ATTEMPT_TIME 2 2)" = "11:00" ]
  [ "$(phase_get ATTEMPT_TIME 2 3)" = "12:00" ]
}

# --- Convenience getters ---

@test "get_phase_status: returns status" {
  phase_set STATUS 1 "completed"
  result=$(get_phase_status 1)
  [ "$result" = "completed" ]
}

@test "get_phase_attempts: returns attempt count" {
  phase_set ATTEMPTS 2 "3"
  result=$(get_phase_attempts 2)
  [ "$result" = "3" ]
}

@test "get_phase_start_time: returns start time" {
  phase_set START_TIME 1 "2024-01-01 10:00:00"
  result=$(get_phase_start_time 1)
  [ "$result" = "2024-01-01 10:00:00" ]
}

@test "get_phase_end_time: returns end time" {
  phase_set END_TIME 1 "2024-01-01 11:00:00"
  result=$(get_phase_end_time 1)
  [ "$result" = "2024-01-01 11:00:00" ]
}

@test "get_phase_fail_reason: returns fail reason" {
  phase_set FAIL_REASON 1 "no_write_actions"
  result=$(get_phase_fail_reason 1)
  [ "$result" = "no_write_actions" ]
}

@test "get_phase_attempt_time: returns attempt time" {
  phase_set ATTEMPT_TIME 2 "2024-01-01 12:00:00" 2
  result=$(get_phase_attempt_time 2 2)
  [ "$result" = "2024-01-01 12:00:00" ]
}

# --- reset_phase_for_retry ---

@test "reset_phase_for_retry: decrements attempts and sets pending" {
  phase_set STATUS 1 "failed"
  phase_set ATTEMPTS 1 "3"
  phase_set START_TIME 1 "2024-01-01 10:00:00"
  phase_set ATTEMPT_TIME 1 "2024-01-01 10:00:00" 3
  reset_phase_for_retry 1
  [ "$(get_phase_status 1)" = "pending" ]
  [ "$(get_phase_attempts 1)" = "2" ]
  [ -z "$(get_phase_attempt_time 1 3)" ]
}

@test "reset_phase_for_retry: handles 0 attempts gracefully" {
  phase_set STATUS 1 "failed"
  phase_set ATTEMPTS 1 "0"
  reset_phase_for_retry 1
  [ "$(get_phase_status 1)" = "pending" ]
  [ "$(get_phase_attempts 1)" = "0" ]
}

@test "reset_phase_for_retry: does NOT call write_progress" {
  # Caller controls timing of write_progress
  phase_set STATUS 1 "failed"
  phase_set ATTEMPTS 1 "2"
  # If it tried to call write_progress, it would fail since PROGRESS_FILE isn't set
  reset_phase_for_retry 1
  [ "$(get_phase_status 1)" = "pending" ]
}

# --- reset_phase_full ---

@test "reset_phase_full: resets all fields to defaults" {
  phase_set STATUS 1 "completed"
  phase_set ATTEMPTS 1 "5"
  phase_set START_TIME 1 "2024-01-01"
  phase_set END_TIME 1 "2024-01-02"
  phase_set FAIL_REASON 1 "no_session"
  reset_phase_full 1
  [ "$(get_phase_status 1)" = "pending" ]
  [ "$(get_phase_attempts 1)" = "0" ]
  [ -z "$(get_phase_start_time 1)" ]
  [ -z "$(get_phase_end_time 1)" ]
  [ -z "$(get_phase_fail_reason 1)" ]
}

# --- old_phase_get / old_phase_set ---

@test "old_phase_set: sets _OLD_PHASE_ namespace" {
  old_phase_set TITLE 1 "Old Setup"
  result=$(old_phase_get TITLE 1)
  [ "$result" = "Old Setup" ]
}

@test "old_phase_set: uses DEPS field name (not DEPENDENCIES)" {
  old_phase_set DEPS 1 "2 3"
  result=$(old_phase_get DEPS 1)
  [ "$result" = "2 3" ]
}

@test "old_phase_set: handles single quotes in values" {
  old_phase_set TITLE 1 "it's old"
  result=$(old_phase_get TITLE 1)
  [ "$result" = "it's old" ]
}

@test "old_phase_get: compound keys with attempt_num" {
  old_phase_set ATTEMPT_TIME 1 "09:00" 2
  result=$(old_phase_get ATTEMPT_TIME 1 2)
  [ "$result" = "09:00" ]
}

@test "old_phase_set: all standard field names" {
  old_phase_set STATUS 1 "completed"
  old_phase_set ATTEMPTS 1 "3"
  old_phase_set START_TIME 1 "2024-01-01"
  old_phase_set END_TIME 1 "2024-01-02"
  old_phase_set DEPS 1 "2"
  [ "$(old_phase_get STATUS 1)" = "completed" ]
  [ "$(old_phase_get ATTEMPTS 1)" = "3" ]
  [ "$(old_phase_get START_TIME 1)" = "2024-01-01" ]
  [ "$(old_phase_get END_TIME 1)" = "2024-01-02" ]
  [ "$(old_phase_get DEPS 1)" = "2" ]
}

# --- Integration with parser.sh getters ---

@test "get_phase_title: still works after phase_state loaded" {
  # get_phase_title is defined in parser.sh - verify no conflicts
  result=$(get_phase_title 1)
  [ "$result" = "Setup" ]
}

@test "get_phase_description: still works after phase_state loaded" {
  result=$(get_phase_description 1)
  echo "$result" | grep -q "Create the initial setup"
}

@test "get_phase_dependencies: still works after phase_state loaded" {
  # Phase 1 has no deps
  result=$(get_phase_dependencies 1)
  [ -z "$result" ]
}
