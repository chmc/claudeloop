#!/usr/bin/env bats
# bats file_tags=recorder

# Tests for lib/recorder.sh — flight recorder JSON extraction

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  export TEST_DIR

  # Source libraries in dependency order
  . "$CLAUDELOOP_DIR/lib/parser.sh"
  . "$CLAUDELOOP_DIR/lib/phase_state.sh"
  . "$CLAUDELOOP_DIR/lib/progress.sh"
  . "$CLAUDELOOP_DIR/lib/ui.sh"
  . "$CLAUDELOOP_DIR/lib/recorder.sh"

  # Defaults
  SIMPLE_MODE=false
  LIVE_LOG=""

  cd "$TEST_DIR"
}

# --- Helper: create synthetic .claudeloop/ fixtures ---

_create_fixtures() {
  local run_dir="$TEST_DIR/run"
  mkdir -p "$run_dir/logs" "$run_dir/signals"

  # PROGRESS.md: 2 phases — phase 1 completed in 1 attempt, phase 2 completed after 3 attempts
  cat > "$run_dir/PROGRESS.md" << 'EOF'
# Progress for PLAN.md
Last updated: 2026-03-01 10:30:00

## Status Summary
- Total phases: 2
- Completed: 2
- In progress: 0
- Pending: 0
- Failed: 0

## Phase Details

### ✅ Phase 1: Setup project
Status: completed
Started: 2026-03-01 10:00:00
Completed: 2026-03-01 10:05:00
Attempts: 1

### ✅ Phase 2: Build feature
Status: completed
Started: 2026-03-01 10:06:00
Completed: 2026-03-01 10:30:00
Attempts: 3
Attempt 1 Started: 2026-03-01 10:06:00
Attempt 2 Started: 2026-03-01 10:15:00
Attempt 3 Started: 2026-03-01 10:22:00
Depends on: Phase 1 ✅

EOF

  # Phase 1 log — single attempt, successful
  cat > "$run_dir/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
=== PROMPT ===
Do phase 1
=== RESPONSE ===
Done with phase 1
[Session: model=claude-sonnet-4-20250514 cost=$0.0523 duration=45.2s turns=12 tokens=5000in/2000out cache=1200r/800w]
=== EXECUTION END exit_code=0 duration=300s time=2026-03-01T10:05:00 ===
EOF

  # Phase 2 — attempt 1 (failed)
  cat > "$run_dir/logs/phase-2.attempt-1.log" << 'EOF'
=== EXECUTION START phase=2 attempt=1 time=2026-03-01T10:06:00 ===
=== PROMPT ===
Do phase 2
=== RESPONSE ===
Failed
[Session: model=claude-sonnet-4-20250514 cost=$0.0100 duration=20.0s turns=5 tokens=2000in/800out]
=== EXECUTION END exit_code=1 duration=120s time=2026-03-01T10:08:00 ===
EOF

  # Phase 2 — attempt 2 (failed)
  cat > "$run_dir/logs/phase-2.attempt-2.log" << 'EOF'
=== EXECUTION START phase=2 attempt=2 time=2026-03-01T10:15:00 ===
=== PROMPT ===
Retry phase 2
=== RESPONSE ===
Failed again
[Session: model=claude-sonnet-4-20250514 cost=$0.0200 duration=30.0s turns=8 tokens=3000in/1200out]
=== EXECUTION END exit_code=1 duration=180s time=2026-03-01T10:18:00 ===
EOF

  # Phase 2 — current attempt (succeeded)
  cat > "$run_dir/logs/phase-2.log" << 'EOF'
=== EXECUTION START phase=2 attempt=3 time=2026-03-01T10:22:00 ===
=== PROMPT ===
Retry phase 2 again
=== RESPONSE ===
Success!
[Session: model=claude-sonnet-4-20250514 cost=$0.0800 duration=60.5s turns=15 tokens=8000in/3000out cache=500r/300w]
=== EXECUTION END exit_code=0 duration=480s time=2026-03-01T10:30:00 ===
EOF

  # Raw JSON for phase 1
  cat > "$run_dir/logs/phase-1.raw.json" << 'EOF'
{"type":"tool_use","name":"Read","input":{"file_path":"src/foo.ts"}}
{"type":"tool_use","name":"Edit","input":{"file_path":"src/foo.ts","old_string":"a","new_string":"b"}}
{"type":"tool_use","name":"Edit","input":{"file_path":"src/foo.ts","old_string":"c","new_string":"d"}}
{"type":"tool_use","name":"Write","input":{"file_path":"src/bar.ts","content":"hello"}}
{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}
{"type":"tool_use","name":"Read","input":{"file_path":"src/bar.ts"}}
{"type":"text","text":"some output"}
{"type":"tool_use","name":"Edit","input":{"file_path":"src/foo.ts","old_string":"e","new_string":"f"}}
EOF

  # Verification log for phase 1
  cat > "$run_dir/logs/phase-1.verify.log" << 'EOF'
Verifying phase 1...
VERIFICATION_PASSED
EOF

  # Verification log for phase 2
  cat > "$run_dir/logs/phase-2.verify.log" << 'EOF'
Verifying phase 2...
VERIFICATION_PASSED
EOF

  # metadata.txt (archived run)
  cat > "$run_dir/metadata.txt" << 'EOF'
plan_file=PLAN.md
archived_at=2026-03-01 10:31:00
phase_count=2
completed=2
failed=0
pending=0
EOF

  printf '%s' "$run_dir"
}

# =============================================================================
# json_escape tests
# =============================================================================

@test "json_escape: plain string unchanged" {
  result=$(json_escape "hello world")
  [ "$result" = "hello world" ]
}

@test "json_escape: escapes double quotes" {
  result=$(json_escape 'say "hello"')
  [ "$result" = 'say \"hello\"' ]
}

@test "json_escape: escapes backslashes" {
  result=$(json_escape 'path\\to\\file')
  [ "$result" = 'path\\\\to\\\\file' ]
}

@test "json_escape: escapes backslash before quote" {
  result=$(json_escape 'a\\"b')
  [ "$result" = 'a\\\\\"b' ]
}

@test "json_escape: escapes tabs" {
  result=$(json_escape "$(printf 'a\tb')")
  [ "$result" = 'a\tb' ]
}

@test "json_escape: handles empty string" {
  result=$(json_escape "")
  [ "$result" = "" ]
}

@test "json_escape: handles special chars in phase titles" {
  result=$(json_escape 'Phase 1: Setup "project" & init')
  [ "$result" = 'Phase 1: Setup \"project\" & init' ]
}

@test "json_escape: escapes newlines" {
  result=$(json_escape "$(printf 'line1\nline2')")
  [ "$result" = 'line1\nline2' ]
}

# =============================================================================
# rec_load_progress tests
# =============================================================================

@test "rec_load_progress: parses phase statuses" {
  run_dir=$(_create_fixtures)
  rec_load_progress "$run_dir"
  [ "$_REC_PHASE_COUNT" = "2" ]
  [ "$_REC_PHASE_STATUS_1" = "completed" ]
  [ "$_REC_PHASE_STATUS_2" = "completed" ]
}

@test "rec_load_progress: parses phase titles" {
  run_dir=$(_create_fixtures)
  rec_load_progress "$run_dir"
  [ "$_REC_PHASE_TITLE_1" = "Setup project" ]
  [ "$_REC_PHASE_TITLE_2" = "Build feature" ]
}

@test "rec_load_progress: parses attempts" {
  run_dir=$(_create_fixtures)
  rec_load_progress "$run_dir"
  [ "$_REC_PHASE_ATTEMPTS_1" = "1" ]
  [ "$_REC_PHASE_ATTEMPTS_2" = "3" ]
}

@test "rec_load_progress: parses timestamps" {
  run_dir=$(_create_fixtures)
  rec_load_progress "$run_dir"
  [ "$_REC_PHASE_START_TIME_1" = "2026-03-01 10:00:00" ]
  [ "$_REC_PHASE_END_TIME_1" = "2026-03-01 10:05:00" ]
  [ "$_REC_PHASE_START_TIME_2" = "2026-03-01 10:06:00" ]
  [ "$_REC_PHASE_END_TIME_2" = "2026-03-01 10:30:00" ]
}

@test "rec_load_progress: parses dependencies" {
  run_dir=$(_create_fixtures)
  rec_load_progress "$run_dir"
  [ "$_REC_PHASE_DEPS_1" = "" ]
  [ "$_REC_PHASE_DEPS_2" = "1" ]
}

@test "rec_load_progress: handles missing file gracefully" {
  run_dir="$TEST_DIR/empty"
  mkdir -p "$run_dir"
  rec_load_progress "$run_dir"
  [ "$_REC_PHASE_COUNT" = "0" ]
}

# =============================================================================
# rec_extract_session tests
# =============================================================================

@test "rec_extract_session: extracts all fields" {
  run_dir=$(_create_fixtures)
  result=$(rec_extract_session "$run_dir/logs/phase-1.log")
  echo "$result" | grep -q '"model":"claude-sonnet-4-20250514"'
  echo "$result" | grep -q '"cost_usd":0.0523'
  echo "$result" | grep -q '"duration_s":45.2'
  echo "$result" | grep -q '"turns":12'
  echo "$result" | grep -q '"input_tokens":5000'
  echo "$result" | grep -q '"output_tokens":2000'
  echo "$result" | grep -q '"cache_read":1200'
  echo "$result" | grep -q '"cache_write":800'
}

@test "rec_extract_session: handles missing cache fields" {
  local logfile="$TEST_DIR/nocache.log"
  cat > "$logfile" << 'EOF'
[Session: model=claude-sonnet-4-20250514 cost=$0.0100 duration=10.0s turns=3 tokens=1000in/500out]
EOF
  result=$(rec_extract_session "$logfile")
  echo "$result" | grep -q '"cache_read":0'
  echo "$result" | grep -q '"cache_write":0'
}

@test "rec_extract_session: returns null for missing session line" {
  local logfile="$TEST_DIR/nosession.log"
  echo "no session here" > "$logfile"
  result=$(rec_extract_session "$logfile")
  [ "$result" = "null" ]
}

@test "rec_extract_session: handles missing file" {
  result=$(rec_extract_session "$TEST_DIR/nonexistent.log")
  [ "$result" = "null" ]
}

# =============================================================================
# rec_extract_exec_meta tests
# =============================================================================

@test "rec_extract_exec_meta: extracts start and end" {
  run_dir=$(_create_fixtures)
  result=$(rec_extract_exec_meta "$run_dir/logs/phase-1.log")
  echo "$result" | grep -q '"started_at":"2026-03-01T10:00:00"'
  echo "$result" | grep -q '"ended_at":"2026-03-01T10:05:00"'
  echo "$result" | grep -q '"exit_code":0'
  echo "$result" | grep -q '"duration_s":300'
}

@test "rec_extract_exec_meta: handles missing END (interrupted)" {
  local logfile="$TEST_DIR/interrupted.log"
  cat > "$logfile" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
=== PROMPT ===
Do stuff
EOF
  result=$(rec_extract_exec_meta "$logfile")
  echo "$result" | grep -q '"started_at":"2026-03-01T10:00:00"'
  echo "$result" | grep -q '"ended_at":null'
  echo "$result" | grep -q '"exit_code":null'
  echo "$result" | grep -q '"duration_s":null'
}

@test "rec_extract_exec_meta: handles missing file" {
  result=$(rec_extract_exec_meta "$TEST_DIR/nonexistent.log")
  echo "$result" | grep -q '"started_at":null'
}

# =============================================================================
# rec_extract_tools tests
# =============================================================================

@test "rec_extract_tools: counts tool usage" {
  run_dir=$(_create_fixtures)
  result=$(rec_extract_tools "$run_dir/logs/phase-1.raw.json")
  # Edit: 3, Read: 2, Write: 1, Bash: 1
  echo "$result" | grep -q '"name":"Bash","count":1'
  echo "$result" | grep -q '"name":"Edit","count":3'
  echo "$result" | grep -q '"name":"Read","count":2'
  echo "$result" | grep -q '"name":"Write","count":1'
}

@test "rec_extract_tools: returns empty array for missing file" {
  result=$(rec_extract_tools "$TEST_DIR/nonexistent.raw.json")
  [ "$result" = "[]" ]
}

@test "rec_extract_tools: returns empty array for empty file" {
  touch "$TEST_DIR/empty.raw.json"
  result=$(rec_extract_tools "$TEST_DIR/empty.raw.json")
  [ "$result" = "[]" ]
}

# =============================================================================
# rec_extract_files tests
# =============================================================================

@test "rec_extract_files: extracts unique files with ops" {
  run_dir=$(_create_fixtures)
  result=$(rec_extract_files "$run_dir/logs/phase-1.raw.json")
  # src/bar.ts: Read, Write
  # src/foo.ts: Read, Edit
  echo "$result" | grep -q '"path":"src/bar.ts"'
  echo "$result" | grep -q '"path":"src/foo.ts"'
  # Check ops are deduplicated
  echo "$result" | grep -q '"ops":\["Read","Write"\]'
  echo "$result" | grep -q '"ops":\["Edit","Read"\]'
}

@test "rec_extract_files: returns empty array for missing file" {
  result=$(rec_extract_files "$TEST_DIR/nonexistent.raw.json")
  [ "$result" = "[]" ]
}

# =============================================================================
# rec_verify_verdict tests
# =============================================================================

@test "rec_verify_verdict: returns passed" {
  run_dir=$(_create_fixtures)
  result=$(rec_verify_verdict "$run_dir" "1")
  [ "$result" = '"passed"' ]
}

@test "rec_verify_verdict: returns failed" {
  run_dir=$(_create_fixtures)
  # Overwrite with failed verdict
  echo "VERIFICATION_FAILED" > "$run_dir/logs/phase-1.verify.log"
  result=$(rec_verify_verdict "$run_dir" "1")
  [ "$result" = '"failed"' ]
}

@test "rec_verify_verdict: returns null when no verify log" {
  run_dir=$(_create_fixtures)
  rm -f "$run_dir/logs/phase-1.verify.log"
  result=$(rec_verify_verdict "$run_dir" "1")
  [ "$result" = "null" ]
}

# =============================================================================
# rec_extract_run_overview tests
# =============================================================================

@test "rec_extract_run_overview: parses metadata.txt (archived run)" {
  run_dir=$(_create_fixtures)
  result=$(rec_extract_run_overview "$run_dir")
  echo "$result" | grep -q '"plan_file":"PLAN.md"'
  echo "$result" | grep -q '"phase_count":2'
  echo "$result" | grep -q '"completed":2'
  echo "$result" | grep -q '"failed":0'
  echo "$result" | grep -q '"pending":0'
}

@test "rec_extract_run_overview: computes from progress when no metadata" {
  run_dir=$(_create_fixtures)
  rm -f "$run_dir/metadata.txt"
  result=$(rec_extract_run_overview "$run_dir")
  echo "$result" | grep -q '"phase_count":2'
  echo "$result" | grep -q '"completed":2'
}

@test "rec_extract_run_overview: aggregates session costs" {
  run_dir=$(_create_fixtures)
  rm -f "$run_dir/metadata.txt"
  result=$(rec_extract_run_overview "$run_dir")
  # Phase 1: 0.0523, Phase 2 attempts: 0.01 + 0.02 + 0.08 = 0.11
  # Total: 0.1623
  echo "$result" | grep -q '"total_cost_usd"'
}

# =============================================================================
# rec_extract_git_commits tests
# =============================================================================

@test "rec_extract_git_commits: returns empty array when no commits match" {
  result=$(rec_extract_git_commits "999")
  [ "$result" = "[]" ]
}

# =============================================================================
# rec_extract_exec_meta: decimal phase numbers
# =============================================================================

@test "rec_extract_exec_meta: handles decimal phase number in log" {
  local logfile="$TEST_DIR/decimal.log"
  cat > "$logfile" << 'EOF'
=== EXECUTION START phase=2.5 attempt=1 time=2026-03-01T11:00:00 ===
=== PROMPT ===
Do phase 2.5
=== RESPONSE ===
Done
[Session: model=claude-sonnet-4-20250514 cost=$0.0300 duration=25.0s turns=6 tokens=3000in/1000out]
=== EXECUTION END exit_code=0 duration=150s time=2026-03-01T11:02:30 ===
EOF
  result=$(rec_extract_exec_meta "$logfile")
  echo "$result" | grep -q '"started_at":"2026-03-01T11:00:00"'
  echo "$result" | grep -q '"exit_code":0'
  echo "$result" | grep -q '"duration_s":150'
}

# =============================================================================
# assemble_recorder_json tests
# =============================================================================

@test "assemble_recorder_json: produces valid JSON structure" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  # Check top-level keys
  echo "$result" | grep -q '"version":1'
  echo "$result" | grep -q '"generated_at":'
  echo "$result" | grep -q '"run":'
  echo "$result" | grep -q '"phases":'
}

@test "assemble_recorder_json: includes phase details" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  echo "$result" | grep -q '"number":"1"'
  echo "$result" | grep -q '"title":"Setup project"'
  echo "$result" | grep -q '"number":"2"'
  echo "$result" | grep -q '"title":"Build feature"'
}

@test "assemble_recorder_json: includes attempts for multi-attempt phase" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  # Phase 2 should have 3 attempts
  echo "$result" | grep -q '"attempts":\['
}

@test "assemble_recorder_json: includes signal_no_changes false" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  echo "$result" | grep -q '"signal_no_changes":false'
}

@test "assemble_recorder_json: detects signal_no_changes true" {
  run_dir=$(_create_fixtures)
  echo "No changes needed" > "$run_dir/signals/phase-1.md"
  result=$(assemble_recorder_json "$run_dir")
  echo "$result" | grep -q '"signal_no_changes":true'
}

@test "assemble_recorder_json: includes verification verdict" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  echo "$result" | grep -q '"verification_verdict":"passed"'
}

# --- inject_and_write_html tests ---

@test "inject_and_write_html: produces valid HTML with JSON embedded" {
  local json_file="$TEST_DIR/test.json"
  local output_html="$TEST_DIR/output.html"
  echo '{"version":1,"phases":[]}' > "$json_file"

  inject_and_write_html "$json_file" "$output_html"
  [ -f "$output_html" ]

  # Should contain the injected JSON as const DATA
  grep -q 'const DATA = {"version":1,"phases":\[\]}' "$output_html"

  # Should still contain HTML structure
  grep -q '<!DOCTYPE html>' "$output_html"
  grep -q '</html>' "$output_html"

  # Should NOT contain the marker comment
  ! grep -q '<!--JSON_DATA-->' "$output_html"
}

@test "inject_and_write_html: fails gracefully with missing template" {
  local json_file="$TEST_DIR/test.json"
  echo '{}' > "$json_file"
  # Override SCRIPT_DIR to point to nonexistent dir
  local old_script_dir="$SCRIPT_DIR"
  SCRIPT_DIR="$TEST_DIR/nonexistent"
  run inject_and_write_html "$json_file" "$TEST_DIR/out.html"
  SCRIPT_DIR="$old_script_dir"
  [ "$status" -ne 0 ]
}

@test "inject_and_write_html: fails gracefully with missing JSON file" {
  run inject_and_write_html "$TEST_DIR/missing.json" "$TEST_DIR/out.html"
  [ "$status" -ne 0 ]
}

# --- generate_flight_recorder tests ---

@test "generate_flight_recorder: end-to-end with fixture data produces valid HTML" {
  run_dir=$(_create_fixtures)

  generate_flight_recorder "$run_dir"
  [ -f "$run_dir/replay.html" ]

  # Should contain HTML structure
  grep -q '<!DOCTYPE html>' "$run_dir/replay.html"
  grep -q 'ClaudeLoop Flight Recorder' "$run_dir/replay.html"

  # Should contain embedded JSON with phase data
  grep -q '"phases":\[' "$run_dir/replay.html"
  grep -q '"Setup project"' "$run_dir/replay.html"
  grep -q '"version":1' "$run_dir/replay.html"
}

@test "generate_flight_recorder: cleans up temp JSON file" {
  run_dir=$(_create_fixtures)
  generate_flight_recorder "$run_dir"
  [ ! -f "$run_dir/recorder.json.tmp" ]
}

@test "generate_flight_recorder: silent on failure with invalid run dir" {
  run generate_flight_recorder "$TEST_DIR/nonexistent"
  [ "$status" -eq 0 ]
}

# =============================================================================
# rec_extract_prompt_text tests
# =============================================================================

@test "rec_extract_prompt_text: extracts text between markers" {
  local logfile="$TEST_DIR/prompt.log"
  cat > "$logfile" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
=== PROMPT ===
Do something useful
with multiple lines
=== RESPONSE ===
Done
[Session: model=claude-sonnet-4-20250514 cost=$0.01 duration=5.0s turns=2 tokens=100in/50out]
=== EXECUTION END exit_code=0 duration=10s time=2026-03-01T10:00:10 ===
EOF
  result=$(rec_extract_prompt_text "$logfile")
  [ "$result" = "Do something useful\nwith multiple lines" ]
}

@test "rec_extract_prompt_text: returns null for missing file" {
  result=$(rec_extract_prompt_text "$TEST_DIR/nonexistent.log")
  [ "$result" = "null" ]
}

@test "rec_extract_prompt_text: returns null when no PROMPT marker" {
  local logfile="$TEST_DIR/noprompt.log"
  echo "no markers here" > "$logfile"
  result=$(rec_extract_prompt_text "$logfile")
  [ "$result" = "null" ]
}

@test "rec_extract_prompt_text: truncates oversized prompts" {
  local logfile="$TEST_DIR/bigprompt.log"
  {
    echo "=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ==="
    echo "=== PROMPT ==="
    # Generate 250 lines
    local i=1
    while [ "$i" -le 250 ]; do
      echo "line $i of the prompt"
      i=$((i + 1))
    done
    echo "=== RESPONSE ==="
    echo "Done"
  } > "$logfile"
  result=$(rec_extract_prompt_text "$logfile")
  # Should contain first 80 lines
  echo "$result" | grep -q 'line 1 of the prompt'
  echo "$result" | grep -q 'line 80 of the prompt'
  # Should contain omission notice
  echo "$result" | grep -q '90 lines omitted'
  # Should contain last 80 lines
  echo "$result" | grep -q 'line 171 of the prompt'
  echo "$result" | grep -q 'line 250 of the prompt'
  # Should NOT contain middle lines
  ! echo "$result" | grep -q 'line 100 of the prompt'
}

@test "rec_extract_prompt_text: JSON-escapes special chars" {
  local logfile="$TEST_DIR/escape_prompt.log"
  cat > "$logfile" << 'LOGEOF'
=== PROMPT ===
Say "hello" and use backslash\here
=== RESPONSE ===
Done
LOGEOF
  result=$(rec_extract_prompt_text "$logfile")
  # Should have escaped quotes and backslashes
  echo "$result" | grep -q '\\"hello\\"'
  echo "$result" | grep -q 'backslash\\\\here'
}

# =============================================================================
# assemble_recorder_json: prompt_text inclusion
# =============================================================================

@test "assemble_recorder_json: includes prompt_text in attempts" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  # Phase 1 attempt should have prompt_text with "Do phase 1"
  echo "$result" | grep -q '"prompt_text":"Do phase 1"'
  # Phase 2 attempt 1 should have "Do phase 2"
  echo "$result" | grep -q '"prompt_text":"Do phase 2"'
  # Phase 2 attempt 2 should have "Retry phase 2"
  echo "$result" | grep -q '"prompt_text":"Retry phase 2"'
}
