#!/usr/bin/env bash
# bats file_tags=integration

# Integration tests for claudeloop
# Uses a stub 'claude' binary and a temporary git repo.
# .claudeloop.conf sets BASE_DELAY=0 so retry tests run instantly.

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

# Write the stub claude script into TEST_DIR/bin/
_write_claude_stub() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/claude" << EOF
#!/bin/sh
count_file="${dir}/claude_call_count"
count=\$(cat "\$count_file" 2>/dev/null || echo 0)
count=\$((count + 1))
printf '%s\n' "\$count" > "\$count_file"
printf 'stub output for call %s\n' "\$count"
exit_codes_file="${dir}/claude_exit_codes"
exit_code=0
if [ -f "\$exit_codes_file" ]; then
    exit_code=\$(sed -n "\${count}p" "\$exit_codes_file" 2>/dev/null || echo "")
    [ -z "\$exit_code" ] && exit_code=0
fi
exit "\$exit_code"
EOF
  chmod +x "$dir/bin/claude"
}

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR
  export CLAUDELOOP="${CLAUDELOOP_DIR}/claudeloop"

  # Initialize git repo
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test User"

  # Write stub claude
  _write_claude_stub "$TEST_DIR"
  export PATH="$TEST_DIR/bin:$PATH"

  # Default 2-phase plan (no dependencies)
  cat > "$TEST_DIR/PLAN.md" << 'PLAN'
## Phase 1: Setup
Initialize the project

## Phase 2: Build
Build the project
PLAN

  # Config: zero delays for fast tests
  cat > "$TEST_DIR/.claudeloop.conf" << 'CONF'
BASE_DELAY=0
MAX_DELAY=0
CONF

  git -C "$TEST_DIR" add .
  git -C "$TEST_DIR" commit -q -m "initial"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: run claudeloop from TEST_DIR
_cl() {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' $*"
}

# Helper: count completed phases in PROGRESS.md
_completed_count() {
  grep -c "Status: completed" "$TEST_DIR/PROGRESS.md" 2>/dev/null || echo 0
}

# Helper: get claude call count
_call_count() {
  cat "$TEST_DIR/claude_call_count" 2>/dev/null || echo 0
}

# =============================================================================
# Scenario 1: Happy path
# =============================================================================
@test "integration: happy path exits 0 and all phases completed" {
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/PROGRESS.md" ]
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Scenario 2: Single retry — phase 1 fails once then succeeds
# =============================================================================
@test "integration: phase retried once then succeeds" {
  # Call 1 (phase 1): exit 1  Call 2 (phase 1 retry): exit 0  Call 3 (phase 2): exit 0
  printf '1\n0\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN.md --max-retries 3
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 3 ]
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Scenario 3: Exhaust retries — phase always fails
# =============================================================================
@test "integration: exhausted retries exits non-zero with failed status" {
  # Phase 1 always fails; MAX_RETRIES=2 → 2 attempts then give up
  printf '1\n1\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN.md --max-retries 2
  [ "$status" -ne 0 ]
  grep -q "Status: failed" "$TEST_DIR/PROGRESS.md"
}

# =============================================================================
# Scenario 4: Dependency blocking — phase 2 blocked when phase 1 fails
# =============================================================================
@test "integration: phase 2 blocked when dependency phase 1 fails" {
  cat > "$TEST_DIR/PLAN_DEP.md" << 'PLAN'
## Phase 1: Setup
Initialize

## Phase 2: Build
Build it
Depends on: Phase 1
PLAN
  git -C "$TEST_DIR" add .
  git -C "$TEST_DIR" commit -q -m "add dep plan"

  # Phase 1 always fails with MAX_RETRIES=1 → 1 attempt only
  printf '1\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN_DEP.md --max-retries 1
  [ "$status" -ne 0 ]
  # Only 1 claude call: phase 1 failed, phase 2 never ran
  [ "$(_call_count)" -eq 1 ]
}

# =============================================================================
# Scenario 5: --reset flag reruns all phases
# =============================================================================
@test "integration: --reset clears prior progress and reruns all phases" {
  # First run: complete everything
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]

  # Reset call counter
  rm -f "$TEST_DIR/claude_call_count"

  # Second run with --reset: should rerun both phases
  _cl --plan PLAN.md --reset
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 2 ]
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Scenario 6: --phase N skip — phases before N marked completed, N runs
# =============================================================================
@test "integration: --phase 2 skips phase 1 and runs only phase 2" {
  _cl --plan PLAN.md --phase 2
  [ "$status" -eq 0 ]
  # Only 1 claude call (phase 2 only)
  [ "$(_call_count)" -eq 1 ]
  # Both phases show as completed in PROGRESS.md
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Scenario 7: Resume from checkpoint (phase 1 already completed in PROGRESS.md)
# =============================================================================
@test "integration: resumes execution skipping already-completed phases" {
  # Write a PROGRESS.md with phase 1 already completed
  cat > "$TEST_DIR/PROGRESS.md" << 'PROGRESS'
# Progress for PLAN.md
Last updated: 2026-01-01 00:00:00

## Status Summary
- Total phases: 2
- Completed: 1
- In progress: 0
- Pending: 1
- Failed: 0

## Phase Details

### ✅ Phase 1: Setup
Status: completed
Started: 2026-01-01 00:00:00
Completed: 2026-01-01 00:01:00
Attempts: 1

### ⏳ Phase 2: Build
Status: pending
PROGRESS

  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  # Only 1 claude call: phase 1 was already done
  [ "$(_call_count)" -eq 1 ]
}

# =============================================================================
# Scenario 8: Lock file conflict — exits non-zero with live PID lock
# =============================================================================
@test "integration: rejects second invocation when lock file has live PID" {
  mkdir -p "$TEST_DIR/.claudeloop"
  # Write our own PID: we're definitely alive
  echo $$ > "$TEST_DIR/.claudeloop/lock"

  _cl --plan PLAN.md
  [ "$status" -ne 0 ]
  # No claude calls should have been made
  [ "$(_call_count)" -eq 0 ]
}

# =============================================================================
# Scenario 8b: Stale lock file is removed and run succeeds
# =============================================================================
@test "integration: stale lock file is cleaned up and run succeeds" {
  mkdir -p "$TEST_DIR/.claudeloop"
  # Create a background process and kill it to get a dead PID
  sh -c 'sleep 100' &
  dead_pid=$!
  kill "$dead_pid" 2>/dev/null || true
  wait "$dead_pid" 2>/dev/null || true
  echo "$dead_pid" > "$TEST_DIR/.claudeloop/lock"

  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
}

# =============================================================================
# Scenario 9: Log files created and non-empty
# =============================================================================
@test "integration: log files are created and non-empty for each phase" {
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.claudeloop/logs/phase-1.log" ]
  [ -s "$TEST_DIR/.claudeloop/logs/phase-1.log" ]
  [ -f "$TEST_DIR/.claudeloop/logs/phase-2.log" ]
  [ -s "$TEST_DIR/.claudeloop/logs/phase-2.log" ]
}

# =============================================================================
# parse_args tests (via subprocess)
# =============================================================================
@test "parse_args: --plan flag is accepted" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --dry-run"
  [ "$status" -eq 0 ]
}

@test "parse_args: --max-retries flag is accepted" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --max-retries 5 --dry-run"
  [ "$status" -eq 0 ]
}

@test "parse_args: --dry-run validates plan without executing claude" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --dry-run"
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 0 ]
}

@test "parse_args: unknown flag exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --unknown-flag 2>&1"
  [ "$status" -ne 0 ]
}

# =============================================================================
# create_lock / remove_lock tests (via subprocess)
# =============================================================================
@test "create_lock: live PID lock prevents execution" {
  mkdir -p "$TEST_DIR/.claudeloop"
  echo $$ > "$TEST_DIR/.claudeloop/lock"
  _cl --plan PLAN.md
  [ "$status" -ne 0 ]
}

@test "create_lock: stale PID lock is removed and execution succeeds" {
  mkdir -p "$TEST_DIR/.claudeloop"
  sh -c 'sleep 100' &
  dead_pid=$!
  kill "$dead_pid" 2>/dev/null || true
  wait "$dead_pid" 2>/dev/null || true
  echo "$dead_pid" > "$TEST_DIR/.claudeloop/lock"
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
}
