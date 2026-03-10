#!/usr/bin/env bash
# bats file_tags=config

# Tests for lib/config.sh — bool_yn, load_config edge cases, run_config_wizard

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/config.sh"
  _tmpdir="$(mktemp -d)"
  MAX_RETRIES=10
  SKIP_PERMISSIONS=false
  VERIFY_PHASES=false
  _CLI_MAX_RETRIES=""
  _CLI_SKIP_PERMISSIONS=""
  _CLI_VERIFY_PHASES=""
}

teardown() { rm -rf "$_tmpdir"; }

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

# --- load_config() edge cases ---

@test "load_config: returns 0 when conf file missing" {
  cd "$_tmpdir"
  run load_config
  [ "$status" -eq 0 ]
}

@test "load_config: skips comment lines" {
  mkdir -p "$_tmpdir/.claudeloop"
  printf '# This is a comment\nMAX_RETRIES=5\n' > "$_tmpdir/.claudeloop/.claudeloop.conf"
  cd "$_tmpdir"
  load_config
  [ "$MAX_RETRIES" = "5" ]
}

@test "load_config: skips blank lines" {
  mkdir -p "$_tmpdir/.claudeloop"
  printf '\n\nMAX_RETRIES=7\n\n' > "$_tmpdir/.claudeloop/.claudeloop.conf"
  cd "$_tmpdir"
  load_config
  [ "$MAX_RETRIES" = "7" ]
}

@test "load_config: ignores unknown keys" {
  mkdir -p "$_tmpdir/.claudeloop"
  printf 'UNKNOWN_KEY=some_value\nMAX_RETRIES=3\n' > "$_tmpdir/.claudeloop/.claudeloop.conf"
  cd "$_tmpdir"
  load_config
  [ "$MAX_RETRIES" = "3" ]
  # UNKNOWN_KEY should not be set as a global
  [ -z "${UNKNOWN_KEY:-}" ]
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
