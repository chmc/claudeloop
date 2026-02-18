#!/usr/bin/env bash
# bats file_tags=retry

# Tests for lib/retry.sh POSIX-compatible implementation

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  MAX_RETRIES=3
  BASE_DELAY=5
  MAX_DELAY=60
}

# --- power() ---

@test "power: 2^0 = 1" {
  run power 2 0
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "power: 2^1 = 2" {
  run power 2 1
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "power: 2^3 = 8" {
  run power 2 3
  [ "$status" -eq 0 ]
  [ "$output" = "8" ]
}

@test "power: 5^2 = 25" {
  run power 5 2
  [ "$status" -eq 0 ]
  [ "$output" = "25" ]
}

# --- get_random() ---

@test "get_random: returns value in range [0, max)" {
  local i=0
  while [ "$i" -lt 10 ]; do
    run get_random 10
    [ "$status" -eq 0 ]
    [ "$output" -ge 0 ]
    [ "$output" -lt 10 ]
    i=$((i + 1))
  done
}

@test "get_random: max=1 always returns 0" {
  run get_random 1
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# --- calculate_backoff() ---

@test "calculate_backoff: attempt 1 returns base delay with jitter" {
  BASE_DELAY=5
  MAX_DELAY=60
  run calculate_backoff 1
  [ "$status" -eq 0 ]
  # 5 * 2^0 = 5, jitter 0..(5/4)=0..1 → 5 or 6
  [ "$output" -ge 5 ]
  [ "$output" -le 6 ]
}

@test "calculate_backoff: attempt 2 doubles the base delay" {
  BASE_DELAY=5
  MAX_DELAY=60
  run calculate_backoff 2
  [ "$status" -eq 0 ]
  # 5 * 2^1 = 10, jitter 0..(10/4)=0..2 → 10..12
  [ "$output" -ge 10 ]
  [ "$output" -le 12 ]
}

@test "calculate_backoff: attempt 3 quadruples the base delay" {
  BASE_DELAY=5
  MAX_DELAY=60
  run calculate_backoff 3
  [ "$status" -eq 0 ]
  # 5 * 2^2 = 20, jitter 0..(20/4)=0..5 → 20..25
  [ "$output" -ge 20 ]
  [ "$output" -le 25 ]
}

@test "calculate_backoff: caps delay at MAX_DELAY" {
  BASE_DELAY=5
  MAX_DELAY=10
  run calculate_backoff 5
  [ "$status" -eq 0 ]
  # 5 * 2^4 = 80 > MAX_DELAY=10; jitter 0..(10/4)=0..2 → 10..12
  [ "$output" -ge 10 ]
  [ "$output" -le 12 ]
}

# --- should_retry_phase() ---

@test "should_retry_phase: returns 0 (should retry) when attempts < MAX_RETRIES" {
  MAX_RETRIES=3
  PHASE_ATTEMPTS_1=1
  run should_retry_phase 1
  [ "$status" -eq 0 ]
}

@test "should_retry_phase: returns 0 (should retry) when attempts = 0" {
  MAX_RETRIES=3
  PHASE_ATTEMPTS_2=0
  run should_retry_phase 2
  [ "$status" -eq 0 ]
}

@test "should_retry_phase: returns 1 (no retry) when attempts = MAX_RETRIES" {
  MAX_RETRIES=3
  PHASE_ATTEMPTS_1=3
  run should_retry_phase 1
  [ "$status" -eq 1 ]
}

@test "should_retry_phase: returns 1 (no retry) when attempts > MAX_RETRIES" {
  MAX_RETRIES=3
  PHASE_ATTEMPTS_1=5
  run should_retry_phase 1
  [ "$status" -eq 1 ]
}

@test "should_retry_phase: works for arbitrary phase numbers" {
  MAX_RETRIES=3
  PHASE_ATTEMPTS_7=2
  run should_retry_phase 7
  [ "$status" -eq 0 ]
}
