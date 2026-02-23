#!/usr/bin/env bash
# bats file_tags=stream_processor

# Tests for lib/stream_processor.sh

STREAM_PROCESSOR_LIB="${BATS_TEST_DIRNAME}/../lib/stream_processor.sh"

setup() {
  _log="$(mktemp)"
  _raw="$(mktemp)"
  . "$STREAM_PROCESSOR_LIB"   # makes process_stream_json available
}

teardown() {
  rm -f "$_log" "$_raw"
}

# Helper: run processor with given stdin
run_processor() {
  echo "$1" | process_stream_json "$_log" "$_raw"
}

# --- assistant text event ---

@test "assistant text event: text written to stdout and log" {
  local event='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello world"}]}}'
  run run_processor "$event"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello world"* ]]
  grep -q "Hello world" "$_log"
}

@test "assistant text event: line prefixed with timestamp [HH:MM:SS]" {
  local event='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello world"}]}}'
  run run_processor "$event"
  [ "$status" -eq 0 ]
  [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\]\ Hello\ world ]]
}

@test "assistant text event: raw JSON written to raw_log" {
  local event='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}'
  run_processor "$event" > /dev/null 2>&1
  grep -q '"type":"assistant"' "$_raw"
}

@test "assistant text event: tool events not written to text log" {
  local event='{"type":"tool_use","name":"Bash","input":{"command":"ls /"}}'
  run_processor "$event" > /dev/null 2>&1
  # text log should not contain [Tool:
  if grep -q '\[Tool:' "$_log"; then
    false
  fi
  true
}

# --- tool_use event ---

@test "tool_use event: [Tool: Bash] emitted to stderr" {
  local event='{"type":"tool_use","name":"Bash","input":{"command":"ls /path"}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: Bash]"* ]]
  [[ "$output" == *"ls /path"* ]]
}

@test "tool_use event: [Tool: Read] shows file path" {
  local event='{"type":"tool_use","name":"Read","input":{"file_path":"/some/file.sh"}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: Read]"* ]]
  [[ "$output" == *"/some/file.sh"* ]]
}

@test "tool_use event: tool line not written to text log" {
  local event='{"type":"tool_use","name":"Bash","input":{"command":"echo hi"}}'
  run_processor "$event" > /dev/null 2>&1
  if grep -q '\[Tool:' "$_log"; then
    false
  fi
  true
}

# --- tool_result event ---

@test "tool_result event: [Tool result: N chars] emitted to stderr" {
  local event='{"type":"tool_result","content":"some output here"}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool result:"* ]]
  [[ "$output" == *"chars]"* ]]
}

@test "tool_result event: char count matches content length" {
  local content="abcdefghij"  # 10 chars
  local event="{\"type\":\"tool_result\",\"content\":\"$content\"}"
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool result: 10 chars]"* ]]
}

@test "tool_result event: not written to text log" {
  local event='{"type":"tool_result","content":"output"}'
  run_processor "$event" > /dev/null 2>&1
  if grep -q '\[Tool result:' "$_log"; then
    false
  fi
  true
}

# --- result event ---

@test "result event: session summary appended to log" {
  local event='{"type":"result","total_cost_usd":0.0041,"duration_ms":18300,"num_turns":4,"usage":{"input_tokens":4200,"output_tokens":380}}'
  run_processor "$event" > /dev/null 2>&1
  grep -q '\[Session:' "$_log"
}

@test "result event: summary printed to stderr" {
  local event='{"type":"result","total_cost_usd":0.0041,"duration_ms":18300,"num_turns":4,"usage":{"input_tokens":4200,"output_tokens":380}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Session:"* ]]
}

@test "result event: contains cost, duration, turns, tokens" {
  local event='{"type":"result","total_cost_usd":0.0041,"duration_ms":18300,"num_turns":4,"usage":{"input_tokens":4200,"output_tokens":380}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cost="* ]]
  [[ "$output" == *"duration="* ]]
  [[ "$output" == *"turns="* ]]
  [[ "$output" == *"tokens="* ]]
}

# --- non-JSON line ---

@test "non-JSON line: passed through to stdout and log" {
  run run_processor "This is not JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"This is not JSON"* ]]
  grep -q "This is not JSON" "$_log"
}

@test "non-JSON line: also written to raw_log" {
  run_processor "plain text line" > /dev/null 2>&1
  grep -q "plain text line" "$_raw"
}

# --- empty input ---

@test "empty input: no crash" {
  run bash -c "echo -n | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw'"
  [ "$status" -eq 0 ]
}

# --- newline separation (Change 3) ---

@test "tool_use after text without trailing newline: newline inserted in stdout" {
  local text1='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hello"}]}}'
  local tool='{"type":"tool_use","name":"Bash","input":{"command":"ls"}}'
  local text2='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"world\n"}]}}'
  run bash -c "printf '%s\n%s\n%s\n' '$text1' '$tool' '$text2' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  [[ "$output" == *"world"* ]]
}

# --- activity dots (Change 4) ---

@test "assistant event with empty text: spinner printed to stdout" {
  local event='{"type":"assistant","message":{"role":"assistant","content":[]}}'
  run run_processor "$event"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\r'* ]]
}

@test "unknown event type: spinner printed to stdout" {
  local event='{"type":"unknown_event"}'
  run run_processor "$event"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\r'* ]]
}

@test "consecutive silent events: each gets its own spinner update" {
  local e1='{"type":"assistant","message":{"role":"assistant","content":[]}}'
  local e2='{"type":"unknown_event"}'
  run bash -c "printf '%s\n%s\n' '$e1' '$e2' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  # Each silent event outputs \r; check at least two carriage returns
  count=$(printf '%s' "$output" | tr -cd $'\r' | wc -c | tr -d ' ')
  [ "$count" -ge 2 ]
}

@test "10 consecutive silent events: spinner shown, only one initial timestamp" {
  run bash -c "yes '{\"type\":\"unknown_event\"}' | head -10 | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  # Spinner carriage-return updates should appear
  [[ "$output" == *$'\r'* ]]
  # BEGIN prints one timestamp; spinner never emits extra timestamps
  count=$(printf '%s' "$output" | grep -o '\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]' | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "50 consecutive silent events: spinner shows elapsed time in seconds" {
  run bash -c "yes '{\"type\":\"unknown_event\"}' | head -50 | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  # Timer format like "0s" should appear in spinner output
  [[ "$output" =~ [0-9]+s ]]
}

@test "text after silent spinner: text starts on new line" {
  local silent='{"type":"unknown_event"}'
  local text='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hello\n"}]}}'
  run bash -c "printf '%s\n%s\n' '$silent' '$text' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\r'* ]]
  [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\]\ hello ]]
}

@test "spinner resets after visible text: second silent period starts fresh" {
  local silent='{"type":"unknown_event"}'
  local text='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi\n"}]}}'
  run bash -c "printf '%s\n%s\n%s\n' '$silent' '$text' '$silent' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\r'*"hi"*$'\r'* ]]
}

@test "spinner after mid-line text: spinner starts on new line" {
  local text='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hello"}]}}'
  local silent='{"type":"unknown_event"}'
  local text2='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"world\n"}]}}'
  run bash -c "printf '%s\n%s\n%s\n' '$text' '$silent' '$text2' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  # With fix: hello\n\r (newline before spinner)
  # Without fix: hello\r (spinner overwrites text line)
  [[ "$output" == *"hello"$'\n'$'\r'* ]]
}

# --- trunc_len configurable (Phase A change 1) ---

@test "tool_use event: 100-char command not truncated at 80 chars with default trunc_len" {
  # Build a 100-char command (all 'x')
  local cmd
  cmd=$(printf '%0.sx' {1..100})
  local event="{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"$cmd\"}}"
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  # The full 100-char command must appear in stderr output (not truncated at 80)
  [[ "$output" == *"$cmd"* ]]
}

@test "tool_use event: command truncated at custom STREAM_TRUNCATE_LEN=50" {
  # Build a 100-char command, set trunc_len to 50
  local cmd
  cmd=$(printf '%0.sx' {1..100})
  local expected
  expected=$(printf '%0.sx' {1..50})"..."
  run bash -c "STREAM_TRUNCATE_LEN=50 sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' <<'JSON'
{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"$cmd\"}}
JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$expected"* ]]
}

# --- tool_result content preview (Phase A change 2) ---

@test "tool_result event: content preview shown alongside char count" {
  local event='{"type":"tool_result","content":"hello preview output"}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool result:"* ]]
  [[ "$output" == *"hello preview output"* ]]
}

# --- hooks_enabled suppresses tool_use (Phase A change 3) ---

@test "tool_use event: suppressed when hooks_enabled=true" {
  local event='{"type":"tool_use","name":"Bash","input":{"command":"ls /"}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' true 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Tool: Bash]"* ]]
}

@test "tool_use event: shown when hooks_enabled=false" {
  local event='{"type":"tool_use","name":"Bash","input":{"command":"ls /"}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' false 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: Bash]"* ]]
}

# --- assistant event with nested tool_use (Phase A+) ---

@test "assistant event with tool_use: [Tool: Bash] shown to stderr" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: Bash]"* ]]
}

@test "assistant event with tool_use: Bash command shown in preview" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git status"* ]]
}

@test "assistant event with tool_use: description shown after command" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status","description":"Show working tree status"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Show working tree status"* ]]
}

@test "assistant event with tool_use: Read shows file_path" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/some/file.sh"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: Read]"* ]]
  [[ "$output" == *"/some/file.sh"* ]]
}

@test "assistant event with tool_use: suppressed when hooks_enabled=true" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' true 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Tool: Bash]"* ]]
}

# --- type:user event with tool_use_result (Phase A+) ---

@test "type:user event with tool_use_result: result shown to stderr" {
  local event='{"type":"user","message":{},"tool_use_result":"output text here"}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Result:"* ]]
  [[ "$output" == *"chars]"* ]]
}

@test "type:user event with is_error:true: [error] label shown" {
  local event='{"type":"user","message":{},"tool_use_result":"error text","is_error":true}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Result [error]:"* ]]
}

@test "type:user event with is_error:false: no [error] label" {
  local event='{"type":"user","message":{},"tool_use_result":"output text","is_error":false}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Result:"* ]]
  [[ "$output" != *"[error]"* ]]
}

@test "type:user event without tool_use_result: no output" {
  local event='{"type":"user","message":{"content":"hello"}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Result"* ]]
}

# --- rate_limit_event (Phase A+) ---

@test "rate_limit_event: warning shown when utilization=0.91" {
  local event='{"type":"rate_limit_event","utilization":0.91}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Rate limit: 91%"* ]]
}

@test "rate_limit_event: warning shown when utilization=0.75" {
  local event='{"type":"rate_limit_event","utilization":0.75}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Rate limit: 75%"* ]]
}

@test "rate_limit_event: warning suppressed when lower utilization follows higher" {
  local event1='{"type":"rate_limit_event","utilization":0.91}'
  local event2='{"type":"rate_limit_event","utilization":0.50}'
  run bash -c "printf '%s\n%s\n' '$event1' '$event2' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Rate limit: 91%"* ]]
  [[ "$output" != *"[Rate limit: 50%"* ]]
}

@test "rate_limit_event: deduplicated when same pct fires twice" {
  local event='{"type":"rate_limit_event","utilization":0.91}'
  run bash -c "printf '%s\n%s\n' '$event' '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  count=$(printf '%s' "$output" | grep -c '\[Rate limit: 91%')
  [ "$count" -eq 1 ]
}

# --- Phase B: more tool previews (§1) ---

@test "assistant event with WebFetch: url shown in preview" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebFetch","input":{"url":"https://example.com","prompt":"summarize"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: WebFetch]"* ]]
  [[ "$output" == *"https://example.com"* ]]
}

@test "assistant event with WebSearch: query shown in preview" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebSearch","input":{"query":"awk tutorial"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: WebSearch]"* ]]
  [[ "$output" == *"awk tutorial"* ]]
}

@test "assistant event with Task: subagent_type shown in preview" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"Bash","prompt":"run tests"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: Task]"* ]]
  [[ "$output" == *"Bash"* ]]
}

@test "assistant event with NotebookEdit: notebook_path shown in preview" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"NotebookEdit","input":{"notebook_path":"/some/notebook.ipynb"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: NotebookEdit]"* ]]
  [[ "$output" == *"/some/notebook.ipynb"* ]]
}

# --- Phase B: iteration + ID deduplication (§2) ---

@test "assistant event with two tool_use blocks: both shown" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_001","name":"Bash","input":{"command":"ls"}},{"type":"tool_use","id":"toolu_002","name":"Read","input":{"file_path":"/some/file"}}]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Tool: Bash]"* ]]
  [[ "$output" == *"[Tool: Read]"* ]]
}

@test "assistant event with tool_use: same toolu_ id shown only once across two events" {
  local event='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_abc","name":"Bash","input":{"command":"ls"}}]}}'
  run bash -c "printf '%s\n%s\n' '$event' '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  count=$(printf '%s' "$output" | grep -c '\[Tool: Bash\]')
  [ "$count" -eq 1 ]
}

# --- Phase B: stop_reason max_tokens warning (§3) ---

@test "assistant event with stop_reason max_tokens: warning shown" {
  local event='{"type":"assistant","message":{"stop_reason":"max_tokens","content":[]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"max_tokens"* ]]
  [[ "$output" == *"truncated"* ]]
}

@test "assistant event with stop_reason end_turn: no warning" {
  local event='{"type":"assistant","message":{"stop_reason":"end_turn","content":[]}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"truncated"* ]]
}

# --- Phase B: model in session summary (§4) ---

@test "result event with modelUsage: model shown in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":18300,"num_turns":4,"modelUsage":{"claude-sonnet-4-6":{"inputTokens":100,"outputTokens":10,"costUSD":0.001}},"usage":{"input_tokens":4200,"output_tokens":380}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"model=claude-sonnet-4-6"* ]]
}

# --- Phase B: system init event (§5) ---

@test "system init event with model: model shown to stderr" {
  local event='{"type":"system","subtype":"init","model":"claude-sonnet-4-6"}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"model=claude-sonnet-4-6"* ]]
}

@test "system init event with non-init subtype: no output" {
  local event='{"type":"system","subtype":"something_else","model":"claude-sonnet-4-6"}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"model="* ]]
}

@test "system init event without model field: no output" {
  local event='{"type":"system","subtype":"init"}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"model="* ]]
}

# --- live_log timestamp tests ---

@test "tool_use event: live log line has timestamp" {
  local _live
  _live=$(mktemp)
  local event='{"type":"tool_use","name":"Bash","input":{"command":"ls /"}}'
  echo "$event" | process_stream_json "$_log" "$_raw" false "$_live"
  grep -qE '\[[0-9]{2}:[0-9]{2}:[0-9]{2}\].*\[Tool: Bash\]' "$_live"
  rm -f "$_live"
}

@test "tool_result event: live log line has timestamp" {
  local _live
  _live=$(mktemp)
  local event='{"type":"tool_result","content":"some output"}'
  echo "$event" | process_stream_json "$_log" "$_raw" false "$_live"
  grep -qE '\[[0-9]{2}:[0-9]{2}:[0-9]{2}\].*\[Tool result:' "$_live"
  rm -f "$_live"
}

@test "text without newline followed by tool_use: tool entry on its own line in live log" {
  local _live
  _live=$(mktemp)
  local text='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Let me start"}]}}'
  local tool='{"type":"tool_use","name":"Bash","input":{"command":"ls /"}}'
  printf '%s\n%s\n' "$text" "$tool" | process_stream_json "$_log" "$_raw" false "$_live"
  # Tool line must begin at column 0 (not appended after text)
  grep -qE '^  \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] \[Tool: Bash\]' "$_live"
  rm -f "$_live"
}

@test "text without newline followed by tool_use: tool entry not appended to text line" {
  local _live
  _live=$(mktemp)
  local text='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Let me start"}]}}'
  local tool='{"type":"tool_use","name":"Bash","input":{"command":"ls /"}}'
  printf '%s\n%s\n' "$text" "$tool" | process_stream_json "$_log" "$_raw" false "$_live"
  # The text "Let me start" must NOT appear on the same line as [Tool: Bash]
  run grep 'Let me start.*\[Tool: Bash\]' "$_live"
  [ "$status" -eq 1 ]
  rm -f "$_live"
}

# --- Cost delta tracking ---

@test "result event: first event shows full cost as delta from zero" {
  local event='{"type":"result","total_cost_usd":0.0100,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cost=\$0.0100"* ]]
}

@test "result event: two sequential events second shows delta cost not cumulative" {
  local event1='{"type":"result","total_cost_usd":0.0100,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10}}'
  local event2='{"type":"result","total_cost_usd":0.0160,"duration_ms":500,"num_turns":1,"usage":{"input_tokens":50,"output_tokens":5}}'
  run bash -c "printf '%s\n%s\n' '$event1' '$event2' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cost=\$0.0060"* ]]
  [[ "$output" != *"cost=\$0.0160"* ]]
}

# --- Cache stats ---

@test "result event with non-zero cache_read tokens: cache= shown in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":500,"cache_creation_input_tokens":0}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cache=500r/0w"* ]]
}

@test "result event with non-zero cache_creation tokens: cache= shown in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":200}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cache=0r/200w"* ]]
}

@test "result event with zero cache tokens: no cache= in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"cache="* ]]
}

# --- Web tool counts ---

@test "result event with non-zero web_search_requests: web= shown in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10,"server_tool_use":{"web_search_requests":3,"web_fetch_requests":0}}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"web=3s/0f"* ]]
}

@test "result event with non-zero web_fetch_requests: web= shown in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":2}}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"web=0s/2f"* ]]
}

@test "result event with zero web tool requests: no web= in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0}}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"web="* ]]
}

# --- Permission denials ---

@test "result event with non-empty permission_denials: denials= shown in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10},"permission_denials":["Bash","Read"]}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"denials=2"* ]]
}

@test "result event with empty permission_denials: no denials= in summary" {
  local event='{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10},"permission_denials":[]}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" != *"denials="* ]]
}

# --- system:init writes model to log_file ---

@test "system init event: model written to log_file" {
  local event='{"type":"system","subtype":"init","model":"claude-sonnet-4-6"}'
  echo "$event" | process_stream_json "$_log" "$_raw"
  grep -q "model=claude-sonnet-4-6" "$_log"
}
