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
  local event='{"type":"result","cost_usd":0.0041,"duration_ms":18300,"num_turns":4,"usage":{"input_tokens":4200,"output_tokens":380}}'
  run_processor "$event" > /dev/null 2>&1
  grep -q '\[Session:' "$_log"
}

@test "result event: summary printed to stderr" {
  local event='{"type":"result","cost_usd":0.0041,"duration_ms":18300,"num_turns":4,"usage":{"input_tokens":4200,"output_tokens":380}}'
  run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Session:"* ]]
}

@test "result event: contains cost, duration, turns, tokens" {
  local event='{"type":"result","cost_usd":0.0041,"duration_ms":18300,"num_turns":4,"usage":{"input_tokens":4200,"output_tokens":380}}'
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

@test "empty input: no output, no crash" {
  run bash -c "echo -n | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- newline separation (Change 3) ---

@test "tool_use after text without trailing newline: newline inserted in stdout" {
  local text1='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hello"}]}}'
  local tool='{"type":"tool_use","name":"Bash","input":{"command":"ls"}}'
  local text2='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"world\n"}]}}'
  run bash -c "printf '%s\n%s\n%s\n' '$text1' '$tool' '$text2' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'hello\nworld'* ]]
}

# --- activity dots (Change 4) ---

@test "assistant event with empty text: dot printed to stdout" {
  local event='{"type":"assistant","message":{"role":"assistant","content":[]}}'
  run run_processor "$event"
  [ "$status" -eq 0 ]
  [[ "$output" == "." ]]
}

@test "unknown event type: dot printed to stdout" {
  local event='{"type":"unknown_event"}'
  run run_processor "$event"
  [ "$status" -eq 0 ]
  [[ "$output" == "." ]]
}

@test "consecutive silent events: only one dot printed" {
  local e1='{"type":"assistant","message":{"role":"assistant","content":[]}}'
  local e2='{"type":"unknown_event"}'
  run bash -c "printf '%s\n%s\n' '$e1' '$e2' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == "." ]]
}

@test "dot resets after visible text: second silent period gets new dot" {
  local silent='{"type":"unknown_event"}'
  local text='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi\n"}]}}'
  run bash -c "printf '%s\n%s\n%s\n' '$silent' '$text' '$silent' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"."*"hi"*"."* ]]
}
