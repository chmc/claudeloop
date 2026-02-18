#!/usr/bin/env bash
# bats file_tags=dependencies

# Tests for lib/dependencies.sh POSIX-compatible implementation

setup() {
  . "${BATS_TEST_DIRNAME}/../lib/dependencies.sh"
  # 3-phase chain: 1 (no deps), 2 (dep: 1), 3 (deps: 1 2)
  PHASE_COUNT=3
  PHASE_STATUS_1="pending"
  PHASE_STATUS_2="pending"
  PHASE_STATUS_3="pending"
  PHASE_DEPENDENCIES_1=""
  PHASE_DEPENDENCIES_2="1"
  PHASE_DEPENDENCIES_3="1 2"
}

# --- is_phase_runnable() ---

@test "is_phase_runnable: pending phase with no deps is runnable" {
  run is_phase_runnable 1
  [ "$status" -eq 0 ]
}

@test "is_phase_runnable: failed phase with no deps is runnable" {
  PHASE_STATUS_1="failed"
  run is_phase_runnable 1
  [ "$status" -eq 0 ]
}

@test "is_phase_runnable: completed phase is not runnable" {
  PHASE_STATUS_1="completed"
  run is_phase_runnable 1
  [ "$status" -eq 1 ]
}

@test "is_phase_runnable: in_progress phase is not runnable" {
  PHASE_STATUS_1="in_progress"
  run is_phase_runnable 1
  [ "$status" -eq 1 ]
}

@test "is_phase_runnable: phase with incomplete dep is not runnable" {
  run is_phase_runnable 2
  [ "$status" -eq 1 ]
}

@test "is_phase_runnable: phase with all deps completed is runnable" {
  PHASE_STATUS_1="completed"
  run is_phase_runnable 2
  [ "$status" -eq 0 ]
}

# --- find_next_phase() ---

@test "find_next_phase: returns first runnable phase number" {
  run find_next_phase
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "find_next_phase: skips completed phases" {
  PHASE_STATUS_1="completed"
  run find_next_phase
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "find_next_phase: returns exit code 1 when no runnable phase exists" {
  PHASE_STATUS_1="in_progress"
  PHASE_STATUS_2="completed"
  PHASE_STATUS_3="completed"
  run find_next_phase
  [ "$status" -eq 1 ]
}

# --- detect_dependency_cycles() ---

@test "detect_dependency_cycles: acyclic graph returns 0" {
  run detect_dependency_cycles
  [ "$status" -eq 0 ]
}

@test "detect_dependency_cycles: cycle returns 1 with error message" {
  PHASE_COUNT=2
  PHASE_DEPENDENCIES_1="2"
  PHASE_DEPENDENCIES_2="1"
  run detect_dependency_cycles
  [ "$status" -eq 1 ]
  [ -n "$output" ]
}

# --- get_blocked_phases() ---

@test "get_blocked_phases: returns phases that depend on the given phase" {
  run get_blocked_phases 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
  [[ "$output" == *"3"* ]]
}

@test "get_blocked_phases: returns empty string when no dependents" {
  run get_blocked_phases 3
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
