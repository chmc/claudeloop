#!/usr/bin/env bash
# bats file_tags=retry

# Tests for lib/retry.sh POSIX-compatible implementation

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  MAX_RETRIES=3
  BASE_DELAY=5
  _log="$BATS_TEST_TMPDIR/log"
}

teardown() { :; }

# --- calculate_backoff() ---

@test "calculate_backoff: any attempt returns BASE_DELAY" {
  BASE_DELAY=5
  for attempt in 1 2 3 5 10 50; do
    run calculate_backoff "$attempt"
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
  done
}

@test "calculate_backoff: non-numeric input returns BASE_DELAY" {
  BASE_DELAY=5
  run calculate_backoff "abc"
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "calculate_backoff: custom BASE_DELAY override works" {
  BASE_DELAY=10
  run calculate_backoff 3
  [ "$status" -eq 0 ]
  [ "$output" = "10" ]
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

@test "should_retry_phase: returns 1 when PHASE_ATTEMPTS is empty" {
  PHASE_ATTEMPTS_1=""
  MAX_RETRIES=3
  run should_retry_phase 1
  [ "$status" -eq 1 ]
}

@test "should_retry_phase: returns 1 when MAX_RETRIES is non-numeric" {
  PHASE_ATTEMPTS_1=2
  MAX_RETRIES="abc"
  run should_retry_phase 1
  [ "$status" -eq 1 ]
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

@test "is_quota_error: bare 429 in unrelated context does not trigger" {
  printf 'Processed 429 tokens in phase 3\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 1 ]
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

@test "is_quota_error: does NOT match 'overloaded' (moved to is_overload_error)" {
  printf 'The API is overloaded, please try again later.\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 1 ]
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

# --- is_network_error() ---

@test "is_network_error: nonexistent file returns 1" {
  run is_network_error "/nonexistent/path/phase-99.log"
  [ "$status" -eq 1 ]
}

@test "is_network_error: clean output returns 1" {
  printf 'All good, task completed.\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_network_error: detects 'connection refused'" {
  printf 'Error: connection refused\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects 'connection reset'" {
  printf 'connection reset by peer\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects 'connection error'" {
  printf 'connection error: network socket disconnected\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects 'could not connect'" {
  printf 'could not connect to api.anthropic.com\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects ETIMEDOUT" {
  printf 'Error: ETIMEDOUT\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects ECONNREFUSED" {
  printf 'Error: ECONNREFUSED\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects ECONNRESET" {
  printf 'Error: ECONNRESET\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects 'socket hang up'" {
  printf 'Error: socket hang up\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects 'fetch failed'" {
  printf 'fetch failed: unable to reach server\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects 'dns resolution failed'" {
  printf 'dns resolution failed for api.anthropic.com\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects 'ssl handshake error'" {
  printf 'ssl handshake error occurred\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: detects 'network unreachable'" {
  printf 'network unreachable\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_network_error: false positive — 'connected to server' does not trigger" {
  printf 'Successfully connected to server\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_network_error: false positive — 'network configuration' does not trigger" {
  printf 'The network configuration looks good\n' > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_network_error: empty file returns 1" {
  : > "$_log"
  run is_network_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_network_error: checks raw JSON log as fallback" {
  # Formatted log has no network error
  printf 'All good\n' > "$_log"
  # But raw JSON has the error
  local _raw_dir
  _raw_dir=$(dirname "$_log")
  printf '{"error":"ECONNRESET"}\n' > "${_raw_dir}/raw-phase-log.json"
  run is_network_error "$_log"
  [ "$status" -eq 0 ]
  rm -f "${_raw_dir}/raw-phase-log.json"
}

# --- is_auth_error() ---

@test "is_auth_error: returns false when log missing" {
  run is_auth_error "/nonexistent/path/phase-99.log"
  [ "$status" -eq 1 ]
}

@test "is_auth_error: returns false for clean output" {
  printf 'All good, task completed.\n' > "$_log"
  run is_auth_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_auth_error: detects authentication_error" {
  printf 'Error: authentication_error\n' > "$_log"
  run is_auth_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_auth_error: detects invalid credentials" {
  printf 'Invalid authentication credentials provided\n' > "$_log"
  run is_auth_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_auth_error: detects invalid api key" {
  printf 'invalid api key\n' > "$_log"
  run is_auth_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_auth_error: detects not_authorized" {
  printf 'not_authorized\n' > "$_log"
  run is_auth_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_auth_error: does not match authentication (without _error)" {
  printf 'authentication completed successfully\n' > "$_log"
  run is_auth_error "$_log"
  [ "$status" -eq 1 ]
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
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=0.0s turns=0 tokens=0in/0out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns true when session has turns > 0" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=12.3s turns=71 tokens=500in/200out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 0 ]
}

@test "has_successful_session: returns true when good session followed by zero-turn crash (sub-agent scenario)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=45.2s turns=71 tokens=5000in/2000out]\n' >> "$_log"
  printf '[Session: duration=0.0s turns=0 tokens=0in/0out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 0 ]
}

@test "has_successful_session: returns true when multiple sessions all turns > 0 (normal multi-subagent case)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=30.1s turns=57 tokens=4000in/1500out]\n' >> "$_log"
  printf '[Session: duration=5.2s turns=1 tokens=200in/100out]\n' >> "$_log"
  printf '[Session: duration=4.8s turns=1 tokens=180in/90out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 0 ]
}

@test "has_successful_session: returns false when current attempt has turns=0 even if prior attempt had turns > 0 (cross-attempt scoping)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=20.0s turns=10 tokens=1000in/500out]\n' >> "$_log"
  printf '=== EXECUTION START phase=1 attempt=2 time=2026-01-01T00:01:00 ===\n' >> "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=0.0s turns=0 tokens=0in/0out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns false when turns=1 but zero output tokens (API 500 error)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=33.8s turns=1 tokens=0in/0out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns true when turns=1 with real output tokens (legitimate quick task)" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=15.0s turns=1 tokens=200in/100out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 0 ]
}

@test "has_successful_session: returns false when nonzero input but zero output tokens" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=10.0s turns=1 tokens=500in/0out]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns false when session line has no token field" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=5.0s turns=3]\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns false when matching session line is in PROMPT section (prompt pollution)" {
  printf '=== EXECUTION START phase=6 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== PROMPT ===\n' >> "$_log"
  printf '## Phase 6: Notifications\n' >> "$_log"
  printf '**Files**: src/views/statusBar.ts[Session: model=claude-opus-4-6 cost=0.25 duration=85.2s turns=1 tokens=2in/5685out cache=7616r/18048w]\n' >> "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf 'Failed to authenticate. API Error: 401\n' >> "$_log"
  printf '[Session: duration=5.2s turns=1 tokens=0in/0out]\n' >> "$_log"
  printf '=== EXECUTION END exit_code=1 duration=7s time=2026-01-01T00:00:07 ===\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 1 ]
}

@test "has_successful_session: returns true when matching session line is in RESPONSE section" {
  printf '=== EXECUTION START phase=1 attempt=1 time=2026-01-01T00:00:00 ===\n' > "$_log"
  printf '=== PROMPT ===\n' >> "$_log"
  printf 'do something\n' >> "$_log"
  printf '=== RESPONSE ===\n' >> "$_log"
  printf '[Session: duration=30.0s turns=5 tokens=500in/200out]\n' >> "$_log"
  printf '=== EXECUTION END exit_code=0 duration=30s time=2026-01-01T00:00:30 ===\n' >> "$_log"
  run has_successful_session "$_log"
  [ "$status" -eq 0 ]
}

# --- has_write_actions() ---

@test "has_write_actions: returns 0 when raw log contains Edit tool" {
  printf '=== EXECUTION START phase=1 attempt=1 ===\n' > "$_log"
  printf '{"type":"tool_use","name":"Edit","input":{}}\n' >> "$_log"
  run has_write_actions "$_log"
  [ "$status" -eq 0 ]
}

@test "has_write_actions: returns 0 when raw log contains Write tool" {
  printf '=== EXECUTION START phase=1 attempt=1 ===\n' > "$_log"
  printf '{"type":"tool_use","name":"Write","input":{}}\n' >> "$_log"
  run has_write_actions "$_log"
  [ "$status" -eq 0 ]
}

@test "has_write_actions: returns 0 when raw log contains NotebookEdit tool" {
  printf '=== EXECUTION START phase=1 attempt=1 ===\n' > "$_log"
  printf '{"type":"tool_use","name":"NotebookEdit","input":{}}\n' >> "$_log"
  run has_write_actions "$_log"
  [ "$status" -eq 0 ]
}

@test "has_write_actions: returns 0 when raw log contains Agent tool" {
  printf '=== EXECUTION START phase=1 attempt=1 ===\n' > "$_log"
  printf '{"type":"tool_use","name":"Agent","input":{}}\n' >> "$_log"
  run has_write_actions "$_log"
  [ "$status" -eq 0 ]
}

@test "has_write_actions: returns 1 when raw log has only Read/Grep tools" {
  printf '=== EXECUTION START phase=1 attempt=1 ===\n' > "$_log"
  printf '{"type":"tool_use","name":"Read","input":{}}\n' >> "$_log"
  printf '{"type":"tool_use","name":"Grep","input":{}}\n' >> "$_log"
  run has_write_actions "$_log"
  [ "$status" -eq 1 ]
}

@test "has_write_actions: returns 1 when log is empty" {
  printf '' > "$_log"
  run has_write_actions "$_log"
  [ "$status" -eq 1 ]
}

@test "has_write_actions: returns 1 when log file missing" {
  run has_write_actions "/nonexistent/phase-99.raw.json"
  [ "$status" -eq 1 ]
}

# --- fail_reason_hint() ---

@test "fail_reason_hint: no_write_actions returns hint about Edit/Write tools" {
  run fail_reason_hint "no_write_actions"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Edit"
  echo "$output" | grep -q "Write"
}

@test "fail_reason_hint: empty_log returns hint about using tools" {
  run fail_reason_hint "empty_log"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "tool\|Read\|Edit"
}

@test "fail_reason_hint: no_session returns hint about crash" {
  run fail_reason_hint "no_session"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "crash\|killed"
}

@test "fail_reason_hint: verification_failed returns hint about verification" {
  run fail_reason_hint "verification_failed"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "verification"
}

@test "fail_reason_hint: empty string returns empty" {
  run fail_reason_hint ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fail_reason_hint: unknown string returns empty" {
  run fail_reason_hint "something_random"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- past_retry_midpoint() ---

@test "past_retry_midpoint: attempt=5 max=10 returns true (5 >= 5)" {
  run past_retry_midpoint 5 10
  [ "$status" -eq 0 ]
}

@test "past_retry_midpoint: attempt=4 max=10 returns false (4 < 5)" {
  run past_retry_midpoint 4 10
  [ "$status" -eq 1 ]
}

@test "past_retry_midpoint: attempt=1 max=10 returns false" {
  run past_retry_midpoint 1 10
  [ "$status" -eq 1 ]
}

@test "past_retry_midpoint: attempt=3 max=5 returns true (3 >= 3)" {
  run past_retry_midpoint 3 5
  [ "$status" -eq 0 ]
}

@test "past_retry_midpoint: attempt=2 max=5 returns false (2 < 3)" {
  run past_retry_midpoint 2 5
  [ "$status" -eq 1 ]
}

@test "past_retry_midpoint: attempt=1 max=1 returns true (1 >= 1)" {
  run past_retry_midpoint 1 1
  [ "$status" -eq 0 ]
}

@test "past_retry_midpoint: max=0 returns false (guard)" {
  run past_retry_midpoint 1 0
  [ "$status" -eq 1 ]
}

@test "past_retry_midpoint: max=abc returns false (guard)" {
  run past_retry_midpoint 1 abc
  [ "$status" -eq 1 ]
}

# --- PHASE_FAIL_REASON round-trip ---

@test "PHASE_FAIL_REASON round-trip via phase_to_var" {
  _pv=$(phase_to_var "2.5")
  eval "PHASE_FAIL_REASON_${_pv}='no_write_actions'"
  reason=$(eval "echo \"\$PHASE_FAIL_REASON_${_pv}\"")
  [ "$reason" = "no_write_actions" ]
}

@test "has_write_actions: multi-attempt log only checks last execution block" {
  printf '=== EXECUTION START phase=1 attempt=1 ===\n' > "$_log"
  printf '{"type":"tool_use","name":"Edit","input":{}}\n' >> "$_log"
  printf '=== EXECUTION START phase=1 attempt=2 ===\n' >> "$_log"
  printf '{"type":"tool_use","name":"Read","input":{}}\n' >> "$_log"
  run has_write_actions "$_log"
  [ "$status" -eq 1 ]
}

# --- has_trapped_tool_calls() ---

@test "has_trapped_tool_calls: returns 0 when thinking has XML function call" {
  printf '{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"<tool_call>\\n<function=Read>\\n<parameter=file_path>/tmp/x</parameter>\\n</function>\\n</tool_call>"}]}}\n' > "$_log"
  run has_trapped_tool_calls "$_log"
  [ "$status" -eq 0 ]
}

@test "has_trapped_tool_calls: returns 1 when no tool patterns in thinking" {
  printf '{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Let me analyze the code"}]}}\n' > "$_log"
  run has_trapped_tool_calls "$_log"
  [ "$status" -eq 1 ]
}

@test "has_trapped_tool_calls: returns 1 when log file missing" {
  run has_trapped_tool_calls "/nonexistent/file"
  [ "$status" -eq 1 ]
}

@test "has_trapped_tool_calls: ignores delta events (only matches assembled)" {
  printf '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"<function"}}}\n' > "$_log"
  run has_trapped_tool_calls "$_log"
  [ "$status" -eq 1 ]
}

@test "has_trapped_tool_calls: returns 1 when raw log is empty" {
  printf '' > "$_log"
  run has_trapped_tool_calls "$_log"
  [ "$status" -eq 1 ]
}

@test "has_trapped_tool_calls: returns 0 with function= but no tool_call wrapper" {
  printf '{"type":"message","message":{"content":[{"type":"thinking","thinking":"I will call <function=Edit>"}]}}\n' > "$_log"
  run has_trapped_tool_calls "$_log"
  [ "$status" -eq 0 ]
}

@test "fail_reason_hint: trapped_tool_calls returns hint about thinking blocks" {
  run fail_reason_hint "trapped_tool_calls"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "thinking"
}

# --- retry_strategy() ---

@test "retry_strategy: MAX_RETRIES=15, attempts 1-5 return standard" {
  for i in 1 2 3 4 5; do
    run retry_strategy "$i" 15
    [ "$status" -eq 0 ]
    [ "$output" = "standard" ]
  done
}

@test "retry_strategy: MAX_RETRIES=15, attempts 6-10 return stripped" {
  for i in 6 7 8 9 10; do
    run retry_strategy "$i" 15
    [ "$status" -eq 0 ]
    [ "$output" = "stripped" ]
  done
}

@test "retry_strategy: MAX_RETRIES=15, attempts 11-15 return targeted" {
  for i in 11 12 13 14 15; do
    run retry_strategy "$i" 15
    [ "$status" -eq 0 ]
    [ "$output" = "targeted" ]
  done
}

@test "retry_strategy: MAX_RETRIES=3, attempt 1=standard, 2=stripped, 3=targeted" {
  run retry_strategy 1 3
  [ "$output" = "standard" ]
  run retry_strategy 2 3
  [ "$output" = "stripped" ]
  run retry_strategy 3 3
  [ "$output" = "targeted" ]
}

@test "retry_strategy: MAX_RETRIES=1, attempt 1=standard" {
  run retry_strategy 1 1
  [ "$output" = "standard" ]
}

@test "retry_strategy: MAX_RETRIES=2, attempt 1=standard, 2=stripped" {
  run retry_strategy 1 2
  [ "$output" = "standard" ]
  run retry_strategy 2 2
  [ "$output" = "stripped" ]
}

# --- verify_mode() ---

@test "verify_mode: MAX_RETRIES=15, attempts 1-5 return full" {
  for i in 1 2 3 4 5; do
    run verify_mode "$i" 15
    [ "$status" -eq 0 ]
    [ "$output" = "full" ]
  done
}

@test "verify_mode: MAX_RETRIES=15, attempts 6-10 return quick" {
  for i in 6 7 8 9 10; do
    run verify_mode "$i" 15
    [ "$status" -eq 0 ]
    [ "$output" = "quick" ]
  done
}

@test "verify_mode: MAX_RETRIES=15, attempts 11-15 return skip" {
  for i in 11 12 13 14 15; do
    run verify_mode "$i" 15
    [ "$status" -eq 0 ]
    [ "$output" = "skip" ]
  done
}

@test "verify_mode: MAX_RETRIES=3, attempt 1=full, 2=quick, 3=skip" {
  run verify_mode 1 3
  [ "$output" = "full" ]
  run verify_mode 2 3
  [ "$output" = "quick" ]
  run verify_mode 3 3
  [ "$output" = "skip" ]
}

# --- extract_error_context() ---

@test "extract_error_context: finds SyntaxError in log" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'Some output here\n' >> "$_log"
  printf 'File: test.py\n' >> "$_log"
  printf 'SyntaxError: unexpected indent at line 42\n' >> "$_log"
  printf 'More output\n' >> "$_log"
  printf '=== EXECUTION END exit_code=1 ===\n' >> "$_log"
  run extract_error_context "$_log" 15
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "SyntaxError"
}

@test "extract_error_context: finds test FAIL in log" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'Running tests...\n' >> "$_log"
  printf 'FAIL: test_something\n' >> "$_log"
  printf 'Expected 1 but got 2\n' >> "$_log"
  printf '=== EXECUTION END exit_code=1 ===\n' >> "$_log"
  run extract_error_context "$_log" 15
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FAIL"
}

@test "extract_error_context: falls back to tail when no patterns match" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'Line one\n' >> "$_log"
  printf 'Line two\n' >> "$_log"
  printf 'Line three\n' >> "$_log"
  printf '=== EXECUTION END exit_code=1 ===\n' >> "$_log"
  run extract_error_context "$_log" 15
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Line three"
}

@test "extract_error_context: handles missing log" {
  run extract_error_context "/nonexistent/file" 15
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract_error_context: handles empty log" {
  printf '' > "$_log"
  run extract_error_context "$_log" 15
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- extract_verify_error() ---

@test "extract_verify_error: extracts VERIFICATION_FAILED context" {
  printf 'Checking tests...\n' > "$_log"
  printf 'test_foo: PASS\n' >> "$_log"
  printf 'test_bar: FAIL - expected 1 got 2\n' >> "$_log"
  printf 'VERIFICATION_FAILED\n' >> "$_log"
  printf 'Issues found: test_bar assertion failed\n' >> "$_log"
  run extract_verify_error "$_log" 10
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "VERIFICATION_FAILED"
}

@test "extract_verify_error: falls back to tail when no VERIFICATION marker" {
  printf 'Some verify output line 1\n' > "$_log"
  printf 'Some verify output line 2\n' >> "$_log"
  printf 'Some verify output line 3\n' >> "$_log"
  run extract_verify_error "$_log" 10
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "line 3"
}

@test "extract_verify_error: handles missing log" {
  run extract_verify_error "/nonexistent/file" 10
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- build_retry_context() ---

@test "build_retry_context: standard includes tail and fail hint" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'Some error happened\n' >> "$_log"
  printf '=== EXECUTION END exit_code=1 ===\n' >> "$_log"
  run build_retry_context "standard" 2 10 "no_write_actions" "$_log" ""
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Previous Attempt Failed"
  echo "$output" | grep -q "MUST"
}

@test "build_retry_context: stripped has shorter context, no generic advice" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'Some error happened\n' >> "$_log"
  printf '=== EXECUTION END exit_code=1 ===\n' >> "$_log"
  run build_retry_context "stripped" 5 10 "no_write_actions" "$_log" ""
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Previous Attempt Failed"
  # Should NOT contain generic advice
  ! echo "$output" | grep -q "do not repeat"
}

@test "build_retry_context: targeted is minimal, just error" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'error: something broke\n' >> "$_log"
  printf '=== EXECUTION END exit_code=1 ===\n' >> "$_log"
  run build_retry_context "targeted" 9 10 "" "$_log" ""
  [ "$status" -eq 0 ]
  # Should be concise
  local line_count
  line_count=$(echo "$output" | wc -l)
  [ "$line_count" -le 20 ]
}

@test "build_retry_context: targeted with verify log uses verify error" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'did some work\n' >> "$_log"
  printf '=== EXECUTION END exit_code=0 ===\n' >> "$_log"
  local _vlog
  _vlog="$(mktemp)"
  printf 'test_foo: FAIL\nVERIFICATION_FAILED\n' > "$_vlog"
  run build_retry_context "targeted" 9 10 "verification_failed" "$_log" "$_vlog"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "VERIFICATION_FAILED"
  rm -f "$_vlog"
}

# --- updated fail_reason_hint() ---

@test "fail_reason_hint: no_write_actions mentions Edit or Write tools" {
  run fail_reason_hint "no_write_actions"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Edit"
  echo "$output" | grep -q "Write"
}

@test "fail_reason_hint: empty_log mentions tools" {
  run fail_reason_hint "empty_log"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "tool\|Read\|Edit"
}

# --- fail_reason_hint() escalation with consecutive count ---

@test "fail_reason_hint: backward compat — no 2nd arg returns same as consec=1" {
  run fail_reason_hint "trapped_tool_calls"
  local no_arg="$output"
  run fail_reason_hint "trapped_tool_calls" 1
  [ "$output" = "$no_arg" ]
}

@test "fail_reason_hint: trapped_tool_calls consec=1 returns level-1 hint" {
  run fail_reason_hint "trapped_tool_calls" 1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "thinking"
  ! echo "$output" | grep -q "CRITICAL"
}

@test "fail_reason_hint: trapped_tool_calls consec=3 includes CRITICAL" {
  run fail_reason_hint "trapped_tool_calls" 3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CRITICAL"
}

@test "fail_reason_hint: no_write_actions consec=3 escalates" {
  run fail_reason_hint "no_write_actions" 3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CRITICAL"
}

@test "fail_reason_hint: verification_failed ignores consecutive count" {
  run fail_reason_hint "verification_failed" 5
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "CRITICAL"
  echo "$output" | grep -qi "verification"
}

# --- escalate_strategy() ---

@test "escalate_strategy: returns base unchanged for consec < 3" {
  run escalate_strategy "standard" "trapped_tool_calls" 2
  [ "$output" = "standard" ]
}

@test "escalate_strategy: returns stripped for trapped_tool_calls consec=3" {
  run escalate_strategy "standard" "trapped_tool_calls" 3
  [ "$output" = "stripped" ]
}

@test "escalate_strategy: returns stripped for no_write_actions consec=3" {
  run escalate_strategy "standard" "no_write_actions" 3
  [ "$output" = "stripped" ]
}

@test "escalate_strategy: returns targeted for consec=5" {
  run escalate_strategy "standard" "trapped_tool_calls" 5
  [ "$output" = "targeted" ]
}

@test "escalate_strategy: never downgrades — base=targeted consec=3 stays targeted" {
  run escalate_strategy "targeted" "trapped_tool_calls" 3
  [ "$output" = "targeted" ]
}

@test "escalate_strategy: ignores non-model-behavior reasons at high consec" {
  run escalate_strategy "standard" "verification_failed" 5
  [ "$output" = "standard" ]
}

@test "escalate_strategy: ignores non-model-behavior reasons (no_session)" {
  run escalate_strategy "standard" "no_session" 5
  [ "$output" = "standard" ]
}

# --- build_retry_context: skip error context for model-behavior failures ---

@test "build_retry_context: skips error context for trapped_tool_calls (only hint)" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'error: something broke\n' >> "$_log"
  printf '=== EXECUTION END exit_code=0 ===\n' >> "$_log"
  run build_retry_context "standard" 2 10 "trapped_tool_calls" "$_log" ""
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "thinking"
  # Should NOT contain the error context from the log
  ! echo "$output" | grep -q "something broke"
}

@test "build_retry_context: skips error context for no_write_actions" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'error: something broke\n' >> "$_log"
  printf '=== EXECUTION END exit_code=0 ===\n' >> "$_log"
  run build_retry_context "standard" 2 10 "no_write_actions" "$_log" ""
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "Edit"
  ! echo "$output" | grep -q "something broke"
}

@test "build_retry_context: skips error context for empty_log" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'error: something broke\n' >> "$_log"
  printf '=== EXECUTION END exit_code=0 ===\n' >> "$_log"
  run build_retry_context "standard" 2 10 "empty_log" "$_log" ""
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "something broke"
}

@test "build_retry_context: includes error context for verification_failed" {
  printf '=== RESPONSE ===\n' > "$_log"
  printf 'error: test assertion failed\n' >> "$_log"
  printf '=== EXECUTION END exit_code=1 ===\n' >> "$_log"
  run build_retry_context "standard" 2 10 "verification_failed" "$_log" ""
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "test assertion failed"
}

# --- has_signal_file() ---

@test "has_signal_file: returns 0 when signal file exists" {
  mkdir -p ".claudeloop/signals"
  printf 'No changes needed\n' > ".claudeloop/signals/phase-1.md"
  run has_signal_file "1"
  [ "$status" -eq 0 ]
  rm -rf ".claudeloop/signals"
}

@test "has_signal_file: returns 1 when no signal file" {
  rm -f ".claudeloop/signals/phase-99.md"
  run has_signal_file "99"
  [ "$status" -eq 1 ]
}

# --- is_overload_error() ---

@test "is_overload_error: nonexistent file returns 1" {
  run is_overload_error "/nonexistent/path/phase-99.log"
  [ "$status" -eq 1 ]
}

@test "is_overload_error: clean output returns 1" {
  printf 'All good, task completed.\n' > "$_log"
  run is_overload_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_overload_error: detects 'overloaded'" {
  printf 'The API is overloaded, please try again later.\n' > "$_log"
  run is_overload_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_overload_error: detects 'overloaded_error' in raw JSON" {
  local _raw="$BATS_TEST_TMPDIR/raw.json"
  printf '{"error":{"type":"overloaded_error","message":"Overloaded"}}\n' > "$_raw"
  printf 'All good\n' > "$_log"
  run is_overload_error "$_log" "$_raw"
  [ "$status" -eq 0 ]
}

@test "is_overload_error: detects 529 status" {
  printf 'HTTP 529 — API overloaded\n' > "$_log"
  run is_overload_error "$_log"
  [ "$status" -eq 0 ]
}

# --- is_server_error() ---

@test "is_server_error: nonexistent file returns 1" {
  run is_server_error "/nonexistent/path/phase-99.log"
  [ "$status" -eq 1 ]
}

@test "is_server_error: clean output returns 1" {
  printf 'All good, task completed.\n' > "$_log"
  run is_server_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_server_error: detects 'api_error'" {
  printf 'Error: api_error\n' > "$_log"
  run is_server_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_server_error: detects 'internal_server_error'" {
  printf 'Error: internal_server_error from API\n' > "$_log"
  run is_server_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_server_error: detects 'Server error'" {
  printf 'Server error: please try again\n' > "$_log"
  run is_server_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_server_error: detects HTTP 500" {
  printf 'HTTP 500 Internal Server Error\n' > "$_log"
  run is_server_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_server_error: detects HTTP 502" {
  printf 'HTTP 502 Bad Gateway\n' > "$_log"
  run is_server_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_server_error: detects HTTP 503" {
  printf 'HTTP 503 Service Unavailable\n' > "$_log"
  run is_server_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_server_error: checks raw JSON log as fallback" {
  local _raw="$BATS_TEST_TMPDIR/raw.json"
  printf 'All good\n' > "$_log"
  printf '{"error":{"type":"api_error","message":"Internal server error"}}\n' > "$_raw"
  run is_server_error "$_log" "$_raw"
  [ "$status" -eq 0 ]
}

# --- is_timeout_error() ---

@test "is_timeout_error: nonexistent file returns 1" {
  run is_timeout_error "/nonexistent/path/phase-99.log"
  [ "$status" -eq 1 ]
}

@test "is_timeout_error: clean output returns 1" {
  printf 'All good, task completed.\n' > "$_log"
  run is_timeout_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_timeout_error: detects 'request_timeout'" {
  printf 'Error: request_timeout\n' > "$_log"
  run is_timeout_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_timeout_error: detects HTTP 408" {
  printf 'HTTP 408 Request Timeout\n' > "$_log"
  run is_timeout_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_timeout_error: detects 'request timed out'" {
  printf 'The request timed out waiting for a response\n' > "$_log"
  run is_timeout_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_timeout_error: detects stream processor idle timeout" {
  printf '[idle timeout after 600s]\n' > "$_log"
  run is_timeout_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_timeout_error: detects stream processor tool timeout" {
  printf '[tool timeout after 300s]\n' > "$_log"
  run is_timeout_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_timeout_error: detects dead connection timeout" {
  printf '[dead connection timeout after 180s]\n' > "$_log"
  run is_timeout_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_timeout_error: no false positive on prose about timeouts" {
  printf 'discussing idle timeout settings\n' > "$_log"
  run is_timeout_error "$_log"
  [ "$status" -eq 1 ]
}

# --- is_rate_limit_error() (renamed, no longer matches overloaded) ---

@test "is_rate_limit_error: detects 'rate_limit_error'" {
  printf 'type: rate_limit_error\n' > "$_log"
  run is_rate_limit_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_rate_limit_error: detects 'usage limit'" {
  printf 'Error: usage limit exceeded\n' > "$_log"
  run is_rate_limit_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_rate_limit_error: does NOT match 'overloaded'" {
  printf 'The API is overloaded, please try again later.\n' > "$_log"
  run is_rate_limit_error "$_log"
  [ "$status" -eq 1 ]
}

@test "is_quota_error: still works as alias for backward compat" {
  printf 'Error: usage limit exceeded\n' > "$_log"
  run is_quota_error "$_log"
  [ "$status" -eq 0 ]
}

# --- is_auth_error() expanded ---

@test "is_auth_error: detects permission_error" {
  printf 'Error: permission_error — your key cannot access this resource\n' > "$_log"
  run is_auth_error "$_log"
  [ "$status" -eq 0 ]
}

@test "is_auth_error: detects not_found_error" {
  printf 'Error: not_found_error — model not available\n' > "$_log"
  run is_auth_error "$_log"
  [ "$status" -eq 0 ]
}

# --- fail_reason_hint: permission_denied ---

@test "fail_reason_hint: permission_denied returns hint about skipping denied files" {
  run fail_reason_hint "permission_denied"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | grep -qi "permission\|denied\|skip"
}

# --- escalate_strategy: permission_denied ---

@test "escalate_strategy: escalates for permission_denied at consec=3" {
  run escalate_strategy "standard" "permission_denied" 3
  [ "$output" = "stripped" ]
}

@test "escalate_strategy: escalates for permission_denied at consec=5" {
  run escalate_strategy "standard" "permission_denied" 5
  [ "$output" = "targeted" ]
}
