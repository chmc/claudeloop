#!/usr/bin/env bats
# Tests for fake_opencode CLI simulator

setup() {
  FAKE_OPENCODE_DIR="$(mktemp -d)"
  export FAKE_OPENCODE_DIR
}

teardown() {
  rm -rf "$FAKE_OPENCODE_DIR"
}

@test "fake_opencode: requires FAKE_OPENCODE_DIR" {
  unset FAKE_OPENCODE_DIR
  run ./tests/fake_opencode
  [ "$status" -ne 0 ]
  [[ "$output" =~ "FAKE_OPENCODE_DIR must be set" ]]
}

@test "fake_opencode: --version returns fake version" {
  run ./tests/fake_opencode --version
  [ "$status" -eq 0 ]
  [ "$output" = "fake-opencode 0.0.0" ]
}

@test "fake_opencode: success scenario emits session.created and session.idle" {
  echo "success" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"type":"session.created"' ]]
  [[ "$output" =~ '"type":"session.idle"' ]]
}

@test "fake_opencode: success scenario emits Edit tool" {
  echo "success" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"name":"Edit"' ]]
  [[ "$output" =~ '"state":"completed"' ]]
}

@test "fake_opencode: success_multi scenario emits Read, Edit, Bash tools" {
  echo "success_multi" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"name":"Read"' ]]
  [[ "$output" =~ '"name":"Edit"' ]]
  [[ "$output" =~ '"name":"Bash"' ]]
}

@test "fake_opencode: failure scenario exits 1" {
  echo "failure" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Error encountered" ]]
}

@test "fake_opencode: verify_pass emits VERIFICATION_PASSED" {
  echo "verify_pass" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VERIFICATION_PASSED" ]]
}

@test "fake_opencode: verify_fail emits VERIFICATION_FAILED" {
  echo "verify_fail" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VERIFICATION_FAILED" ]]
}

@test "fake_opencode: verify_skip emits VERIFICATION_PASSED without tools" {
  echo "verify_skip" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VERIFICATION_PASSED" ]]
  [[ ! "$output" =~ '"callID"' ]]
}

@test "fake_opencode: quota_error scenario" {
  echo "quota_error" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 1 ]
  [[ "$output" =~ "rate limit exceeded" ]]
}

@test "fake_opencode: permission_request emits permission events" {
  echo "permission_request" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"type":"permission.requested"' ]]
  [[ "$output" =~ '"type":"permission.granted"' ]]
}

@test "fake_opencode: read_only scenario has no write tools" {
  echo "read_only" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"name":"Read"' ]]
  [[ "$output" =~ '"name":"Grep"' ]]
  [[ ! "$output" =~ '"name":"Edit"' ]]
  [[ ! "$output" =~ '"name":"Write"' ]]
}

@test "fake_opencode: empty scenario produces no output" {
  echo "empty" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fake_opencode: custom scenario reads custom_output" {
  echo "custom" > "$FAKE_OPENCODE_DIR/scenario"
  printf '{"type":"session.created","sessionId":"custom"}\n{"type":"session.idle","sessionId":"custom"}\n' > "$FAKE_OPENCODE_DIR/custom_output"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"sessionId":"custom"' ]]
}

@test "fake_opencode: per-call scenario selection" {
  printf 'success\nfailure\n' > "$FAKE_OPENCODE_DIR/scenarios"
  echo "call1" | ./tests/fake_opencode > /dev/null
  run sh -c 'echo "call2" | ./tests/fake_opencode'
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Error encountered" ]]
}

@test "fake_opencode: call_count increments" {
  echo "success" > "$FAKE_OPENCODE_DIR/scenario"
  echo "call1" | ./tests/fake_opencode > /dev/null
  echo "call2" | ./tests/fake_opencode > /dev/null
  [ "$(cat "$FAKE_OPENCODE_DIR/call_count")" = "2" ]
}

@test "fake_opencode: captures prompts" {
  echo "success" > "$FAKE_OPENCODE_DIR/scenario"
  echo "my test prompt" | ./tests/fake_opencode > /dev/null
  [ -f "$FAKE_OPENCODE_DIR/prompts/prompt_1" ]
  grep -q "my test prompt" "$FAKE_OPENCODE_DIR/prompts/prompt_1"
}

@test "fake_opencode: captures args" {
  echo "success" > "$FAKE_OPENCODE_DIR/scenario"
  echo "test" | ./tests/fake_opencode --format json --stream > /dev/null
  [ -f "$FAKE_OPENCODE_DIR/args/args_1" ]
  grep -q "\-\-format" "$FAKE_OPENCODE_DIR/args/args_1"
}

@test "fake_opencode: exit_codes file overrides default" {
  echo "success" > "$FAKE_OPENCODE_DIR/scenario"
  echo "42" > "$FAKE_OPENCODE_DIR/exit_codes"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 42 ]
}

@test "fake_opencode: error_realistic has tool errors" {
  echo "error_realistic" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 1 ]
  [[ "$output" =~ '"state":"error"' ]]
  [[ "$output" =~ '"state":"failed"' ]]
}

@test "fake_opencode: tool state machine (pending -> running -> completed)" {
  echo "success_multi" > "$FAKE_OPENCODE_DIR/scenario"
  run sh -c 'echo "test" | ./tests/fake_opencode'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"state":"pending"' ]]
  [[ "$output" =~ '"state":"running"' ]]
  [[ "$output" =~ '"state":"completed"' ]]
}

@test "fake_opencode: normalizes through opencode adapter" {
  echo "success" > "$FAKE_OPENCODE_DIR/scenario"
  . ./lib/adapters/opencode.sh
  output=$(echo "test" | ./tests/fake_opencode | _opencode_normalize_events)
  [[ "$output" =~ '"type":"system"' ]]
  [[ "$output" =~ '"type":"tool_use"' ]]
  [[ "$output" =~ '"type":"tool_result"' ]]
  [[ "$output" =~ '"type":"result"' ]]
}
