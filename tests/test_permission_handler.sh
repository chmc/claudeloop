#!/usr/bin/env bats
# bats file_tags=permission_handler

# Tests for lib/permission_handler.sh — permission_filter, response builders, field extraction
# Note: bats uses FD 3 internally, so we must not use exec 3>&- in teardown.
# For permission_filter tests, we set PERMISSION_RESPONSE_FD and use FD 7.

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"
  source "${BATS_TEST_DIRNAME}/../lib/permission_handler.sh"
  VERBOSE_MODE=false
  SKIP_PERMISSIONS=true
  _tmpdir="$BATS_TEST_TMPDIR"
}

teardown() { :; }

# --- _extract_field() ---

@test "_extract_field: extracts simple string field" {
  local json='{"request_id":"req_123","type":"control_request"}'
  run _extract_field "$json" "request_id"
  [ "$status" -eq 0 ]
  [ "$output" = "req_123" ]
}

@test "_extract_field: extracts nested-looking field" {
  local json='{"type":"control_request","request_id":"abc-def-456"}'
  run _extract_field "$json" "request_id"
  [ "$status" -eq 0 ]
  [ "$output" = "abc-def-456" ]
}

@test "_extract_field: returns empty for missing field" {
  local json='{"type":"control_request"}'
  run _extract_field "$json" "request_id"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "_extract_field: handles escaped quotes in value" {
  local json='{"name":"foo\"bar","type":"test"}'
  run _extract_field "$json" "name"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# --- _build_stream_message() ---

@test "_build_stream_message: produces valid JSON structure" {
  run _build_stream_message "Hello world"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"type":"user"'
  echo "$output" | grep -q '"role":"user"'
  echo "$output" | grep -q '"content":"Hello world"'
  echo "$output" | grep -q '"session_id"'
}

@test "_build_stream_message: escapes special characters" {
  run _build_stream_message 'Line 1
Line 2	with tab and "quotes"'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\\n'
  echo "$output" | grep -q '\\t'
  echo "$output" | grep -q '\\"'
}

@test "_build_stream_message: handles backslashes" {
  run _build_stream_message 'path\to\file'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\\\\'
}

# --- _build_deny_response() ---

@test "_build_deny_response: builds valid deny JSON" {
  local request='{"type":"control_request","request_id":"req_abc123","request":{"type":"can_use_tool","tool_name":"Write","input":{"file_path":"/tmp/test"}}}'
  run _build_deny_response "$request"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"type":"control_response"'
  echo "$output" | grep -q '"request_id":"req_abc123"'
  echo "$output" | grep -q '"behavior":"deny"'
}

# --- _build_allow_response() ---

@test "_build_allow_response: builds valid allow JSON with updatedInput" {
  command -v node >/dev/null 2>&1 || skip "node.js not available"
  local request='{"type":"control_request","request_id":"req_xyz","request":{"type":"can_use_tool","tool_name":"Write","input":{"file_path":"/tmp/test.txt","content":"hello"}}}'
  run _build_allow_response "$request"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"type":"control_response"'
  echo "$output" | grep -q '"request_id":"req_xyz"'
  echo "$output" | grep -q '"behavior":"allow"'
  echo "$output" | grep -q '"updatedInput"'
}

@test "_build_allow_response: echoes back original input in updatedInput" {
  command -v node >/dev/null 2>&1 || skip "node.js not available"
  local request='{"type":"control_request","request_id":"req_001","request":{"type":"can_use_tool","tool_name":"Edit","input":{"file_path":"src/main.sh","old_string":"foo","new_string":"bar"}}}'
  result=$(_build_allow_response "$request")
  echo "$result" | node -e "
    const r=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const inp=r.response.response.updatedInput;
    if(inp.file_path!=='src/main.sh') process.exit(1);
    if(inp.old_string!=='foo') process.exit(1);
    if(inp.new_string!=='bar') process.exit(1);
  "
}

# --- permission_filter() ---
# Uses subshell with redirection to avoid bats FD conflicts.
# permission_filter reads stdin, writes pass-through to stdout, writes responses to FD 3.
# We redirect FD 3 to a file in a subshell wrapper.

_run_filter() {
  # Args: stdin content via pipe, FD output file path as $1
  local _fd_file="$1"
  (
    exec 7>"$_fd_file"
    permission_filter
    exec 7>&-
  )
}

@test "permission_filter: passes non-control events through unchanged" {
  local input='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hello"}]}}
{"type":"tool_use","name":"Edit","input":{},"id":"toolu_001"}
{"type":"result","total_cost_usd":0.01}'
  local fd3_out="$_tmpdir/fd3_pass"
  result=$(printf '%s\n' "$input" | _run_filter "$fd3_out")
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 3 ]
  echo "$result" | grep -q '"type":"assistant"'
  echo "$result" | grep -q '"type":"tool_use"'
  echo "$result" | grep -q '"type":"result"'
}

@test "permission_filter: intercepts control_request and does not pass it downstream" {
  command -v node >/dev/null 2>&1 || skip "node.js not available"
  SKIP_PERMISSIONS=true
  local fd3_out="$_tmpdir/fd3_intercept"
  local input='{"type":"control_request","request_id":"req_002","request":{"type":"can_use_tool","tool_name":"Write","input":{"file_path":"/tmp/x"}}}
{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}'
  result=$(printf '%s\n' "$input" | _run_filter "$fd3_out")
  # Only the assistant event should pass through
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 1 ]
  echo "$result" | grep -q '"type":"assistant"'
}

@test "permission_filter: ignores keep_alive events" {
  local fd3_out="$_tmpdir/fd3_keepalive"
  local input='{"type":"keep_alive","timestamp":"2026-01-01T00:00:00Z"}
{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}'
  result=$(printf '%s\n' "$input" | _run_filter "$fd3_out")
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 1 ]
  echo "$result" | grep -q '"type":"assistant"'
}

@test "permission_filter: ignores control_cancel_request events" {
  local fd3_out="$_tmpdir/fd3_cancel"
  local input='{"type":"control_cancel_request","request_id":"req_003"}
{"type":"result","total_cost_usd":0.01}'
  result=$(printf '%s\n' "$input" | _run_filter "$fd3_out")
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 1 ]
  echo "$result" | grep -q '"type":"result"'
}

@test "permission_filter: auto-approve writes allow response to permission FD" {
  command -v node >/dev/null 2>&1 || skip "node.js not available"
  SKIP_PERMISSIONS=true
  local fd3_out="$_tmpdir/fd3_allow"
  local input='{"type":"control_request","request_id":"req_005","request":{"type":"can_use_tool","tool_name":"Write","input":{"file_path":"/tmp/test.txt","content":"hi"}}}'
  printf '%s\n' "$input" | _run_filter "$fd3_out" >/dev/null
  [ -f "$fd3_out" ]
  grep -q '"type":"control_response"' "$fd3_out"
  grep -q '"behavior":"allow"' "$fd3_out"
  grep -q '"updatedInput"' "$fd3_out"
}
