#!/usr/bin/env bash
# bats file_tags=ui

# Tests for lib/ui.sh POSIX-compatible implementation

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"

  PHASE_COUNT=3
  PHASE_TITLE_1="Setup"
  PHASE_TITLE_2="Implementation"
  PHASE_TITLE_3="Testing"
  PHASE_STATUS_1="completed"
  PHASE_STATUS_2="in_progress"
  PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=1
  PHASE_ATTEMPTS_2=1
  PHASE_ATTEMPTS_3=0
  MAX_RETRIES=3
}

# --- print_header() ---

@test "print_header: shows plan file name" {
  run print_header "my_plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plan: my_plan.md"* ]]
}

@test "print_header: shows correct completed count" {
  run print_header "PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Progress: 1/3 phases completed"* ]]
}

@test "print_header: counts all completed phases" {
  PHASE_STATUS_1="completed"
  PHASE_STATUS_2="completed"
  PHASE_STATUS_3="completed"
  run print_header "PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Progress: 3/3 phases completed"* ]]
}

@test "print_header: zero completed when all pending" {
  PHASE_STATUS_1="pending"
  PHASE_STATUS_2="pending"
  PHASE_STATUS_3="pending"
  run print_header "PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Progress: 0/3 phases completed"* ]]
}

# --- print_phase_status() ---

@test "print_phase_status: shows checkmark for completed phase" {
  run print_phase_status 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"* ]]
}

@test "print_phase_status: shows spinner for in_progress phase" {
  run print_phase_status 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"🔄"* ]]
}

@test "print_phase_status: shows hourglass for pending phase" {
  run print_phase_status 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"⏳"* ]]
}

@test "print_phase_status: shows X for failed phase" {
  PHASE_STATUS_3="failed"
  run print_phase_status 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"❌"* ]]
}

@test "print_phase_status: shows phase title" {
  run print_phase_status 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Implementation"* ]]
}

@test "print_phase_status: shows phase number" {
  run print_phase_status 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase 2"* ]]
}

@test "print_phase_status: defaults to pending when status unset" {
  PHASE_STATUS_3=""
  run print_phase_status 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"⏳"* ]]
}

@test "print_phase_status: defaults title to Unknown when unset" {
  PHASE_TITLE_3=""
  run print_phase_status 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unknown"* ]]
}

# --- print_all_phases() ---

@test "print_all_phases: outputs all phase titles" {
  run print_all_phases
  [ "$status" -eq 0 ]
  [[ "$output" == *"Setup"* ]]
  [[ "$output" == *"Implementation"* ]]
  [[ "$output" == *"Testing"* ]]
}

@test "print_all_phases: outputs correct icons" {
  run print_all_phases
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"* ]]
  [[ "$output" == *"🔄"* ]]
  [[ "$output" == *"⏳"* ]]
}

# --- print_phase_exec_header() ---

@test "print_phase_exec_header: shows phase number and title" {
  run print_phase_exec_header 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase 2"* ]]
  [[ "$output" == *"Implementation"* ]]
}

@test "print_phase_exec_header: hides attempt line on first attempt" {
  PHASE_ATTEMPTS_2=1
  run print_phase_exec_header 2
  [ "$status" -eq 0 ]
  [[ "$output" != *"Attempt 1"* ]]
}

@test "print_phase_exec_header: shows attempt line when attempt > 1" {
  PHASE_ATTEMPTS_2=2
  run print_phase_exec_header 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Attempt 2"* ]]
}

# --- print_success() ---

@test "print_success: outputs checkmark and message" {
  run print_success "All done"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ All done"* ]]
}

# --- print_error() ---

@test "print_error: exits with status 0" {
  run print_error "Something failed"
  [ "$status" -eq 0 ]
}

# --- print_warning() ---

@test "print_warning: outputs warning icon and message" {
  run print_warning "Caution ahead"
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠ Caution ahead"* ]]
}
