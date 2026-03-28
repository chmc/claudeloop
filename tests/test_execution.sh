#!/usr/bin/env bash
# bats file_tags=execution

# Tests for lib/execution.sh and lib/prompt.sh — build_default_prompt, rotate_phase_log, capture_git_context

setup() {
  # Stub log_verbose before sourcing (called at definition-time? no, only at call-time)
  log_verbose() { :; }
  log_ts() { :; }
  VERBOSE_MODE=false
  source "${BATS_TEST_DIRNAME}/../lib/prompt.sh"
  source "${BATS_TEST_DIRNAME}/../lib/execution.sh"
  _tmpdir="$BATS_TEST_TMPDIR"
}

teardown() { :; }

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

@test "execute_phase: archives per-attempt raw.json after pipeline" {
  # Verify that execute_phase copies raw_log to attempt-specific file after pipeline
  local src="${BATS_TEST_DIRNAME}/../lib/execution.sh"
  local pipeline_line rotate_line archive_line
  pipeline_line=$(grep -n 'run_claude_pipeline "$prompt"' "$src" | head -1 | cut -d: -f1)
  rotate_line=$(grep -n 'rotate_phase_log "$log_file"' "$src" | head -1 | cut -d: -f1)
  archive_line=$(grep -n 'cp "$raw_log" ".claudeloop/logs/phase-${phase_num}.attempt-${attempt}.raw.json"' "$src" | head -1 | cut -d: -f1)
  [ -n "$archive_line" ]
  # Archive must be after pipeline and before rotation
  [ "$archive_line" -gt "$pipeline_line" ]
  [ "$archive_line" -lt "$rotate_line" ]
}

@test "capture_git_context: returns empty when in dir with no git repo" {
  cd "$_tmpdir"
  run capture_git_context
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- build_default_prompt: signal file instruction ---

@test "build_default_prompt: includes signal file instruction" {
  run build_default_prompt "5" "Review" "Check everything works" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"signals/phase-"* ]]
  [[ "$output" == *"no code changes"* ]]
}

# --- evaluate_phase_result: signal file tests ---

# Helper to set up stubs needed by evaluate_phase_result
_setup_epr_stubs() {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  PROGRESS_FILE="$_tmpdir/progress"
  PLAN_FILE="$_tmpdir/plan"
  CURRENT_PHASE=""
  REFACTOR_PHASES="false"
  # Stub functions called by evaluate_phase_result
  update_phase_status() { phase_set STATUS "$1" "$2"; }
  write_progress() { :; }
  print_error() { :; }
  print_warning() { :; }
  print_success() { :; }
  auto_commit_changes() { :; }
  run_refactor_if_needed() { :; }
  run_adaptive_verification() { return 0; }
}

@test "evaluate_phase_result: succeeds with signal file + successful session despite no write actions" {
  _setup_epr_stubs
  local log="$_tmpdir/phase-1.log"
  local raw="$_tmpdir/phase-1.raw.json"
  # Log with successful session but no write actions
  printf '=== EXECUTION START phase=1 attempt=1 ===\n' > "$log"
  printf '=== RESPONSE ===\nAll checks passed.\n' >> "$log"
  printf '[Session: duration=30.0s turns=15 tokens=5000in/2000out]\n' >> "$log"
  # Raw log with only read actions (no writes)
  printf '=== EXECUTION START phase=1 attempt=1 ===\n' > "$raw"
  printf '{"type":"tool_use","name":"Read","input":{}}\n' >> "$raw"
  # Create signal file
  mkdir -p .claudeloop/signals
  printf 'Phase already implemented. Tests pass.\n' > ".claudeloop/signals/phase-1.md"
  phase_set ATTEMPTS 1 "1"
  run evaluate_phase_result 1 0 1 "$log" "$raw"
  [ "$status" -eq 0 ]
  rm -rf .claudeloop/signals
}

@test "evaluate_phase_result: fails with signal file but no successful session" {
  _setup_epr_stubs
  local log="$_tmpdir/phase-2.log"
  local raw="$_tmpdir/phase-2.raw.json"
  # Log with NO successful session (turns=0)
  printf '=== EXECUTION START phase=2 attempt=1 ===\n' > "$log"
  printf '[Session: duration=0.0s turns=0 tokens=0in/0out]\n' >> "$log"
  printf '=== RESPONSE ===\nDone.\n' >> "$log"
  # Raw log with no write actions
  printf '=== EXECUTION START phase=2 attempt=1 ===\n' > "$raw"
  printf '{"type":"tool_use","name":"Read","input":{}}\n' >> "$raw"
  # Create signal file
  mkdir -p .claudeloop/signals
  printf 'No changes needed.\n' > ".claudeloop/signals/phase-2.md"
  phase_set ATTEMPTS 2 "1"
  run evaluate_phase_result 2 0 1 "$log" "$raw"
  [ "$status" -eq 1 ]
  rm -rf .claudeloop/signals
}

@test "evaluate_phase_result: still fails without write actions or signal file" {
  _setup_epr_stubs
  local log="$_tmpdir/phase-3.log"
  local raw="$_tmpdir/phase-3.raw.json"
  # Log with successful session
  printf '=== EXECUTION START phase=3 attempt=1 ===\n' > "$log"
  printf '[Session: duration=30.0s turns=15 tokens=5000in/2000out]\n' >> "$log"
  printf '=== RESPONSE ===\nAll done.\n' >> "$log"
  # Raw log with no write actions
  printf '=== EXECUTION START phase=3 attempt=1 ===\n' > "$raw"
  printf '{"type":"tool_use","name":"Read","input":{}}\n' >> "$raw"
  # NO signal file
  rm -f ".claudeloop/signals/phase-3.md"
  phase_set ATTEMPTS 3 "1"
  run evaluate_phase_result 3 0 1 "$log" "$raw"
  [ "$status" -eq 1 ]
}

@test "evaluate_phase_result: succeeds with signal file + successful session even when Write tool used" {
  _setup_epr_stubs
  # Spy: detect if run_adaptive_verification is called
  run_adaptive_verification() { printf 'called' > "$_tmpdir/rav_spy"; return 0; }
  local log="$_tmpdir/phase-6.log"
  local raw="$_tmpdir/phase-6.raw.json"
  # Log with successful session
  printf '=== EXECUTION START phase=6 attempt=1 ===\n' > "$log"
  printf '=== RESPONSE ===\nNo code changes needed.\n' >> "$log"
  printf '[Session: duration=30.0s turns=10 tokens=3000in/1500out]\n' >> "$log"
  # Raw log WITH Write tool call (signal file creation triggers has_write_actions)
  printf '=== EXECUTION START phase=6 attempt=1 ===\n' > "$raw"
  printf '{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_01","name":"Write","input":{}}}}\n' >> "$raw"
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_01","name":"Write","input":{"file_path":".claudeloop/signals/phase-6.md","content":"No changes needed"}}]}}\n' >> "$raw"
  # Create signal file
  mkdir -p .claudeloop/signals
  printf 'No changes needed.\n' > ".claudeloop/signals/phase-6.md"
  phase_set ATTEMPTS 6 "1"
  run evaluate_phase_result 6 0 1 "$log" "$raw"
  [ "$status" -eq 0 ]
  # Verify run_adaptive_verification was NOT called (signal file skips verification)
  [ ! -f "$_tmpdir/rav_spy" ]
  rm -rf .claudeloop/signals
}

@test "evaluate_phase_result: succeeds with signal file + successful session on non-zero exit" {
  _setup_epr_stubs
  # Spy: detect if run_adaptive_verification is called
  run_adaptive_verification() { printf 'called' > "$_tmpdir/rav_spy"; return 0; }
  local log="$_tmpdir/phase-7.log"
  local raw="$_tmpdir/phase-7.raw.json"
  # Log with successful session
  printf '=== EXECUTION START phase=7 attempt=1 ===\n' > "$log"
  printf '=== RESPONSE ===\nNo code changes needed.\n' >> "$log"
  printf '[Session: duration=25.0s turns=8 tokens=2000in/1000out]\n' >> "$log"
  # Raw log with no write actions
  printf '=== EXECUTION START phase=7 attempt=1 ===\n' > "$raw"
  printf '{"type":"tool_use","name":"Read","input":{}}\n' >> "$raw"
  # Create signal file
  mkdir -p .claudeloop/signals
  printf 'Phase verified manually.\n' > ".claudeloop/signals/phase-7.md"
  phase_set ATTEMPTS 7 "1"
  # Non-zero exit (e.g., Claude crashed after writing signal file)
  run evaluate_phase_result 7 1 1 "$log" "$raw"
  [ "$status" -eq 0 ]
  # Verify run_adaptive_verification was NOT called
  [ ! -f "$_tmpdir/rav_spy" ]
  rm -rf .claudeloop/signals
}

@test "evaluate_phase_result: fails on non-zero exit with turns=1 tokens=0 (API 500 error)" {
  _setup_epr_stubs
  local log="$_tmpdir/phase-4.log"
  local raw="$_tmpdir/phase-4.raw.json"
  # Log with API 500 error session: turns=1 but zero output tokens
  printf '=== EXECUTION START phase=4 attempt=1 ===\n' > "$log"
  printf '=== RESPONSE ===\n' >> "$log"
  printf 'API Error: 500 {"type":"error","error":{"type":"api_error","message":"Internal server error"}}\n' >> "$log"
  printf '[Session: duration=33.8s turns=1 tokens=0in/0out]\n' >> "$log"
  # Raw log with no meaningful events
  printf '=== EXECUTION START phase=4 attempt=1 ===\n' > "$raw"
  printf '{"type":"error","error":{"type":"api_error","message":"Internal server error"}}\n' >> "$raw"
  phase_set ATTEMPTS 4 "1"
  run evaluate_phase_result 4 1 1 "$log" "$raw"
  [ "$status" -eq 1 ]
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

# --- run_claude_pipeline: sentinel poll timeout ---

@test "run_claude_pipeline: sentinel poll has timeout guard" {
  local src="${BATS_TEST_DIRNAME}/../lib/execution.sh"
  # Verify the sentinel loop has a break condition based on elapsed time
  grep -q '_sentinel_polls' "$src"
  grep -q '_SENTINEL_MAX_WAIT' "$src"
  # The timeout break must be inside the sentinel while loop
  local sentinel_line break_line
  sentinel_line=$(grep -n 'while \[ ! -f "$_sentinel" \]' "$src" | head -1 | cut -d: -f1)
  break_line=$(grep -n '_sentinel_polls.*_sentinel_interval.*_sentinel_max' "$src" | head -1 | cut -d: -f1)
  [ -n "$break_line" ]
  [ "$break_line" -gt "$sentinel_line" ]
}

@test "run_claude_pipeline: timer creates sentinel even when kill fails" {
  local src="${BATS_TEST_DIRNAME}/../lib/execution.sh"
  # The timer subshell must use '; : > "$_sentinel"' (unconditional) not '&& : > "$_sentinel"'
  # This ensures sentinel is created even when kill fails (process already dead)
  local timer_line
  timer_line=$(grep -n 'sleep.*MAX_PHASE_TIME.*kill.*sentinel' "$src" | head -1)
  [ -n "$timer_line" ]
  # Must NOT use '&& : >' before sentinel — must use '; : >'
  ! grep -q 'kill.*2>/dev/null && : > "\$_sentinel"' "$src"
}

# --- execute_phase: pre-exec SHA rollback ---

@test "execute_phase: captures pre-exec SHA and rolls back on failure with write actions" {
  local src="${BATS_TEST_DIRNAME}/../lib/execution.sh"
  # Verify pre-exec SHA capture exists before run_claude_pipeline
  grep -q '_pre_exec_sha' "$src"
  # Verify rollback logic exists (git checkout to pre-exec SHA)
  grep -q 'git checkout "$_pre_exec_sha"' "$src"
  # Verify rollback is gated on has_write_actions
  grep -q 'has_write_actions.*raw_log' "$src"
  # Verify rollback is inside the failure path (after evaluate_phase_result)
  local eval_line rollback_line
  eval_line=$(grep -n 'evaluate_phase_result' "$src" | tail -1 | cut -d: -f1)
  rollback_line=$(grep -n 'rolling back partial edits' "$src" | head -1 | cut -d: -f1)
  [ -n "$rollback_line" ]
  [ "$rollback_line" -gt "$eval_line" ]
}

# --- evaluate_phase_result: non-zero exit with successful session but no write actions ---

@test "evaluate_phase_result: non-zero exit with successful session but no write actions returns failure" {
  _setup_epr_stubs
  local log="$_tmpdir/phase-5.log"
  local raw="$_tmpdir/phase-5.raw.json"
  # Log with successful session (turns=15, tokens>0)
  printf '=== EXECUTION START phase=5 attempt=1 ===\n' > "$log"
  printf '=== RESPONSE ===\nSome output here.\n' >> "$log"
  printf '[Session: duration=30.0s turns=15 tokens=5000in/2000out]\n' >> "$log"
  # Raw log with only read actions (no writes)
  printf '=== EXECUTION START phase=5 attempt=1 ===\n' > "$raw"
  printf '{"type":"tool_use","name":"Read","input":{}}\n' >> "$raw"
  # NO signal file
  rm -f ".claudeloop/signals/phase-5.md"
  phase_set ATTEMPTS 5 "1"
  # Non-zero exit (exit=1), successful session present, but no write actions
  run evaluate_phase_result 5 1 1 "$log" "$raw"
  [ "$status" -eq 1 ]
}

# --- run_adaptive_verification: write action checks ---

# Helper to set up stubs needed by run_adaptive_verification
_setup_rav_stubs() {
  source "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  source "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  source "${BATS_TEST_DIRNAME}/../lib/retry.sh"
  PROGRESS_FILE="$_tmpdir/progress"
  PLAN_FILE="$_tmpdir/plan"
  CURRENT_PHASE=""
  MAX_RETRIES=15
  # Stub functions called by run_adaptive_verification
  update_phase_status() { phase_set STATUS "$1" "$2"; }
  write_progress() { :; }
  print_error() { :; }
  verify_phase() { return 0; }
  mkdir -p .claudeloop/logs
}

@test "run_adaptive_verification: quick mode fails without write actions" {
  _setup_rav_stubs
  local raw=".claudeloop/logs/phase-1.raw.json"
  # Raw log with no write actions
  printf '{"type":"tool_use","name":"Read","input":{}}\n' > "$raw"
  # attempt=6 with MAX_RETRIES=15 → third=(15+2)/3=5, quick range is 6..10
  run run_adaptive_verification 1 6 "$_tmpdir/phase-1.log"
  [ "$status" -eq 1 ]
  rm -rf .claudeloop
}

@test "run_adaptive_verification: quick mode passes with write actions" {
  _setup_rav_stubs
  local raw=".claudeloop/logs/phase-1.raw.json"
  # Raw log WITH write actions (Edit tool)
  printf '{"type":"tool_use","name":"Edit","input":{}}\n' > "$raw"
  # attempt=6 with MAX_RETRIES=15 → quick mode
  run run_adaptive_verification 1 6 "$_tmpdir/phase-1.log"
  [ "$status" -eq 0 ]
  rm -rf .claudeloop
}

@test "run_adaptive_verification: skip mode fails without write actions" {
  _setup_rav_stubs
  local raw=".claudeloop/logs/phase-1.raw.json"
  # Raw log with no write actions
  printf '{"type":"tool_use","name":"Read","input":{}}\n' > "$raw"
  # attempt=12 with MAX_RETRIES=15 → third=5, skip range is >10
  run run_adaptive_verification 1 12 "$_tmpdir/phase-1.log"
  [ "$status" -eq 1 ]
  rm -rf .claudeloop
}
