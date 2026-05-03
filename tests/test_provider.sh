#!/usr/bin/env bash
# bats file_tags=provider

setup() {
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/.."
  . "${BATS_TEST_DIRNAME}/../lib/provider.sh"
}

@test "provider_detect: returns claude" {
  run provider_detect
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

@test "provider_cli: returns claude" {
  run provider_cli
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

@test "provider_exec_args: returns exact execution flags" {
  run provider_exec_args
  [ "$status" -eq 0 ]
  [ "$output" = "--input-format stream-json --output-format stream-json --permission-prompt-tool stdio --verbose --include-partial-messages" ]
}

@test "provider_print_args: returns exact print flags" {
  run provider_print_args
  [ "$status" -eq 0 ]
  [ "$output" = "--print --output-format=stream-json --verbose --include-partial-messages" ]
}

@test "provider_write_tool_pattern: returns pipe-separated tool names" {
  run provider_write_tool_pattern
  [ "$status" -eq 0 ]
  [ "$output" = "Edit|Write|NotebookEdit|Agent" ]
}

@test "provider_verdict_pass_keyword: returns VERIFICATION_PASSED" {
  run provider_verdict_pass_keyword
  [ "$status" -eq 0 ]
  [ "$output" = "VERIFICATION_PASSED" ]
}

@test "provider_verdict_fail_keyword: returns VERIFICATION_FAILED" {
  run provider_verdict_fail_keyword
  [ "$status" -eq 0 ]
  [ "$output" = "VERIFICATION_FAILED" ]
}

@test "provider_permission_protocol: returns stdio for Claude" {
  run provider_permission_protocol
  [ "$status" -eq 0 ]
  [ "$output" = "stdio" ]
}

# Tests for PROVIDER config support (Issue #34)

@test "provider_detect: respects PROVIDER=claude" {
  PROVIDER=claude run provider_detect
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

@test "provider_detect: returns opencode when PROVIDER=opencode" {
  PROVIDER=opencode run provider_detect
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
}

@test "provider_detect: fails for unknown provider" {
  PROVIDER=unknown run provider_detect
  [ "$status" -eq 1 ]
  [[ "$output" == *"not yet supported"* ]]
}

@test "provider_detect: empty PROVIDER defaults to claude" {
  PROVIDER="" run provider_detect
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

# Tests for OpenCode provider (Issue #35)

setup_opencode() {
  PROVIDER=opencode
  . "${BATS_TEST_DIRNAME}/../lib/provider.sh"
}

@test "provider_cli: returns opencode when PROVIDER=opencode" {
  setup_opencode
  run provider_cli
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
}

@test "provider_exec_args: returns OpenCode flags when PROVIDER=opencode" {
  setup_opencode
  run provider_exec_args
  [ "$status" -eq 0 ]
  [ "$output" = "--format json --stream" ]
}

@test "provider_print_args: returns OpenCode flags when PROVIDER=opencode" {
  setup_opencode
  run provider_print_args
  [ "$status" -eq 0 ]
  [ "$output" = "--format json" ]
}

@test "provider_permission_protocol: returns http for OpenCode" {
  setup_opencode
  run provider_permission_protocol
  [ "$status" -eq 0 ]
  [ "$output" = "http" ]
}

@test "provider_normalize_events: passes through for Claude" {
  output=$(echo "test line" | provider_normalize_events)
  [ "$output" = "test line" ]
}

@test "provider_normalize_events: normalizes OpenCode events" {
  setup_opencode
  input='{"type":"session.created","model":"gpt-4"}'
  output=$(echo "$input" | provider_normalize_events)
  [[ "$output" == *'"type":"system"'* ]]
  [[ "$output" == *'"subtype":"init"'* ]]
}
