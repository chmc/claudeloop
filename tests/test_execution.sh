#!/usr/bin/env bash
# bats file_tags=execution

# Tests for lib/execution.sh — build_default_prompt, rotate_phase_log, capture_git_context

setup() {
  # Stub log_verbose before sourcing (called at definition-time? no, only at call-time)
  log_verbose() { :; }
  log_ts() { :; }
  VERBOSE_MODE=false
  source "${BATS_TEST_DIRNAME}/../lib/execution.sh"
  _tmpdir="$(mktemp -d)"
}

teardown() { rm -rf "$_tmpdir"; }

# --- build_default_prompt() ---

@test "build_default_prompt: output contains phase number, title, description" {
  run build_default_prompt "3" "Setup DB" "Create the database schema" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase 3"* ]]
  [[ "$output" == *"Setup DB"* ]]
  [[ "$output" == *"Create the database schema"* ]]
}

@test "build_default_prompt: output contains git context when provided" {
  run build_default_prompt "1" "Init" "Initialize project" "Recent commits: abc123"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recent commits: abc123"* ]]
}

@test "build_default_prompt: git context area empty when arg is empty" {
  run build_default_prompt "1" "Init" "Initialize project" ""
  [ "$status" -eq 0 ]
  # Should not contain git-specific headers
  [[ "$output" != *"Recent commits"* ]]
  [[ "$output" != *"Uncommitted changes"* ]]
}

# --- rotate_phase_log() ---

@test "rotate_phase_log: no rotation when response section <= 500 lines" {
  local logfile="$_tmpdir/phase-1.log"
  {
    printf '=== PROMPT ===\nsome prompt\n=== RESPONSE ===\n'
    for i in $(seq 1 500); do printf 'line %d\n' "$i"; done
  } > "$logfile"
  local before_md5
  before_md5=$(md5 -q "$logfile" 2>/dev/null || md5sum "$logfile" | cut -d' ' -f1)
  rotate_phase_log "$logfile" "1"
  local after_md5
  after_md5=$(md5 -q "$logfile" 2>/dev/null || md5sum "$logfile" | cut -d' ' -f1)
  [ "$before_md5" = "$after_md5" ]
}

@test "rotate_phase_log: rotates to 500 response lines when over limit; header preserved" {
  local logfile="$_tmpdir/phase-2.log"
  {
    printf '=== PROMPT ===\nsome prompt\n=== RESPONSE ===\n'
    for i in $(seq 1 600); do printf 'line %d\n' "$i"; done
  } > "$logfile"
  rotate_phase_log "$logfile" "2"
  # Header lines (prompt + response marker) should be preserved
  grep -q '=== PROMPT ===' "$logfile"
  grep -q '=== RESPONSE ===' "$logfile"
  # Response section should be 500 lines (last 500 of original 600)
  local response_start total
  response_start=$(grep -n '^=== RESPONSE ===$' "$logfile" | head -1 | cut -d: -f1)
  total=$(wc -l < "$logfile")
  local response_lines=$((total - response_start))
  [ "$response_lines" -eq 500 ]
}

@test "rotate_phase_log: old-format log no rotation when <= 500 lines" {
  local logfile="$_tmpdir/phase-3.log"
  for i in $(seq 1 500); do printf 'line %d\n' "$i"; done > "$logfile"
  local before_md5
  before_md5=$(md5 -q "$logfile" 2>/dev/null || md5sum "$logfile" | cut -d' ' -f1)
  rotate_phase_log "$logfile" "3"
  local after_md5
  after_md5=$(md5 -q "$logfile" 2>/dev/null || md5sum "$logfile" | cut -d' ' -f1)
  [ "$before_md5" = "$after_md5" ]
}

@test "rotate_phase_log: old-format log rotates when > 500 lines" {
  local logfile="$_tmpdir/phase-4.log"
  for i in $(seq 1 600); do printf 'line %d\n' "$i"; done > "$logfile"
  rotate_phase_log "$logfile" "4"
  local line_count
  line_count=$(wc -l < "$logfile")
  [ "$line_count" -eq 500 ]
}

# --- capture_git_context() ---

@test "capture_git_context: returns string with Recent commits when commits exist" {
  cd "$_tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  printf 'hello\n' > file.txt
  git add file.txt
  git commit -q -m "initial commit"
  local result
  result=$(capture_git_context) || true
  [[ "$result" == *"Recent commits"* ]]
}

@test "capture_git_context: returns string with Uncommitted changes when dirty tree" {
  cd "$_tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  printf 'hello\n' > file.txt
  git add file.txt
  git commit -q -m "initial commit"
  printf 'world\n' >> file.txt
  run capture_git_context
  [ "$status" -eq 0 ]
  [[ "$output" == *"Uncommitted changes"* ]]
}

# --- raw log reset in execute_phase ---

@test "execute_phase: raw log is truncated before run_claude_pipeline" {
  # Verify that the code truncates raw_log before running the pipeline.
  # We check this by inspecting the source within execute_phase function.
  local src="${BATS_TEST_DIRNAME}/../lib/execution.sh"
  # Find line numbers within execute_phase (after line 324 where function starts)
  local truncate_line pipeline_line
  truncate_line=$(grep -n ': > "$raw_log"' "$src" | tail -1 | cut -d: -f1)
  pipeline_line=$(grep -n 'run_claude_pipeline "$prompt"' "$src" | head -1 | cut -d: -f1)
  [ -n "$truncate_line" ]
  [ -n "$pipeline_line" ]
  # Truncation must come before the pipeline call
  [ "$truncate_line" -lt "$pipeline_line" ]
}

@test "capture_git_context: returns empty when in dir with no git repo" {
  cd "$_tmpdir"
  run capture_git_context
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- update_fail_reason() ---

@test "update_fail_reason: same reason increments consec" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  phase_set FAIL_REASON 1 "trapped_tool_calls"
  phase_set CONSEC_FAIL 1 "2"
  update_fail_reason 1 "trapped_tool_calls"
  [ "$(get_phase_fail_reason 1)" = "trapped_tool_calls" ]
  [ "$(get_phase_consec_fail 1)" = "3" ]
}

@test "update_fail_reason: different reason resets consec to 1" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  phase_set FAIL_REASON 1 "trapped_tool_calls"
  phase_set CONSEC_FAIL 1 "3"
  update_fail_reason 1 "no_write_actions"
  [ "$(get_phase_fail_reason 1)" = "no_write_actions" ]
  [ "$(get_phase_consec_fail 1)" = "1" ]
}

@test "update_fail_reason: first failure sets consec to 1" {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  update_fail_reason 1 "empty_log"
  [ "$(get_phase_fail_reason 1)" = "empty_log" ]
  [ "$(get_phase_consec_fail 1)" = "1" ]
}

# --- run_claude_pipeline: exit code wait loop ---

@test "run_claude_pipeline: waits for exit code file when sentinel fires before exit_tmp written" {
  # Verify source code has the wait loop for $_exit_tmp after sentinel detection
  local src="${BATS_TEST_DIRNAME}/../lib/execution.sh"
  # The wait loop should exist between the sentinel loop and the kill command
  local sentinel_done_line kill_line wait_loop_line
  sentinel_done_line=$(grep -n 'while \[ ! -f "$_sentinel" \]' "$src" | head -1 | cut -d: -f1)
  kill_line=$(grep -n 'kill -TERM -- "-\$CURRENT_PIPELINE_PGID"' "$src" | head -1 | cut -d: -f1)
  wait_loop_line=$(grep -n 'while \[ ! -s "$_exit_tmp" \]' "$src" | head -1 | cut -d: -f1)
  [ -n "$wait_loop_line" ]
  # Wait loop must be after sentinel loop and before kill
  [ "$wait_loop_line" -gt "$sentinel_done_line" ]
  [ "$wait_loop_line" -lt "$kill_line" ]
}
