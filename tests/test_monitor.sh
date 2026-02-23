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

@test "--monitor colorizes checkmark lines green" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf '[12:00:00] \xe2\x9c\x93 Phase 1 completed\n' > "$TEST_DIR/.claudeloop/live.log"
  run sh -c "cd '$TEST_DIR' && _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q $'\033\[0;32m'
}

@test "--monitor colorizes failure lines red" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf '[12:00:00] \xe2\x9c\x97 Phase 1 failed\n' > "$TEST_DIR/.claudeloop/live.log"
  run sh -c "cd '$TEST_DIR' && _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q $'\033\[0;31m'
}

@test "--monitor colorizes executing phase lines blue" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf '[12:00:00] \xe2\x96\xb6 Executing Phase 1/1: Setup\n' > "$TEST_DIR/.claudeloop/live.log"
  run sh -c "cd '$TEST_DIR' && _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q $'\033\[0;34m'
}

@test "--monitor colorizes Attempt lines yellow" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf '[12:00:00] Attempt 2/3\n' > "$TEST_DIR/.claudeloop/live.log"
  run sh -c "cd '$TEST_DIR' && _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q $'\033\[1;33m'
}

@test "--monitor colorizes [Tool: X] tag inline cyan" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf '  [12:00:00] [Tool: Bash] npm test\n' > "$TEST_DIR/.claudeloop/live.log"
  run sh -c "cd '$TEST_DIR' && _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q $'\033\[0;36m'
}

@test "--monitor does not add color to plain text lines" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf '[12:00:00] I see the issue with the code\n' > "$TEST_DIR/.claudeloop/live.log"
  run sh -c "cd '$TEST_DIR' && _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qv $'\033\['
}

@test "--monitor live.log stays plain text after run" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf '[12:00:00] \xe2\x9c\x93 Phase 1 completed\n' > "$TEST_DIR/.claudeloop/live.log"
  sh -c "cd '$TEST_DIR' && _MONITOR_NO_FOLLOW=1 '$CLAUDELOOP' --monitor" >/dev/null
  # live.log itself must contain no ANSI escape sequences
  if grep -qP '\x1b' "$TEST_DIR/.claudeloop/live.log" 2>/dev/null; then
    false
  fi
}
