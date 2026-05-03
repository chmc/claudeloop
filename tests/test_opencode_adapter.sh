#!/usr/bin/env bats
# bats file_tags=opencode,adapter,provider

# Tests for lib/adapters/opencode.sh — OpenCode adapter functions and event normalization
# Contract tests, event normalization, and integration with provider dispatch

setup() {
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/.."
  . "${BATS_TEST_DIRNAME}/../lib/ui.sh"
  VERBOSE_MODE=false
  _tmpdir="$BATS_TEST_TMPDIR"
}

teardown() { :; }

# Load adapter directly for unit tests
_load_adapter() {
  . "${BATS_TEST_DIRNAME}/../lib/adapters/opencode.sh"
}

# Load provider layer for integration tests
_load_provider() {
  . "${BATS_TEST_DIRNAME}/../lib/provider.sh"
}

# --- Contract Tests: Adapter Function Returns ---

@test "_opencode_cli: returns opencode" {
  _load_adapter
  run _opencode_cli
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
}

@test "_opencode_exec_args: returns --format json --stream" {
  _load_adapter
  run _opencode_exec_args
  [ "$status" -eq 0 ]
  [ "$output" = "--format json --stream" ]
}

@test "_opencode_print_args: returns --format json" {
  _load_adapter
  run _opencode_print_args
  [ "$status" -eq 0 ]
  [ "$output" = "--format json" ]
}

@test "_opencode_permission_protocol: returns http" {
  _load_adapter
  run _opencode_permission_protocol
  [ "$status" -eq 0 ]
  [ "$output" = "http" ]
}

@test "_opencode_verdict_pass_keyword: returns VERIFICATION_PASSED" {
  _load_adapter
  run _opencode_verdict_pass_keyword
  [ "$status" -eq 0 ]
  [ "$output" = "VERIFICATION_PASSED" ]
}

@test "_opencode_verdict_fail_keyword: returns VERIFICATION_FAILED" {
  _load_adapter
  run _opencode_verdict_fail_keyword
  [ "$status" -eq 0 ]
  [ "$output" = "VERIFICATION_FAILED" ]
}

@test "_opencode_write_tool_pattern: returns Edit|Write|NotebookEdit|Agent" {
  _load_adapter
  run _opencode_write_tool_pattern
  [ "$status" -eq 0 ]
  [ "$output" = "Edit|Write|NotebookEdit|Agent" ]
}

@test "_opencode_raw_write_tool_pattern: returns pre-normalization pattern" {
  _load_adapter
  run _opencode_raw_write_tool_pattern
  [ "$status" -eq 0 ]
  [ "$output" = "edit|write|file\.edit|file\.write|apply_patch" ]
}

# --- Event Normalization Tests ---

@test "normalize_events: session.created maps to system init" {
  _load_adapter
  local input='{"type":"session.created","model":"gpt-4"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"type":"system"'* ]]
  [[ "$result" == *'"subtype":"init"'* ]]
  [[ "$result" == *'"model":"gpt-4"'* ]]
}

@test "normalize_events: session.created with missing model defaults to opencode" {
  _load_adapter
  local input='{"type":"session.created"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"model":"opencode"'* ]]
}

@test "normalize_events: message.part.updated (text) maps to assistant" {
  _load_adapter
  local input='{"type":"message.part.updated","text":"Hello world"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"type":"assistant"'* ]]
  [[ "$result" == *'"text":"Hello world"'* ]]
}

@test "normalize_events: message.part.updated with content field maps to assistant" {
  _load_adapter
  local input='{"type":"message.part.updated","content":"Alternative content"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"type":"assistant"'* ]]
  [[ "$result" == *'"text":"Alternative content"'* ]]
}

@test "normalize_events: message.part.updated (tool pending) maps to tool_use" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"call_123","name":"Bash","state":"pending"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"type":"tool_use"'* ]]
  [[ "$result" == *'"id":"call_123"'* ]]
  [[ "$result" == *'"name":"Bash"'* ]]
}

@test "normalize_events: message.part.updated (tool running) does not emit new output" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"call_456","name":"Edit","state":"pending"}
{"type":"message.part.updated","callID":"call_456","name":"Edit","state":"running"}'
  result=$(echo "$input" | _opencode_normalize_events)
  line_count=$(echo "$result" | wc -l | tr -d ' ')
  [ "$line_count" -eq 1 ]
  [[ "$result" == *'"type":"tool_use"'* ]]
}

@test "normalize_events: message.part.updated (tool completed) maps to tool_result" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"call_789","name":"Read","state":"pending"}
{"type":"message.part.updated","callID":"call_789","name":"Read","state":"completed","output":"file contents"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"type":"tool_use"'* ]]
  [[ "$result" == *'"type":"tool_result"'* ]]
  [[ "$result" == *'"tool_use_id":"call_789"'* ]]
  [[ "$result" == *'"is_error":false'* ]]
  [[ "$result" == *'"content":"file contents"'* ]]
}

@test "normalize_events: message.part.updated (tool error) maps to tool_result with is_error true" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"call_error","name":"Bash","state":"pending"}
{"type":"message.part.updated","callID":"call_error","name":"Bash","state":"error","output":"command failed"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"type":"tool_result"'* ]]
  [[ "$result" == *'"is_error":true'* ]]
  [[ "$result" == *'"content":"command failed"'* ]]
}

@test "normalize_events: message.part.updated (tool failed state) maps to error result" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"call_fail","name":"Write","state":"pending"}
{"type":"message.part.updated","callID":"call_fail","name":"Write","state":"failed"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"is_error":true'* ]]
}

@test "normalize_events: file.edited maps to tool_use (Edit)" {
  _load_adapter
  local input='{"type":"file.edited","path":"/tmp/test.txt"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"type":"tool_use"'* ]]
  [[ "$result" == *'"name":"Edit"'* ]]
  [[ "$result" == *'"/tmp/test.txt"'* ]]
}

@test "normalize_events: file.edited with file field instead of path" {
  _load_adapter
  local input='{"type":"file.edited","file":"/home/user/code.sh"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"name":"Edit"'* ]]
  [[ "$result" == *'"/home/user/code.sh"'* ]]
}

@test "normalize_events: session.idle maps to result" {
  _load_adapter
  local input='{"type":"session.idle"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [ "$result" = '{"type":"result"}' ]
}

@test "normalize_events: duplicate callID pending events emit single tool_use" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"dup_001","name":"Grep","state":"pending"}
{"type":"message.part.updated","callID":"dup_001","name":"Grep","state":"pending"}
{"type":"message.part.updated","callID":"dup_001","name":"Grep","state":"pending"}'
  result=$(echo "$input" | _opencode_normalize_events)
  tool_use_count=$(echo "$result" | grep -c '"type":"tool_use"' || true)
  [ "$tool_use_count" -eq 1 ]
}

@test "normalize_events: duplicate tool result events emit single tool_result" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"dup_002","name":"Read","state":"pending"}
{"type":"message.part.updated","callID":"dup_002","name":"Read","state":"completed","output":"result1"}
{"type":"message.part.updated","callID":"dup_002","name":"Read","state":"completed","output":"result2"}'
  result=$(echo "$input" | _opencode_normalize_events)
  tool_result_count=$(echo "$result" | grep -c '"type":"tool_result"' || true)
  [ "$tool_result_count" -eq 1 ]
}

@test "normalize_events: malformed JSON goes to stderr, not stdout" {
  _load_adapter
  local input='not valid json
{"type":"session.idle"}'
  result=$(echo "$input" | _opencode_normalize_events 2>"$_tmpdir/stderr_out")
  [ "$result" = '{"type":"result"}' ]
  grep -q "malformed input" "$_tmpdir/stderr_out"
}

@test "normalize_events: JSON without type field goes to stderr" {
  _load_adapter
  local input='{"foo":"bar","baz":123}'
  result=$(echo "$input" | _opencode_normalize_events 2>"$_tmpdir/stderr_out")
  [ -z "$result" ]
  grep -q "malformed JSON (no type)" "$_tmpdir/stderr_out"
}

@test "normalize_events: handles escaped quotes in text" {
  _load_adapter
  local input='{"type":"message.part.updated","text":"He said \"hello\""}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"type":"assistant"'* ]]
  [[ "$result" == *'\"hello\"'* ]]
}

@test "normalize_events: handles newlines in text" {
  _load_adapter
  local input='{"type":"message.part.updated","text":"line1\nline2"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"text":"line1\nline2"'* ]]
}

@test "normalize_events: alternative call_id field works" {
  _load_adapter
  local input='{"type":"message.part.updated","call_id":"alt_123","name":"Agent","state":"pending"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"id":"alt_123"'* ]]
}

@test "normalize_events: toolCallId field works" {
  _load_adapter
  local input='{"type":"message.part.updated","toolCallId":"tc_456","name":"Write","state":"pending"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"id":"tc_456"'* ]]
}

@test "normalize_events: alternative toolName field works" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"tn_001","toolName":"Glob","state":"pending"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"name":"Glob"'* ]]
}

@test "normalize_events: alternative tool field works" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"tf_001","tool":"NotebookEdit","state":"pending"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"name":"NotebookEdit"'* ]]
}

@test "normalize_events: result field works for output" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"res_001","name":"Bash","state":"pending"}
{"type":"message.part.updated","callID":"res_001","name":"Bash","state":"completed","result":"command output"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"content":"command output"'* ]]
}

@test "normalize_events: content field works for output" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"cnt_001","name":"Read","state":"pending"}
{"type":"message.part.updated","callID":"cnt_001","name":"Read","state":"done","content":"file data"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [[ "$result" == *'"content":"file data"'* ]]
}

@test "normalize_events: unknown event types pass through unchanged" {
  _load_adapter
  local input='{"type":"custom.event","data":"some value"}'
  result=$(echo "$input" | _opencode_normalize_events)
  [ "$result" = '{"type":"custom.event","data":"some value"}' ]
}

@test "normalize_events: multiple events in sequence" {
  _load_adapter
  local input='{"type":"session.created","model":"test-model"}
{"type":"message.part.updated","text":"Starting task"}
{"type":"message.part.updated","callID":"seq_001","name":"Bash","state":"pending"}
{"type":"message.part.updated","callID":"seq_001","name":"Bash","state":"completed","output":"done"}
{"type":"session.idle"}'
  result=$(echo "$input" | _opencode_normalize_events)
  line_count=$(echo "$result" | wc -l | tr -d ' ')
  [ "$line_count" -eq 5 ]
  echo "$result" | head -1 | grep -q '"type":"system"'
  echo "$result" | sed -n '2p' | grep -q '"type":"assistant"'
  echo "$result" | sed -n '3p' | grep -q '"type":"tool_use"'
  echo "$result" | sed -n '4p' | grep -q '"type":"tool_result"'
  echo "$result" | sed -n '5p' | grep -q '"type":"result"'
}

# --- Integration Tests: Provider Dispatch ---

# Helper to load provider with specific PROVIDER setting
_load_opencode_provider() {
  export PROVIDER=opencode
  . "${BATS_TEST_DIRNAME}/../lib/provider.sh"
}

_load_claude_provider() {
  export PROVIDER=claude
  . "${BATS_TEST_DIRNAME}/../lib/provider.sh"
}

@test "provider_detect: returns opencode when PROVIDER=opencode" {
  _load_opencode_provider
  run provider_detect
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
}

@test "provider_cli: returns opencode when PROVIDER=opencode" {
  _load_opencode_provider
  run provider_cli
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
}

@test "provider_exec_args: returns OpenCode flags when PROVIDER=opencode" {
  _load_opencode_provider
  run provider_exec_args
  [ "$status" -eq 0 ]
  [ "$output" = "--format json --stream" ]
}

@test "provider_print_args: returns OpenCode flags when PROVIDER=opencode" {
  _load_opencode_provider
  run provider_print_args
  [ "$status" -eq 0 ]
  [ "$output" = "--format json" ]
}

@test "provider_permission_protocol: returns http for PROVIDER=opencode" {
  _load_opencode_provider
  run provider_permission_protocol
  [ "$status" -eq 0 ]
  [ "$output" = "http" ]
}

@test "provider_normalize_events: returns cat passthrough for Claude" {
  _load_claude_provider
  local input='{"type":"assistant","text":"hello"}'
  result=$(echo "$input" | provider_normalize_events)
  [ "$result" = '{"type":"assistant","text":"hello"}' ]
}

@test "provider_normalize_events: normalizes events for OpenCode" {
  _load_opencode_provider
  local input='{"type":"session.idle"}'
  result=$(echo "$input" | provider_normalize_events)
  [ "$result" = '{"type":"result"}' ]
}

@test "provider_write_tool_pattern: returns same pattern for both providers" {
  _load_claude_provider
  claude_pattern=$(provider_write_tool_pattern)
  _load_opencode_provider
  opencode_pattern=$(provider_write_tool_pattern)
  [ "$claude_pattern" = "$opencode_pattern" ]
  [ "$opencode_pattern" = "Edit|Write|NotebookEdit|Agent" ]
}

@test "provider_verdict_pass_keyword: returns same keyword for both providers" {
  _load_claude_provider
  claude_kw=$(provider_verdict_pass_keyword)
  _load_opencode_provider
  opencode_kw=$(provider_verdict_pass_keyword)
  [ "$claude_kw" = "$opencode_kw" ]
  [ "$opencode_kw" = "VERIFICATION_PASSED" ]
}

@test "provider_verdict_fail_keyword: returns same keyword for both providers" {
  _load_claude_provider
  claude_kw=$(provider_verdict_fail_keyword)
  _load_opencode_provider
  opencode_kw=$(provider_verdict_fail_keyword)
  [ "$claude_kw" = "$opencode_kw" ]
  [ "$opencode_kw" = "VERIFICATION_FAILED" ]
}

# --- Integration: Normalized Events Flow Through Stream Processing ---

@test "integration: normalized OpenCode events compatible with process_stream_json structure" {
  _load_adapter
  local input='{"type":"message.part.updated","text":"Test message"}'
  result=$(echo "$input" | _opencode_normalize_events)
  echo "$result" | grep -q '"type":"assistant"'
  echo "$result" | grep -q '"text":"Test message"'
}

@test "integration: tool_use from normalized event has required fields" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"integ_001","name":"Edit","state":"pending"}'
  result=$(echo "$input" | _opencode_normalize_events)
  echo "$result" | grep -q '"type":"tool_use"'
  echo "$result" | grep -q '"id":'
  echo "$result" | grep -q '"name":'
}

@test "integration: tool_result from normalized event has required fields" {
  _load_adapter
  local input='{"type":"message.part.updated","callID":"integ_002","name":"Bash","state":"pending"}
{"type":"message.part.updated","callID":"integ_002","name":"Bash","state":"completed","output":"success"}'
  result=$(echo "$input" | _opencode_normalize_events)
  echo "$result" | grep -q '"type":"tool_result"'
  echo "$result" | grep -q '"tool_use_id":'
  echo "$result" | grep -q '"is_error":'
}
