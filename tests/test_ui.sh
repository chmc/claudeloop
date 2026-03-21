#!/usr/bin/env bash
# bats file_tags=ui

# Tests for lib/ui.sh POSIX-compatible implementation

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"

  PHASE_COUNT=3
  PHASE_NUMBERS="1 2 3"
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

# --- print_logo() ---

@test "print_logo: outputs logo art when SIMPLE_MODE is false" {
  SIMPLE_MODE="false"
  run print_logo
  [ "$status" -eq 0 ]
  [[ "$output" == *"claudeloop"* ]]
}

@test "print_logo: suppresses logo when SIMPLE_MODE is true" {
  SIMPLE_MODE="true"
  run print_logo
  [ "$status" -eq 0 ]
  [[ "$output" != *"claudeloop"* ]]
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

@test "print_header: shows version from VERSION variable" {
  VERSION="9.8.7"
  run print_header "PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v9.8.7"* ]]
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

@test "print_phase_exec_header: shows previous attempt times when attempt > 1" {
  PHASE_ATTEMPTS_2=3
  PHASE_ATTEMPT_TIME_2_1="2026-02-23 10:00:00"
  PHASE_ATTEMPT_TIME_2_2="2026-02-23 10:05:00"
  run print_phase_exec_header 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Attempt 1 started: 2026-02-23 10:00:00"* ]]
  [[ "$output" == *"Attempt 2 started: 2026-02-23 10:05:00"* ]]
}

# --- print_success() ---

@test "print_success: outputs checkmark and message" {
  run print_success "All done"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ All done"* ]]
}

@test "print_success: includes timestamp prefix" {
  run print_success "All done"
  [ "$status" -eq 0 ]
  [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
}

# --- print_error() ---

@test "print_error: exits with status 0" {
  run print_error "Something failed"
  [ "$status" -eq 0 ]
}

@test "print_error: includes timestamp prefix" {
  run print_error "Something failed"
  [ "$status" -eq 0 ]
  [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
}

# --- print_warning() ---

@test "print_warning: outputs warning icon and message" {
  run print_warning "Caution ahead"
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠ Caution ahead"* ]]
}

@test "print_warning: includes timestamp prefix" {
  run print_warning "Caution ahead"
  [ "$status" -eq 0 ]
  [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
}

# --- print_quota_wait() ---

@test "print_quota_wait: includes timestamp prefix" {
  run print_quota_wait 1 120
  [ "$status" -eq 0 ]
  [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
}

# --- log_live() ---

# --- print_substep_header() ---

@test "print_substep_header: outputs separator and message" {
  SIMPLE_MODE="false"
  run print_substep_header "🔍" "Verifying phase 1..."
  [ "$status" -eq 0 ]
  [[ "$output" == *"┄┄┄┄"* ]]
  [[ "$output" == *"🔍"* ]]
  [[ "$output" == *"Verifying phase 1..."* ]]
}

@test "print_substep_header: includes timestamp" {
  SIMPLE_MODE="false"
  run print_substep_header "🔍" "Verifying phase 1..."
  [ "$status" -eq 0 ]
  [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
}

@test "print_substep_header: falls back to log_ts in SIMPLE_MODE" {
  SIMPLE_MODE="true"
  run print_substep_header "🔍" "Verifying phase 1..."
  [ "$status" -eq 0 ]
  [[ "$output" != *"┄┄┄┄"* ]]
  [[ "$output" == *"Verifying phase 1..."* ]]
}

@test "print_substep_header: writes to LIVE_LOG" {
  SIMPLE_MODE="false"
  local tmplog
  tmplog=$(mktemp)
  LIVE_LOG="$tmplog"
  print_substep_header "🔍" "Verifying phase 1..."
  [[ "$(cat "$tmplog")" == *"┄┄┄┄"* ]]
  [[ "$(cat "$tmplog")" == *"Verifying phase 1..."* ]]
  rm -f "$tmplog"
}

# --- log_live() ---

@test "log_live writes timestamped entry to LIVE_LOG" {
  local tmplog
  tmplog=$(mktemp)
  LIVE_LOG="$tmplog"
  log_live "hello"
  [[ "$(cat "$tmplog")" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\]\ hello ]]
  rm -f "$tmplog"
}

# --- print_completion_summary() ---

@test "print_completion_summary: shows Run Summary header" {
  PHASE_STATUS_1="completed"
  PHASE_STATUS_2="completed"
  PHASE_STATUS_3="completed"
  run print_completion_summary "PLAN.md" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Run Summary"* ]]
  [[ "$output" == *"3/3 phases completed"* ]]
}

@test "print_completion_summary: shows plan file" {
  run print_completion_summary "my-plan.md" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plan:   my-plan.md"* ]]
}

@test "print_completion_summary: shows report path when provided" {
  run print_completion_summary "PLAN.md" ".claudeloop/archive/20260320-143022/replay.html"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Report: .claudeloop/archive/20260320-143022/replay.html"* ]]
}

@test "print_completion_summary: omits report line when path is empty" {
  run print_completion_summary "PLAN.md" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"Report:"* ]]
}

@test "print_completion_summary: counts completed phases correctly" {
  PHASE_STATUS_1="completed"
  PHASE_STATUS_2="failed"
  PHASE_STATUS_3="pending"
  run print_completion_summary "PLAN.md" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"1/3 phases completed"* ]]
}

@test "print_completion_summary: shows all phase statuses with icons" {
  PHASE_STATUS_1="completed"
  PHASE_STATUS_2="completed"
  PHASE_STATUS_3="completed"
  run print_completion_summary "PLAN.md" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"*"Setup"* ]]
  [[ "$output" == *"✅"*"Implementation"* ]]
  [[ "$output" == *"✅"*"Testing"* ]]
}

@test "print_completion_summary: indents phase lines with 2 spaces" {
  PHASE_STATUS_1="completed"
  PHASE_STATUS_2="completed"
  PHASE_STATUS_3="completed"
  run print_completion_summary "PLAN.md" ""
  [ "$status" -eq 0 ]
  # Check that phase lines start with 2-space indent
  echo "$output" | grep -q "^  .*Phase 1"
}

@test "print_completion_summary: shows separator lines" {
  run print_completion_summary "PLAN.md" ""
  [ "$status" -eq 0 ]
  # Should have 3 separator lines (top, after header, bottom)
  local count
  count=$(echo "$output" | grep -c "═══════════════════════════════════════════════════════════")
  [ "$count" -eq 3 ]
}

@test "print_completion_summary: handles zero phases" {
  PHASE_COUNT=0
  PHASE_NUMBERS=""
  run print_completion_summary "PLAN.md" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"0/0 phases completed"* ]]
}

@test "print_completion_summary: handles decimal phase numbers" {
  PHASE_COUNT=4
  PHASE_NUMBERS="1 2 2.5 3"
  PHASE_TITLE_2_5="Bugfix"
  PHASE_STATUS_2_5="completed"
  PHASE_STATUS_1="completed"
  PHASE_STATUS_2="completed"
  PHASE_STATUS_3="completed"
  run print_completion_summary "PLAN.md" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"4/4 phases completed"* ]]
  [[ "$output" == *"Bugfix"* ]]
}

@test "log_live writes blank line for empty string" {
  local tmplog
  tmplog=$(mktemp)
  LIVE_LOG="$tmplog"
  log_live ""
  # empty string: should write a bare newline, no timestamp
  ! grep -q '\[' "$tmplog"
  rm -f "$tmplog"
}
