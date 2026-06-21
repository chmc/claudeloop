#!/usr/bin/env bash
# bats file_tags=nudge

# Tests for lib/nudge.sh — nudge_file_path, read_nudge, clear_nudge, prompt_nudge_text

setup() {
  export _NUDGE_DISABLED=1
  . "${BATS_TEST_DIRNAME}/../lib/nudge.sh"
  export TEST_DIR="$BATS_TEST_TMPDIR"
  mkdir -p "$TEST_DIR/.claudeloop"
  cd "$TEST_DIR"
}

teardown() { :; }

# --- nudge_file_path ---

@test "nudge_file_path: integer phase" {
  run nudge_file_path "3"
  [ "$status" -eq 0 ]
  [ "$output" = ".claudeloop/nudge-phase-3.md" ]
}

@test "nudge_file_path: decimal phase" {
  run nudge_file_path "2.5"
  [ "$status" -eq 0 ]
  [ "$output" = ".claudeloop/nudge-phase-2.5.md" ]
}

# --- read_nudge ---

@test "read_nudge: empty when file does not exist" {
  run read_nudge "3"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "read_nudge: returns content when file exists" {
  printf '%s\n' "try a different approach" > "$TEST_DIR/.claudeloop/nudge-phase-3.md"
  run read_nudge "3"
  [ "$status" -eq 0 ]
  [ "$output" = "try a different approach" ]
}

@test "read_nudge: empty when file is empty" {
  : > "$TEST_DIR/.claudeloop/nudge-phase-3.md"
  run read_nudge "3"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- clear_nudge ---

@test "clear_nudge: removes file" {
  printf '%s\n' "some guidance" > "$TEST_DIR/.claudeloop/nudge-phase-3.md"
  clear_nudge "3"
  [ ! -f "$TEST_DIR/.claudeloop/nudge-phase-3.md" ]
}

@test "clear_nudge: no-op when file does not exist" {
  run clear_nudge "99"
  [ "$status" -eq 0 ]
}

# --- nudge replaces previous (no stacking) ---

@test "nudge replaces previous nudge" {
  printf '%s\n' "first guidance" > "$TEST_DIR/.claudeloop/nudge-phase-3.md"
  printf '%s\n' "second guidance" > "$TEST_DIR/.claudeloop/nudge-phase-3.md"
  run read_nudge "3"
  [ "$output" = "second guidance" ]
}

# --- adversarial content ---

@test "read_nudge: adversarial content returned as plain text without expansion" {
  printf '%s\n' '$(rm -rf /)' > "$TEST_DIR/.claudeloop/nudge-phase-1.md"
  run read_nudge "1"
  [ "$status" -eq 0 ]
  [ "$output" = '$(rm -rf /)' ]
}

@test "read_nudge: backtick content not expanded" {
  printf '%s\n' '`id`' > "$TEST_DIR/.claudeloop/nudge-phase-1.md"
  run read_nudge "1"
  [ "$status" -eq 0 ]
  [ "$output" = '`id`' ]
}

@test "read_nudge: dollar-HOME not expanded" {
  printf '%s\n' '$HOME' > "$TEST_DIR/.claudeloop/nudge-phase-1.md"
  run read_nudge "1"
  [ "$status" -eq 0 ]
  [ "$output" = '$HOME' ]
}
