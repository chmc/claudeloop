#!/usr/bin/env bash
# bats file_tags=config

# Tests for lib/wizard.sh — bool_yn, run_config_wizard

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/config.sh"
  source "${BATS_TEST_DIRNAME}/../lib/wizard.sh"
  _tmpdir="$BATS_TEST_TMPDIR"
  MAX_RETRIES=10
  SKIP_PERMISSIONS=false
  VERIFY_PHASES=false
  _CLI_MAX_RETRIES=""
  _CLI_SKIP_PERMISSIONS=""
  _CLI_VERIFY_PHASES=""
  print_success() { :; }
  print_warning() { :; }
  export -f print_success
  export -f print_warning
}

teardown() { :; }

# --- bool_yn() ---

@test "bool_yn: true returns y" {
  run bool_yn "true"
  [ "$status" -eq 0 ]
  [ "$output" = "y" ]
}

@test "bool_yn: false returns n" {
  run bool_yn "false"
  [ "$status" -eq 0 ]
  [ "$output" = "n" ]
}

@test "bool_yn: empty string returns n" {
  run bool_yn ""
  [ "$status" -eq 0 ]
  [ "$output" = "n" ]
}

@test "bool_yn: arbitrary string returns n" {
  run bool_yn "anything_else"
  [ "$status" -eq 0 ]
  [ "$output" = "n" ]
}

# --- run_config_wizard() ---

@test "run_config_wizard: all defaults (Enter×3) leaves globals unchanged" {
  printf '\n\n\n' > "$_tmpdir/input"
  run_config_wizard < "$_tmpdir/input" > /dev/null
  [ "$MAX_RETRIES" = "10" ]
  [ "$SKIP_PERMISSIONS" = "false" ]
  [ "$VERIFY_PHASES" = "false" ]
}

@test "run_config_wizard: custom MAX_RETRIES updates global" {
  printf '5\n\n\n' > "$_tmpdir/input"
  run_config_wizard < "$_tmpdir/input" > /dev/null
  [ "$MAX_RETRIES" = "5" ]
}

@test "run_config_wizard: _CLI_MAX_RETRIES set skips prompt and shows message" {
  _CLI_MAX_RETRIES=1
  MAX_RETRIES=20
  output=$(printf '\n\n' | run_config_wizard)
  [ "$MAX_RETRIES" = "20" ]
  [[ "$output" == *"using --max-retries"* ]]
}
