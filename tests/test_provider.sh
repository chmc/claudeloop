#!/usr/bin/env bash
# bats file_tags=provider

setup() {
  SCRIPT_DIR_PROVIDER="${BATS_TEST_DIRNAME}/../lib"
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
