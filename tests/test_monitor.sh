#!/usr/bin/env bash
# bats file_tags=monitor

# Tests for --monitor flag

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR
  export CLAUDELOOP="${CLAUDELOOP_DIR}/claudeloop"

  # Initialize git repo
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test User"

  # Minimal plan file so claudeloop doesn't exit early on missing plan
  cat > "$TEST_DIR/PLAN.md" << 'PLAN'
## Phase 1: Setup
Initialize the project
PLAN
  git -C "$TEST_DIR" add PLAN.md
  git -C "$TEST_DIR" commit -q -m "initial"

  # Pre-created conf so setup wizard doesn't prompt
  mkdir -p "$TEST_DIR/.claudeloop"
  cat > "$TEST_DIR/.claudeloop/.claudeloop.conf" << 'CONF'
BASE_DELAY=0
MAX_DELAY=0
CONF
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "--monitor times out with error when no live log exists" {
  run sh -c "cd '$TEST_DIR' && _MONITOR_WAIT_TIMEOUT=1 '$CLAUDELOOP' --monitor"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "No live log found"
}

@test "--monitor shows COMPLETED when live log exists but no active PID" {
  mkdir -p "$TEST_DIR/.claudeloop"
  echo "test output" > "$TEST_DIR/.claudeloop/live.log"
  run sh -c "cd '$TEST_DIR' && _MONITOR_WAIT_TIMEOUT=1 _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "COMPLETED"
}

@test "--monitor shows content of live log with _MONITOR_NO_FOLLOW" {
  mkdir -p "$TEST_DIR/.claudeloop"
  echo "hello from claudeloop" > "$TEST_DIR/.claudeloop/live.log"
  run sh -c "cd '$TEST_DIR' && _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hello from claudeloop"
}
