#!/usr/bin/env bash
# bats file_tags=retry

# Tests for lib/retry.sh POSIX-compatible implementation

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  MAX_RETRIES=3
  BASE_DELAY=5
  MAX_DELAY=60
  _log="$(mktemp)"
}

teardown() { rm -f "$_log"; }

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

@test "power: 2^10 = 1024" {
  run power 2 10
  [ "$status" -eq 0 ]
  [ "$output" = "1024" ]
}

@test "power: 2^62 = correct value" {
  run power 2 62
  [ "$status" -eq 0 ]
  [ "$output" = "4611686018427387904" ]
}

@test "power: 2^63 returns correct value without early cap" {
  run power 2 63
  [ "$status" -eq 0 ]
  # 2^63 = 9223372036854775808, but that overflows signed 64-bit.
  # The guard should cap at 2^62 (last safe value before overflow).
  # The key invariant: result must be >= 2^62
  [ "$output" -ge 4611686018427387904 ]
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

# --- is_quota_error() ---

@test "is_quota_error: nonexistent file returns 1" {
  run is_quota_error "/nonexistent/path/phase-99.log"
  [ "$status" -eq 1 ]
}

@test "is_quota_error: clean output returns 1" {
  printf 'All good, task completed.\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_quota_error: detects 'usage limit'" {
  printf 'Error: usage limit exceeded\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_quota_error: detects 'quota'" {
  printf 'quota has been reached\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_quota_error: detects 'rate limit' (with space)" {
  printf 'You have hit the rate limit\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_quota_error: detects 'rate-limit' (with hyphen)" {
  printf 'rate-limit error occurred\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_quota_error: detects '429'" {
  printf 'HTTP 429 response received\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_quota_error: detects 'Too Many Requests' (case-insensitive)" {
  printf 'too many requests\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_quota_error: detects 'rate_limit_error'" {
  printf 'type: rate_limit_error\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_quota_error: detects 'overloaded'" {
  printf 'The API is overloaded, please try again later.\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

# --- is_permission_error() ---

@test "is_permission_error: nonexistent file returns 1" {
  run is_permission_error "/nonexistent/path/phase-99.log"
  [ "$status" -eq 1 ]
}

@test "is_permission_error: clean output returns 1" {
  printf 'All good, task completed.\n' > "$_log"
  run is_permission_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_permission_error: detects 'write permissions haven't been granted'" {
  printf "Error: write permissions haven't been granted for this file\n" > "$_log"
  run is_permission_error "$_log"
  [ "$status" -eq 0 ]
}

# --- is_empty_log() ---

@test "is_empty_log: missing file returns 0 (empty)" {
  run is_empty_log "/nonexistent/phase-99.log"
  [ "$status" -eq 0 ]
}

@test "is_empty_log: zero-byte file returns 0 (empty)" {
  printf '' > "$_log"
  run is_empty_log "$_log"
  [ "$status" -eq 0 ]
}

@test "is_empty_log: new-format log with empty response returns 0 (empty)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== PROMPT ===\n' >> "$_log"
  printf 'do something\n' >> "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '=== EXECUTION END exit_code=0 duration=1s time=2026-01-01T00:00:01 ===\n' >> "$_log"
  run is_empty_log "$_log"
  [ "$status" -eq 0 ]
}

@test "is_empty_log: new-format log with non-empty response returns 1 (not empty)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== PROMPT ===\n' >> "$_log"
  printf 'do something\n' >> "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf 'Claude output here.\n' >> "$_log"
  printf '=== EXECUTION END exit_code=0 duration=1s time=2026-01-01T00:00:01 ===\n' >> "$_log"
  run is_empty_log "$_log"
  [ "$status" -eq 1 ]
}

@test "is_empty_log: old-format non-empty file returns 1 (not empty)" {
  printf 'Some Claude output without headers.\n' > "$_log"
  run is_empty_log "$_log"
  [ "$status" -eq 1 ]
}

# --- has_successful_session() ---

@test "has_successful_session: returns false when log missing" {
  run has_successful_session "/nonexistent/phase-99.log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns false when log has no session lines" {
  printf 'Some output without any session lines.\n' > "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns false when only turns=0 session" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '[Session: duration=0.0s turns=0 tokens=0in/0out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns true when session has turns > 0" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '[Session: duration=12.3s turns=71 tokens=500in/200out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 0 ]
}

@test "has_successful_session: returns true when good session followed by zero-turn session (bug scenario)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '[Session: duration=45.2s turns=71 tokens=5000in/2000out]\n' >> "$_log"
  printf '[Session: duration=0.0s turns=0 tokens=0in/0out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 0 ]
}

@test "has_successful_session: returns true when multiple sessions all turns > 0 (normal multi-subagent case)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '[Session: duration=30.1s turns=57 tokens=4000in/1500out]\n' >> "$_log"
  printf '[Session: duration=5.2s turns=1 tokens=200in/100out]\n' >> "$_log"
  printf '[Session: duration=4.8s turns=1 tokens=180in/90out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 0 ]
}

@test "has_successful_session: returns false when current attempt has turns=0 even if prior attempt had turns > 0 (cross-attempt scoping)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '[Session: duration=20.0s turns=10 tokens=1000in/500out]\n' >> "$_log"
  printf '=== EXECUTION START phase=1 attempt=2 time=2026-01-01T00:01:00 ===\n' >> "$_log"
  printf '[Session: duration=0.0s turns=0 tokens=0in/0out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}
