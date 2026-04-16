#!/usr/bin/env bash
# bats file_tags=fake_claude

# Tests for the fake Claude CLI (tests/fake_claude).
# Validates each scenario produces correct NDJSON for the stream processor.

FAKE_CLAUDE="${BATS_TEST_DIRNAME}/fake_claude"

setup() {
  FAKE_DIR="$BATS_TEST_TMPDIR/fake"
  mkdir -p "$FAKE_DIR"
  export FAKE_CLAUDE_DIR="$FAKE_DIR"
  # Source retry.sh for detection helpers
  . "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  # Isolate CWD so fake_claude file writes don't pollute project directory
  cd "$BATS_TEST_TMPDIR"
}

teardown() {
  cd /
}

# Helper: run fake_claude with a scenario
run_scenario() {
  printf '%s' "$1" > "$FAKE_CLAUDE_DIR/scenario"
  FAKE_CLAUDE_THINK=0 echo "test prompt" | "$FAKE_CLAUDE" --print 2>&1
}

# --- NDJSON validity ---

@test "success scenario: every line is valid JSON (starts with {)" {
  output=$(run_scenario "success")
  while IFS= read -r line; do
    [[ "$line" == "{"* ]] || { echo "Bad line: $line"; return 1; }
  done <<< "$output"
}

@test "success_multi scenario: every line is valid JSON" {
  output=$(run_scenario "success_multi")
  while IFS= read -r line; do
    [[ "$line" == "{"* ]] || { echo "Bad line: $line"; return 1; }
  done <<< "$output"
}

# --- Detection function compatibility ---

@test "success scenario: has_write_actions detects Edit" {
  run_scenario "success" > "$FAKE_DIR/test.raw.json"
  # Wrap in execution block like real logs
  { printf '=== EXECUTION START ===\n'; cat "$FAKE_DIR/test.raw.json"; } > "$FAKE_DIR/wrapped.raw.json"
  has_write_actions "$FAKE_DIR/wrapped.raw.json"
}

@test "success_multi scenario: has_write_actions detects writes" {
  run_scenario "success_multi" > "$FAKE_DIR/test.raw.json"
  { printf '=== EXECUTION START ===\n'; cat "$FAKE_DIR/test.raw.json"; } > "$FAKE_DIR/wrapped.raw.json"
  has_write_actions "$FAKE_DIR/wrapped.raw.json"
}

@test "quota_error scenario: is_quota_error matches" {
  printf 'quota_error\n' > "$FAKE_CLAUDE_DIR/scenario"
  echo "test" | "$FAKE_CLAUDE" --print > "$FAKE_DIR/test.log" || true
  is_quota_error "$FAKE_DIR/test.log"
}

@test "permission_error scenario: is_permission_error matches" {
  run_scenario "permission_error" > "$FAKE_DIR/test.log"
  is_permission_error "$FAKE_DIR/test.log"
}

# --- Verification contract ---

@test "verify_pass: exit 0 + tool_use + VERIFICATION_PASSED" {
  run_scenario "verify_pass" > "$FAKE_DIR/test.raw.json"
  # Check exit code
  echo "test prompt" | "$FAKE_CLAUDE" --print; rc=$?
  [ "$rc" -eq 0 ]
  # Check tool_use present
  grep -q '"type":"tool_use"' "$FAKE_DIR/test.raw.json"
  # Check verdict present
  grep -q 'VERIFICATION_PASSED' "$FAKE_DIR/test.raw.json"
}

@test "verify_fail: has VERIFICATION_FAILED" {
  run_scenario "verify_fail" > "$FAKE_DIR/test.raw.json"
  grep -q 'VERIFICATION_FAILED' "$FAKE_DIR/test.raw.json"
}

@test "verify_skip: has VERIFICATION_PASSED but NO tool_use (anti-skip)" {
  run_scenario "verify_skip" > "$FAKE_DIR/test.raw.json"
  grep -q 'VERIFICATION_PASSED' "$FAKE_DIR/test.raw.json"
  ! grep -q '"type":"tool_use"' "$FAKE_DIR/test.raw.json"
}

# --- Stream processor integration ---

@test "success_multi through process_stream_json produces Session line" {
  . "${BATS_TEST_DIRNAME}/../lib/stream_processor.sh"
  run_scenario "success_multi" > "$FAKE_DIR/input.json"
  log="$FAKE_DIR/formatted.log"
  raw="$FAKE_DIR/raw.log"
  : > "$log"; : > "$raw"
  output=$(cat "$FAKE_DIR/input.json" | process_stream_json "$log" "$raw" "false" "" "true" "0" 2>&1)
  echo "$output" | grep -q '\[Session:'
}

# --- Call counting ---

@test "call counting: 3 calls increments to 3" {
  printf 'success\n' > "$FAKE_CLAUDE_DIR/scenario"
  echo "p1" | "$FAKE_CLAUDE" --print >/dev/null
  echo "p2" | "$FAKE_CLAUDE" --print >/dev/null
  echo "p3" | "$FAKE_CLAUDE" --print >/dev/null
  count=$(cat "$FAKE_CLAUDE_DIR/call_count")
  [ "$count" = "3" ]
}

# --- Per-call scenario selection ---

@test "per-call scenarios: call 1=success, call 2=failure, call 3=success" {
  printf 'success\nfailure\nsuccess\n' > "$FAKE_CLAUDE_DIR/scenarios"
  rc1=0; echo "p1" | "$FAKE_CLAUDE" --print >/dev/null || rc1=$?
  rc2=0; echo "p2" | "$FAKE_CLAUDE" --print >/dev/null || rc2=$?
  rc3=0; echo "p3" | "$FAKE_CLAUDE" --print >/dev/null || rc3=$?
  [ "$rc1" -eq 0 ]
  [ "$rc2" -eq 1 ]
  [ "$rc3" -eq 0 ]
}

# --- Per-call exit code override ---

@test "exit code override: scenario success but exit 42" {
  printf 'success\n' > "$FAKE_CLAUDE_DIR/scenario"
  printf '42\n' > "$FAKE_CLAUDE_DIR/exit_codes"
  rc=0; echo "test" | "$FAKE_CLAUDE" --print >/dev/null || rc=$?
  [ "$rc" -eq 42 ]
}

# --- Prompt/args capture ---

@test "prompt capture: stdin is saved to prompts/prompt_N" {
  printf 'success\n' > "$FAKE_CLAUDE_DIR/scenario"
  printf 'hello world' | "$FAKE_CLAUDE" --print --verbose >/dev/null
  [ -f "$FAKE_CLAUDE_DIR/prompts/prompt_1" ]
  content=$(cat "$FAKE_CLAUDE_DIR/prompts/prompt_1")
  [ "$content" = "hello world" ]
}

@test "args capture: CLI args saved to args/args_N" {
  printf 'success\n' > "$FAKE_CLAUDE_DIR/scenario"
  echo "test" | "$FAKE_CLAUDE" --print --verbose --output-format=stream-json >/dev/null
  [ -f "$FAKE_CLAUDE_DIR/args/args_1" ]
  grep -q '\-\-print' "$FAKE_CLAUDE_DIR/args/args_1"
  grep -q '\-\-verbose' "$FAKE_CLAUDE_DIR/args/args_1"
}

# --- Empty scenario ---

@test "empty scenario: produces no output" {
  output=$(run_scenario "empty")
  [ -z "$output" ]
}

# --- Failure scenario ---

@test "failure scenario: exits non-zero" {
  printf 'failure\n' > "$FAKE_CLAUDE_DIR/scenario"
  rc=0; echo "test" | "$FAKE_CLAUDE" --print >/dev/null || rc=$?
  [ "$rc" -eq 1 ]
}

# --- Custom scenario ---

@test "custom scenario: emits lines from custom_output file" {
  printf 'custom\n' > "$FAKE_CLAUDE_DIR/scenario"
  printf '{"type":"system","subtype":"init","model":"custom-model"}\n' > "$FAKE_CLAUDE_DIR/custom_output"
  output=$(echo "test" | "$FAKE_CLAUDE" --print 2>&1)
  echo "$output" | grep -q '"model":"custom-model"'
}

# --- Rate limit scenario ---

@test "rate_limit scenario: contains rate_limit_event" {
  output=$(run_scenario "rate_limit")
  echo "$output" | grep -q '"type":"rate_limit_event"'
}

# --- Default scenario ---

@test "no scenario configured: defaults to success" {
  output=$(echo "test" | "$FAKE_CLAUDE" --print 2>&1)
  echo "$output" | grep -q '"type":"system"'
  echo "$output" | grep -q '"name":"Edit"'
}

# --- Slow scenario respects FAKE_CLAUDE_SLEEP ---

@test "slow scenario: respects FAKE_CLAUDE_SLEEP" {
  FAKE_CLAUDE_SLEEP=0 run_scenario "slow" >/dev/null
  # Just verify it exits (sleep 0 = instant)
}

# --- Verbose scenario ---

@test "success_verbose scenario: every line is valid JSON" {
  output=$(run_scenario "success_verbose")
  while IFS= read -r line; do
    [[ "$line" == "{"* ]] || { echo "Bad line: $line"; return 1; }
  done <<< "$output"
}

@test "success_verbose scenario: produces 30+ lines (fills terminal)" {
  output=$(run_scenario "success_verbose")
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$line_count" -ge 30 ]
}

@test "success_verbose scenario: has_write_actions detects edits" {
  run_scenario "success_verbose" > "$FAKE_DIR/test.raw.json"
  { printf '=== EXECUTION START ===\n'; cat "$FAKE_DIR/test.raw.json"; } > "$FAKE_DIR/wrapped.raw.json"
  has_write_actions "$FAKE_DIR/wrapped.raw.json"
}

@test "success_verbose through process_stream_json produces Session with cache tokens" {
  . "${BATS_TEST_DIRNAME}/../lib/stream_processor.sh"
  run_scenario "success_verbose" > "$FAKE_DIR/input.json"
  log="$FAKE_DIR/formatted.log"
  raw="$FAKE_DIR/raw.log"
  : > "$log"; : > "$raw"
  output=$(cat "$FAKE_DIR/input.json" | process_stream_json "$log" "$raw" "false" "" "true" "0" 2>&1)
  echo "$output" | grep -q '\[Session:'
  echo "$output" | grep -q 'cache='
}

# --- Verbose scenario: TodoWrite + TaskCreate ---

@test "success_verbose scenario: contains TodoWrite events" {
  output=$(run_scenario "success_verbose")
  echo "$output" | grep -q '"name":"TodoWrite"'
}

@test "success_verbose scenario: contains TaskCreate event" {
  output=$(run_scenario "success_verbose")
  echo "$output" | grep -q '"name":"TaskCreate"'
}

# --- AI parse auto-detection ---
# Tests that success scenarios auto-detect AI-parse and verification prompts
# and emit the correct response format (phase headers, PASS, VERIFICATION_PASSED).

# Helper: run fake_claude with a specific prompt (not the generic "test prompt")
# Note: FAKE_CLAUDE_THINK=0 disables think delays in success_verbose scenario.
run_with_prompt() {
  local scenario="$1" prompt="$2"
  printf '%s' "$scenario" > "$FAKE_CLAUDE_DIR/scenario"
  FAKE_CLAUDE_THINK=0 printf '%s' "$prompt" | "$FAKE_CLAUDE" --print 2>&1
}

@test "success scenario: AI-parse prompt emits ## Phase headers" {
  output=$(run_with_prompt "success" "You are a plan extraction assistant. Extract phases using ## Phase N: Title format.")
  echo "$output" | grep -q '## Phase [0-9]'
}

@test "success scenario: normal prompt emits tool_use (unchanged)" {
  output=$(run_with_prompt "success" "Please fix the bug in main.sh")
  echo "$output" | grep -q '"name":"Edit"'
  ! echo "$output" | grep -q '## Phase'
}

@test "ai_parse scenario: emits ## Phase headers" {
  output=$(run_scenario "ai_parse")
  echo "$output" | grep -q '## Phase 1:'
  echo "$output" | grep -q '## Phase 2:'
}

@test "ai_parse scenario: no tool_use events" {
  output=$(run_scenario "ai_parse")
  ! echo "$output" | grep -q '"type":"tool_use"'
}

@test "success scenario: AI-verify prompt emits PASS" {
  output=$(run_with_prompt "success" "Compare the ORIGINAL requirements with the DECOMPOSED plan.")
  echo "$output" | grep -q 'PASS'
}

@test "success scenario: phase-verify prompt emits VERIFICATION_PASSED" {
  output=$(run_with_prompt "success" "Run verification checks on the phase implementation")
  echo "$output" | grep -q 'VERIFICATION_PASSED'
}

# --- Golden file conformance ---

@test "conformance: success scenario uses same event types as golden file" {
  golden="${BATS_TEST_DIRNAME}/fixtures/stream_json_sample.ndjson"
  [ -f "$golden" ] || skip "golden file not found"
  # Extract unique "type" values from golden file
  golden_types=$(grep -o '"type":"[^"]*"' "$golden" | sort -u)
  # Extract unique "type" values from success_multi (most comprehensive scenario)
  fake_output=$(run_scenario "success_multi")
  fake_types=$(echo "$fake_output" | grep -o '"type":"[^"]*"' | sort -u)
  # Every type in fake output must exist in golden file
  while IFS= read -r t; do
    echo "$golden_types" | grep -qF "$t" || { echo "Type $t not in golden file"; return 1; }
  done <<< "$fake_types"
}

# --- File-writing behavior ---

@test "success scenario: writes file to disk" {
  run_scenario "success" > /dev/null
  [ -f "test.sh" ]
}

@test "success_multi scenario: writes file to disk" {
  run_scenario "success_multi" > /dev/null
  [ -f "test.sh" ]
}

@test "success_realistic scenario: writes file to disk" {
  run_scenario "success_realistic" > /dev/null
  [ -f "src/main.sh" ]
}

@test "failure scenario: does NOT write files" {
  run_scenario "failure" > /dev/null 2>&1 || true
  [ ! -f "test.sh" ]
}
