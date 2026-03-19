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

  # Raw JSON for phase 2 attempt 1 (failed attempt)
  cat > "$run_dir/logs/phase-2.attempt-1.raw.json" << 'EOF'
{"type":"tool_use","name":"Read","input":{"file_path":"src/main.ts"}}
{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}
EOF

  # Raw JSON for phase 2 attempt 2 (failed attempt)
  cat > "$run_dir/logs/phase-2.attempt-2.raw.json" << 'EOF'
{"type":"tool_use","name":"Read","input":{"file_path":"src/main.ts"}}
{"type":"tool_use","name":"Edit","input":{"file_path":"src/main.ts","old_string":"x","new_string":"y"}}
{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}
EOF

  # Raw JSON for phase 2 current attempt (success)
  cat > "$run_dir/logs/phase-2.raw.json" << 'EOF'
{"type":"tool_use","name":"Read","input":{"file_path":"src/main.ts"}}
{"type":"tool_use","name":"Edit","input":{"file_path":"src/main.ts","old_string":"a","new_string":"b"}}
{"type":"tool_use","name":"Edit","input":{"file_path":"src/util.ts","old_string":"c","new_string":"d"}}
{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}
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

@test "inject_and_write_html: escapes < to prevent script injection" {
  local json_file="$TEST_DIR/script.json"
  local output_html="$TEST_DIR/output.html"
  # JSON containing </script> which would break inline <script> blocks
  printf '{"prompt":"use </script> tag"}' > "$json_file"

  inject_and_write_html "$json_file" "$output_html"
  [ -f "$output_html" ]

  # The literal </script should NOT appear inside the injected data
  # Extract just the const DATA = ... line
  local data_line
  data_line=$(grep 'const DATA = ' "$output_html")
  ! echo "$data_line" | grep -q '</script'

  # The escaped form \u003c should be present
  grep -q '\\u003c' "$output_html"
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

@test "assemble_recorder_json: includes tools and files for all attempts" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  # Phase 2 attempt 1 should have tools from its raw.json (Read:1, Bash:1)
  # Phase 2 attempt 2 should have tools from its raw.json (Read:1, Edit:1, Bash:1)
  # Phase 2 attempt 3 should have tools from phase-2.raw.json (Read:1, Edit:2, Bash:1)
  # All attempts should have non-empty tools arrays
  # Count occurrences of "Bash" tool in the output — should appear in all attempts
  local bash_count
  bash_count=$(echo "$result" | grep -o '"name":"Bash"' | wc -l | tr -d ' ')
  # Phase 1 (1 Bash) + Phase 2 attempt 1 (1 Bash) + attempt 2 (1 Bash) + attempt 3 (1 Bash) = 4
  [ "$bash_count" -eq 4 ]
  # Phase 2 attempt 1 should have files (src/main.ts only from Read)
  echo "$result" | grep -q '"path":"src/main.ts"'
  # Phase 2 attempt 3 should have src/util.ts (new file in last attempt)
  echo "$result" | grep -q '"path":"src/util.ts"'
}

# =============================================================================
# Bug 1: Session extraction with [Session:] not at BOL
# =============================================================================

@test "rec_extract_session: extracts session line not at beginning of line" {
  local logfile="$TEST_DIR/midline.log"
  cat > "$logfile" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
=== PROMPT ===
Do stuff
=== RESPONSE ===
Done with regressions[Session: model=claude-sonnet-4-20250514 cost=$0.0400 duration=30.0s turns=8 tokens=4000in/1500out cache=200r/100w]
=== EXECUTION END exit_code=0 duration=60s time=2026-03-01T10:01:00 ===
EOF
  result=$(rec_extract_session "$logfile")
  echo "$result" | grep -q '"model":"claude-sonnet-4-20250514"'
  echo "$result" | grep -q '"cost_usd":0.0400'
  echo "$result" | grep -q '"input_tokens":4000'
}

# =============================================================================
# Bug 6: Session extraction ignores [Session:] in prompt text
# =============================================================================

@test "rec_extract_session: ignores [Session:] mentions in prompt text" {
  local logfile="$TEST_DIR/promptmention.log"
  cat > "$logfile" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
=== PROMPT ===
The session line format is [Session: model=X cost=$Y duration=Zs turns=N tokens=Ain/Bout]
=== RESPONSE ===
Done
[Session: model=claude-sonnet-4-20250514 cost=$0.0300 duration=20.0s turns=5 tokens=3000in/1000out]
=== EXECUTION END exit_code=0 duration=30s time=2026-03-01T10:00:30 ===
EOF
  result=$(rec_extract_session "$logfile")
  # Should pick the real session line, not the prompt mention
  echo "$result" | grep -q '"cost_usd":0.0300'
  echo "$result" | grep -q '"model":"claude-sonnet-4-20250514"'
}

# =============================================================================
# Bug 2: Aggregation excludes verify/refactor/formatted logs
# =============================================================================

@test "_rec_aggregate_sessions: excludes verify/refactor/formatted logs" {
  local run_dir="$TEST_DIR/agg_run"
  mkdir -p "$run_dir/logs"

  # Main execution log
  cat > "$run_dir/logs/phase-1.log" << 'EOF'
=== EXECUTION START phase=1 attempt=1 time=2026-03-01T10:00:00 ===
[Session: model=claude-sonnet-4-20250514 cost=$0.0500 duration=30.0s turns=8 tokens=5000in/2000out]
=== EXECUTION END exit_code=0 duration=60s time=2026-03-01T10:01:00 ===
EOF

  # Verify log (should be excluded)
  cat > "$run_dir/logs/phase-1.verify.log" << 'EOF'
[Session: model=claude-sonnet-4-20250514 cost=$0.0100 duration=10.0s turns=2 tokens=1000in/500out]
EOF

  # Refactor log (should be excluded)
  cat > "$run_dir/logs/phase-1.refactor.log" << 'EOF'
[Session: model=claude-sonnet-4-20250514 cost=$0.0200 duration=15.0s turns=3 tokens=2000in/800out]
EOF

  # Formatted log (should be excluded)
  cat > "$run_dir/logs/phase-1.formatted.log" << 'EOF'
[Session: model=claude-sonnet-4-20250514 cost=$0.0300 duration=20.0s turns=4 tokens=3000in/1000out]
EOF

  result=$(_rec_aggregate_sessions "$run_dir")
  local total_cost
  total_cost=$(printf '%s' "$result" | cut -d'|' -f1)
  # Should only count main log: 0.0500. NOT 0.0500 + 0.0100 + 0.0200 + 0.0300 = 0.1100
  [ "$(echo "$total_cost > 0.04 && $total_cost < 0.06" | bc)" = "1" ]
}

# =============================================================================
# Bug 3 & 4: Strategy and fail_reason in recorder JSON
# =============================================================================

@test "rec_load_progress: parses attempt strategy and fail_reason" {
  local run_dir="$TEST_DIR/strat_run"
  mkdir -p "$run_dir/logs"

  cat > "$run_dir/PROGRESS.md" << 'EOF'
# Progress for PLAN.md
Last updated: 2026-03-01 10:30:00

## Phase Details

### ✅ Phase 1: Do stuff
Status: completed
Started: 2026-03-01 10:00:00
Completed: 2026-03-01 10:30:00
Attempts: 3
Attempt 1 Started: 2026-03-01 10:00:00
Attempt 1 Strategy: standard
Attempt 1 Fail Reason: no_write_actions
Attempt 2 Started: 2026-03-01 10:10:00
Attempt 2 Strategy: stripped
Attempt 2 Fail Reason: verification_failed
Attempt 3 Started: 2026-03-01 10:20:00
Attempt 3 Strategy: targeted

EOF

  rec_load_progress "$run_dir"

  # Check strategy per attempt
  local s1 s2 s3
  s1=$(_rec_get ATTEMPT_STRATEGY "1" 1)
  s2=$(_rec_get ATTEMPT_STRATEGY "1" 2)
  s3=$(_rec_get ATTEMPT_STRATEGY "1" 3)
  [ "$s1" = "standard" ]
  [ "$s2" = "stripped" ]
  [ "$s3" = "targeted" ]

  # Check fail_reason per attempt
  local f1 f2 f3
  f1=$(_rec_get ATTEMPT_FAIL_REASON "1" 1)
  f2=$(_rec_get ATTEMPT_FAIL_REASON "1" 2)
  f3=$(_rec_get ATTEMPT_FAIL_REASON "1" 3)
  [ "$f1" = "no_write_actions" ]
  [ "$f2" = "verification_failed" ]
  [ "$f3" = "" ]
}

@test "assemble_recorder_json: includes strategy and fail_reason per attempt" {
  run_dir=$(_create_fixtures)
  # Add strategy/fail_reason lines to PROGRESS.md for phase 2
  # Phase 2 has 3 attempts — patch the existing PROGRESS.md
  sed -i '' '/^Attempt 1 Started:.*10:06/a\
Attempt 1 Strategy: standard\
Attempt 1 Fail Reason: no_write_actions' "$run_dir/PROGRESS.md"
  sed -i '' '/^Attempt 2 Started:.*10:15/a\
Attempt 2 Strategy: stripped\
Attempt 2 Fail Reason: verification_failed' "$run_dir/PROGRESS.md"
  sed -i '' '/^Attempt 3 Started:.*10:22/a\
Attempt 3 Strategy: targeted' "$run_dir/PROGRESS.md"

  result=$(assemble_recorder_json "$run_dir")
  # Phase 2 attempt 1 should have strategy "standard" and fail_reason "no_write_actions"
  echo "$result" | grep -q '"strategy":"standard","fail_reason":"no_write_actions"'
  # Phase 2 attempt 2 should have strategy "stripped" and fail_reason "verification_failed"
  echo "$result" | grep -q '"strategy":"stripped","fail_reason":"verification_failed"'
  # Phase 2 attempt 3 should have strategy "targeted" and null fail_reason
  echo "$result" | grep -q '"strategy":"targeted","fail_reason":null'
}

@test "assemble_recorder_json: defaults strategy to standard when missing" {
  run_dir=$(_create_fixtures)
  # No strategy/fail_reason lines in PROGRESS.md — should default
  result=$(assemble_recorder_json "$run_dir")
  echo "$result" | grep -q '"strategy":"standard"'
  echo "$result" | grep -q '"fail_reason":null'
}

# =============================================================================
# Bug 5: Phase started_at uses earliest attempt time
# =============================================================================

@test "assemble_recorder_json: phase started_at uses earliest attempt time" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  # Phase 2 PROGRESS.md says Started: 2026-03-01 10:06:00 (overwritten by last attempt)
  # But Attempt 1 Started: 2026-03-01 10:06:00 is the earliest
  # The phase started_at should be 2026-03-01 10:06:00
  # For phase 1 with 1 attempt, started_at should be from PROGRESS.md
  echo "$result" | grep -q '"number":"1".*"started_at":"2026-03-01 10:00:00"'
  echo "$result" | grep -q '"number":"2".*"started_at":"2026-03-01 10:06:00"'
}

# =============================================================================
# is_success computation
# =============================================================================

@test "assemble_recorder_json: computes is_success for multi-attempt completed phase" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  # Phase 2: 3 attempts, completed — only last attempt is success
  # Extract phase 2 attempts block
  phase2=$(echo "$result" | sed 's/.*"number":"2"//' )
  # Attempt 1 and 2 should be is_success:false
  echo "$result" | grep -q '"number":"2".*"is_success":false.*"is_success":false.*"is_success":true'
}

@test "assemble_recorder_json: computes is_success for single-attempt completed phase" {
  run_dir=$(_create_fixtures)
  result=$(assemble_recorder_json "$run_dir")
  # Phase 1: 1 attempt, completed — that attempt is success
  # Phase 1 has "number":"1" (string) in phase, "number":1 (int) in attempt
  echo "$result" | grep -o '"number":"1"[^}]*"attempts":\[{[^]]*' | grep -q '"is_success":true'
}

# =============================================================================
# Attempt-specific raw.json lookup: prefer attempt-N, fall back to phase-level
# =============================================================================

@test "assemble_recorder_json: uses attempt-specific raw.json for last attempt when available" {
  run_dir=$(_create_fixtures)
  # Create attempt-3 raw.json with DIFFERENT tools than phase-2.raw.json
  cat > "$run_dir/logs/phase-2.attempt-3.raw.json" << 'EOF'
{"type":"tool_use","name":"Write","input":{"file_path":"src/new.ts","content":"x"}}
{"type":"tool_use","name":"Bash","input":{"command":"npm build"}}
EOF
  result=$(assemble_recorder_json "$run_dir")
  # Last attempt (3) should use attempt-3.raw.json, which has Write+Bash (not Edit)
  # The phase-2.raw.json has Edit but attempt-3 does not
  # Extract phase 2 data and check that Write appears in last attempt
  echo "$result" | grep -q '"path":"src/new.ts"'
}

@test "assemble_recorder_json: falls back to phase-level raw.json for last attempt when no attempt file" {
  run_dir=$(_create_fixtures)
  # Ensure no attempt-3 raw.json exists (default fixtures don't have it)
  rm -f "$run_dir/logs/phase-2.attempt-3.raw.json"
  result=$(assemble_recorder_json "$run_dir")
  # Should fall back to phase-2.raw.json which has Edit on src/main.ts and src/util.ts
  echo "$result" | grep -q '"path":"src/util.ts"'
}

@test "assemble_recorder_json: is_success false for all attempts of failed phase" {
  run_dir=$(_create_fixtures)
  # Change phase 2 status from completed to failed
  awk '/Status: completed/ && ++n==2 { sub(/completed/, "failed") } 1' "$run_dir/PROGRESS.md" > "$run_dir/PROGRESS.md.tmp"
  mv "$run_dir/PROGRESS.md.tmp" "$run_dir/PROGRESS.md"
  result=$(assemble_recorder_json "$run_dir")
  # All attempts of phase 2 should be is_success:false
  phase2_attempts=$(echo "$result" | grep -o '"number":"2".*' | grep -o '"is_success":[a-z]*' | sort -u)
  [ "$phase2_attempts" = '"is_success":false' ]
}
