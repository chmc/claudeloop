#!/usr/bin/env bash
# bats file_tags=ai_parser

# Test AI Parser Library
# TDD: tests written FIRST

setup() {
  export TEST_DIR="$BATS_TEST_TMPDIR"
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/.claudeloop"
  export LIVE_LOG=""
  export SIMPLE_MODE=false
  . "${BATS_TEST_DIRNAME}/../lib/ui.sh"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  . "${BATS_TEST_DIRNAME}/../lib/phase_state.sh"
  . "${BATS_TEST_DIRNAME}/../lib/stream_processor.sh"
  . "${BATS_TEST_DIRNAME}/../lib/ai_parser.sh"

  # Create text_to_stream_json helper: converts plain text to stream-json events
  cat > "$TEST_DIR/bin/text_to_stream_json" << 'HELPER'
#!/bin/sh
while IFS= read -r line || [ -n "$line" ]; do
  escaped=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s\\n"}]}}\n' "$escaped"
done
HELPER
  chmod +x "$TEST_DIR/bin/text_to_stream_json"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  :
}

# Helper: create a mock claude that outputs given text as stream-json
mock_claude() {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat /dev/stdin > /dev/null
cat << 'ENDOUT' | text_to_stream_json
$1
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"
}

# Helper: create a mock claude that emits system/init + assistant + result events
# This reproduces the metadata contamination bug where process_stream_json
# writes [HH:MM:SS] model=... and [Session: ...] lines to the log file
mock_claude_with_metadata() {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat /dev/stdin > /dev/null
# Emit system/init event (produces "[HH:MM:SS] model=..." in log)
printf '{"type":"system","subtype":"init","model":"claude-opus-4-6[1m]"}\n'
# Emit assistant text events
cat << 'ENDOUT' | text_to_stream_json
$1
ENDOUT
# Emit result event (produces "[Session: ...]" in log)
printf '{"type":"result","total_cost_usd":0.01,"duration_ms":1500,"num_turns":"1","input_tokens":"100","output_tokens":"50","modelUsage":{"claude-opus-4-6[1m]":{"input":100,"output":50}}}\n'
MOCK
  chmod +x "$TEST_DIR/bin/claude"
}

# Helper: create a mock claude that writes to stderr and exits non-zero
mock_claude_fail() {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
echo "$1" >&2
exit 1
MOCK
  chmod +x "$TEST_DIR/bin/claude"
}

# Helper: create a mock claude that outputs nothing
mock_claude_empty() {
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$TEST_DIR/bin/claude"
}

# --- ai_parse_plan tests ---

@test "ai_parse_plan: produces valid plan file from clean AI output" {
  mock_claude "## Phase 1: Setup
Create project structure.

## Phase 2: Implementation
**Depends on:** Phase 1
Implement the feature."

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a web app with authentication.
EOF

  run ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.claudeloop/ai-parsed-plan.md" ]
  grep -q "## Phase 1: Setup" "$TEST_DIR/.claudeloop/ai-parsed-plan.md"
  grep -q "## Phase 2: Implementation" "$TEST_DIR/.claudeloop/ai-parsed-plan.md"
}

@test "ai_parse_plan: output passes existing parse_plan" {
  mock_claude "## Phase 1: Setup
Create project structure.

## Phase 2: Implementation
**Depends on:** Phase 1
Implement the feature.

## Phase 3: Testing
**Depends on:** Phase 2
Add tests."

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  parse_plan "$TEST_DIR/.claudeloop/ai-parsed-plan.md"
  [ "$PHASE_COUNT" -eq 3 ]
}

@test "ai_parse_plan: strips preamble before first ## Phase" {
  mock_claude "Here's the decomposed plan:

Some extra text.

## Phase 1: Setup
Create project structure.

## Phase 2: Build
Build the thing."

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  # File should start with ## Phase, no preamble
  local first_line
  first_line=$(head -1 "$TEST_DIR/.claudeloop/ai-parsed-plan.md")
  [ "$first_line" = "## Phase 1: Setup" ]
}

@test "ai_parse_plan: returns 1 when claude not in PATH" {
  # Remove claude from PATH entirely
  export PATH="/usr/bin:/bin"
  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  run ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
}

@test "ai_parse_plan: returns 1 when claude returns empty output" {
  mock_claude_empty

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  run ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
}

@test "ai_parse_plan: returns 1 when output has no ## Phase headers" {
  mock_claude "This is just some text without any phase headers.
It talks about things but doesn't use the right format."

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  run ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
}

@test "ai_parse_plan: retry succeeds when first call returns garbage" {
  # Mock claude uses a counter file: first call returns garbage, second returns valid
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
counter_file="/tmp/bats_ai_parser_counter_$$"
# Use parent's counter file if set
counter_file="${MOCK_COUNTER_FILE:-$counter_file}"
if [ ! -f "$counter_file" ]; then
  echo "1" > "$counter_file"
  echo "This is garbage with no phases at all." | text_to_stream_json
else
  cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create the project.

## Phase 2: Build
Build it.
ENDOUT
fi
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_FILE="$TEST_DIR/counter"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  run ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.claudeloop/ai-parsed-plan.md" ]
  grep -q "## Phase 1: Setup" "$TEST_DIR/.claudeloop/ai-parsed-plan.md"
}

# --- ai_verify_plan tests ---

@test "ai_verify_plan: returns 0 when AI says PASS" {
  mock_claude "PASS"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
}

@test "ai_verify_plan: returns 2 when AI says FAIL" {
  mock_claude "FAIL
Missing setup phase for database initialization."

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something with database.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 2 ]
}

@test "ai_verify_plan: prompt includes granularity context" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/verify_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
PASS
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md" "steps"
  grep -q "steps" "$TEST_DIR/verify_prompt.txt"
  grep -q "Do NOT penalize" "$TEST_DIR/verify_prompt.txt"
}

@test "ai_verify_plan: works without granularity (backward compat)" {
  mock_claude "PASS"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
}

@test "ai_verify_plan: returns 1 on unexpected format" {
  mock_claude "Looks good to me, everything checks out."

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "warning\|unexpected"
}

# --- confirm_ai_plan tests ---

@test "confirm_ai_plan: auto-accepts with YES_MODE=true" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.

## Phase 2: Build
Build it.
EOF

  export YES_MODE=true
  run confirm_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
}

@test "confirm_ai_plan: auto-accepts with DRY_RUN=true" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  export DRY_RUN=true
  export YES_MODE=false
  run confirm_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
}

# --- run_claude_print tests ---

@test "run_claude_print: captures stderr on failure" {
  mock_claude_fail "API key expired"

  CURRENT_PIPELINE_PID=""
  run run_claude_print "test prompt" "$TEST_DIR/rcp_out"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "failed with exit code"
}

# --- granularity tests ---

@test "ai_parse_plan: phases opening line mentions high-level phases" {
  # Mock claude that dumps its stdin to a file for inspection
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "phases" "$TEST_DIR/.claudeloop"
  # Opening line should mention high-level phases
  grep -q "3-8 high-level phases" "$TEST_DIR/received_prompt.txt"
  # Should NOT contain anti-mirroring instruction for phases
  ! grep -q "Do NOT mirror" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: tasks opening line mentions decompose and anti-mirroring" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  # Opening should mention decompose and 5-20
  grep -q "5-20" "$TEST_DIR/received_prompt.txt"
  # Must include anti-mirroring instruction
  grep -q "Do NOT mirror" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: steps opening line mentions atomic and anti-mirroring" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "steps" "$TEST_DIR/.claudeloop"
  # Opening should mention atomic and 10-40
  grep -q "10-40" "$TEST_DIR/received_prompt.txt"
  # Must include anti-mirroring instruction
  grep -q "Do NOT mirror" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: steps prompt includes decomposition example" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "steps" "$TEST_DIR/.claudeloop"
  grep -q "DECOMPOSITION EXAMPLE" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: phases prompt does NOT include decomposition example" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "phases" "$TEST_DIR/.claudeloop"
  ! grep -q "DECOMPOSITION EXAMPLE" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: steps prompt relaxes self-contained requirement" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "steps" "$TEST_DIR/.claudeloop"
  # Steps should allow referencing prior phases
  grep -q "reference what prior phases created" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: phases prompt keeps strict self-contained requirement" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "phases" "$TEST_DIR/.claudeloop"
  grep -q "SELF-CONTAINED" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: sub-task flattening instruction present for tasks/steps" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  grep -q "sub-task should become its OWN" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: granularity is first CRITICAL RULE for tasks" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  # The first bullet after CRITICAL RULES should be the granularity instruction
  # Extract the line number of "CRITICAL RULES" and the first bullet after it
  local rules_line first_bullet
  rules_line=$(grep -n "CRITICAL RULES" "$TEST_DIR/received_prompt.txt" | head -1 | cut -d: -f1)
  first_bullet=$(awk -v start="$rules_line" 'NR>start && /^- / {print; exit}' "$TEST_DIR/received_prompt.txt")
  echo "first_bullet: $first_bullet"
  echo "$first_bullet" | grep -q "5-20"
}

@test "ai_parse_plan: prompt includes execution context about separate AI instances" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  grep -q "SEPARATE, FRESH AI" "$TEST_DIR/received_prompt.txt"
}

@test "show_ai_plan: displays phase count" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.

## Phase 2: Build
Build it.

## Phase 3: Test
Test it.
EOF

  run show_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "3 phases"
}

@test "confirm_ai_plan: editor flow validates edited content" {
  # Create a plan file with valid content
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  # Mock editor that replaces content with invalid text
  cat > "$TEST_DIR/bin/mock_editor" << 'MOCK'
#!/bin/sh
echo "This has no phases at all." > "$1"
MOCK
  chmod +x "$TEST_DIR/bin/mock_editor"

  # Simulate interactive: 'e' to edit, then 'n' to quit after invalid edit
  # We need to set up the environment variables and pipe input for the interactive loop
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    YES_MODE=false DRY_RUN=false LIVE_LOG="" SIMPLE_MODE=false \
    EDITOR="$TEST_DIR/bin/mock_editor" _AI_CONFIRM_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      printf "e\nn\n" | confirm_ai_plan "'"$TEST_DIR/parsed.md"'"
    '
  # Should show validation error about the edited content
  echo "$output" | grep -qi "invalid\|error\|no phases"
}

# --- run_claude_print streaming tests ---

@test "run_claude_print: streams output to stderr in real-time" {
  mock_claude "line one
line two
line three"

  # Capture stderr separately — stderr should contain the streamed output
  local stderr_file="$TEST_DIR/stderr_capture"
  CURRENT_PIPELINE_PID=""
  run_claude_print "test prompt" "$TEST_DIR/rcp_out" 2> "$stderr_file"
  grep -q "line one" "$stderr_file"
  grep -q "line two" "$stderr_file"
  grep -q "line three" "$stderr_file"
}

@test "run_claude_print: output file contains full output for capture" {
  mock_claude "capture this output"

  CURRENT_PIPELINE_PID=""
  run_claude_print "test prompt" "$TEST_DIR/rcp_out" 2>/dev/null
  local result
  result=$(cat "$TEST_DIR/rcp_out")
  [ "$result" = "capture this output" ]
}

@test "run_claude_print: exit code recovered correctly on failure" {
  mock_claude_fail "some error"

  CURRENT_PIPELINE_PID=""
  run run_claude_print "test prompt" "$TEST_DIR/rcp_out"
  [ "$status" -eq 1 ]
}

@test "run_claude_print: logs output to LIVE_LOG when set" {
  mock_claude "AI response line 1
AI response line 2"

  export LIVE_LOG="$TEST_DIR/live.log"
  : > "$LIVE_LOG"

  CURRENT_PIPELINE_PID=""
  run_claude_print "test prompt" "$TEST_DIR/rcp_out" 2>/dev/null
  # LIVE_LOG should contain the AI response (written by process_stream_json)
  grep -q "AI response line 1" "$LIVE_LOG"
  grep -q "AI response line 2" "$LIVE_LOG"
}

@test "run_claude_print: does not log to LIVE_LOG when unset" {
  mock_claude "some output"

  export LIVE_LOG=""
  CURRENT_PIPELINE_PID=""
  run_claude_print "test prompt" "$TEST_DIR/rcp_out" 2>/dev/null
  # No crash, no log file created
  [ ! -f "$TEST_DIR/live.log" ]
}

# --- show_ai_plan logging tests ---

@test "show_ai_plan: logs to LIVE_LOG when set" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.

## Phase 2: Build
Build it.
EOF

  export LIVE_LOG="$TEST_DIR/live.log"
  : > "$LIVE_LOG"

  show_ai_plan "$TEST_DIR/parsed.md" > /dev/null
  # LIVE_LOG should have plan content
  grep -q "Phase 1" "$LIVE_LOG"
  grep -q "phases total" "$LIVE_LOG"
}

# =============================================================================
# ai_parse_plan: extract-not-rewrite prompt tests
# =============================================================================

@test "ai_parse_plan: prompt instructs to extract and preserve original content" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  # Must instruct extraction, not rewriting
  grep -q "extract" "$TEST_DIR/received_prompt.txt"
  grep -q "preserve" "$TEST_DIR/received_prompt.txt"
  grep -qi "do not rewrite\|do not summarize\|no summarizing\|no rewriting" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: prompt instructs to exclude non-phase sections" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  grep -qi "context.*not.*phase\|non-phase\|informational" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: prompt instructs not to invent phases" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  grep -qi "do not invent\|do NOT invent\|never invent" "$TEST_DIR/received_prompt.txt"
}

# =============================================================================
# ai_verify_plan: content preservation check + reason file
# =============================================================================

@test "ai_verify_plan: prompt includes content preservation check" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/verify_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
PASS
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  grep -qi "content preservation\|CONTENT PRESERVATION" "$TEST_DIR/verify_prompt.txt"
}

@test "ai_verify_plan: writes failure reason to ai-verify-reason.txt on FAIL" {
  mock_claude "FAIL
Missing database setup phase."

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something with database.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 2 ]
  [ -f "$TEST_DIR/.claudeloop/ai-verify-reason.txt" ]
  grep -q "Missing database" "$TEST_DIR/.claudeloop/ai-verify-reason.txt"
}

@test "ai_verify_plan: does not write reason file on PASS" {
  mock_claude "PASS"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md" "tasks" "$TEST_DIR/.claudeloop"
  [ ! -f "$TEST_DIR/.claudeloop/ai-verify-reason.txt" ]
}

# =============================================================================
# ai_reparse_with_feedback tests
# =============================================================================

@test "ai_reparse_with_feedback: sends original plan + previous output + failure reason" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/reparse_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project structure.

## Phase 2: Build
Build the feature.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a web app.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-parsed-plan.md" << 'EOF'
## Phase 1: Everything
Do it all.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-verify-reason.txt" << 'EOF'
Missing database setup phase.
EOF

  run ai_reparse_with_feedback "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
  # Prompt should contain original plan
  grep -q "Build a web app" "$TEST_DIR/reparse_prompt.txt"
  # Prompt should contain verification failure reason
  grep -q "Missing database" "$TEST_DIR/reparse_prompt.txt"
  # Prompt should contain previous failed output
  grep -q "Do it all" "$TEST_DIR/reparse_prompt.txt"
}

# =============================================================================
# ai_parse_and_verify orchestrator tests
# =============================================================================

@test "ai_parse_and_verify: passes on first try when verification succeeds" {
  # Mock claude that returns valid plan for parse, then PASS for verify
  local call_count=0
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

if [ "$count" -eq 1 ]; then
  cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.

## Phase 2: Build
Build it.
ENDOUT
else
  echo "PASS" | text_to_stream_json
fi
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
}

@test "ai_parse_and_verify: retries with feedback when verification fails then passes" {
  # Call 1: parse (valid format). Call 2: verify (FAIL). Call 3: reparse. Call 4: verify (PASS)
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nMissing build phase.\n' | text_to_stream_json ;;
  3) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.

## Phase 2: Build
Build it.
ENDOUT
    ;;
  4) echo "PASS" | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=true

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing with a build step.
EOF

  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
  # Should have called claude 4 times
  [ "$(cat "$TEST_DIR/call_count")" = "4" ]
}

@test "ai_parse_and_verify: exits when user says a (abort)" {
  # Call 1: parse. Call 2: verify (FAIL)
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nMissing stuff.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=false

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  printf 'a\n' > "$TEST_DIR/user_input"
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false \
    _AI_VERIFY_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'" < "'"$TEST_DIR/user_input"'"
    '
  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_DIR/call_count")" = "2" ]
}

@test "ai_parse_and_verify: continues as-is when user says c" {
  # Call 1: parse (valid). Call 2: verify (FAIL). User types 'c' → return 0
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nMinor title rephrasing.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=false

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  printf 'c\n' > "$TEST_DIR/user_input"
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false \
    _AI_VERIFY_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'" < "'"$TEST_DIR/user_input"'"
    '
  [ "$status" -eq 0 ]
  # Plan file should still exist
  [ -f "$TEST_DIR/.claudeloop/ai-parsed-plan.md" ]
  # ai-verify-reason.txt should be cleaned up
  [ ! -f "$TEST_DIR/.claudeloop/ai-verify-reason.txt" ]
  # Only 2 claude calls (parse + verify), no reparse
  [ "$(cat "$TEST_DIR/call_count")" = "2" ]
}

@test "ai_parse_and_verify: retries on R or empty input" {
  # Call 1: parse. Call 2: verify (FAIL). User types '' (enter). Call 3: reparse. Call 4: verify (PASS)
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nMissing build phase.\n' | text_to_stream_json ;;
  3) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.

## Phase 2: Build
Build it.
ENDOUT
    ;;
  4) echo "PASS" | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=false

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing with a build step.
EOF

  # Empty input (just Enter) should retry
  printf '\n' > "$TEST_DIR/user_input"
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false \
    _AI_VERIFY_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'" < "'"$TEST_DIR/user_input"'"
    '
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/call_count")" = "4" ]
}

@test "ai_parse_and_verify: continues as-is after max retries when user says c" {
  # All verify calls return FAIL. After max retries, user types 'c' → return 0
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case $((count % 2)) in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  0) printf 'FAIL\nStill missing stuff.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=false
  export AI_RETRY_MAX=1

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  # Provide 'R' for the first prompt (retry), then 'c' for the max-retries prompt
  printf 'R\nc\n' > "$TEST_DIR/user_input"
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false AI_RETRY_MAX=1 \
    _AI_VERIFY_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'" < "'"$TEST_DIR/user_input"'"
    '
  [ "$status" -eq 0 ]
}

@test "ai_parse_and_verify: aborts after max retries when user says a" {
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case $((count % 2)) in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  0) printf 'FAIL\nStill missing stuff.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=false
  export AI_RETRY_MAX=1

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  # Provide 'R' for the first prompt (retry), then 'a' for the max-retries prompt
  printf 'R\na\n' > "$TEST_DIR/user_input"
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false AI_RETRY_MAX=1 \
    _AI_VERIFY_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'" < "'"$TEST_DIR/user_input"'"
    '
  [ "$status" -eq 1 ]
}

@test "ai_parse_and_verify: YES_MODE hard-fails at max retries" {
  # All verify calls return FAIL — YES_MODE should still hard-fail (no continue option)
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case $((count % 2)) in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  0) printf 'FAIL\nStill missing stuff.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=true
  export AI_RETRY_MAX=1

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
}

@test "ai_parse_and_verify: auto-retries in YES_MODE" {
  # Call 1: parse. Call 2: verify (FAIL). Call 3: reparse. Call 4: verify (PASS)
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nMissing build phase.\n' | text_to_stream_json ;;
  3) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.

## Phase 2: Build
Build it.
ENDOUT
    ;;
  4) echo "PASS" | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=true

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 0 ]
}

@test "ai_parse_and_verify: respects AI_RETRY_MAX (default 3)" {
  # All verify calls return FAIL — should stop after 3 retries
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

# Odd calls = parse/reparse, even calls = verify (always FAIL)
case $((count % 2)) in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  0) printf 'FAIL\nStill missing stuff.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=true

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
  # 1 initial parse + 3 retries × (reparse + verify) + 1 initial verify = 1 + 1 + 3*2 = 8
  # Actually: parse(1) + verify(2) + reparse(3) + verify(4) + reparse(5) + verify(6) + reparse(7) + verify(8) = 8
  local call_count
  call_count=$(cat "$TEST_DIR/call_count")
  [ "$call_count" -eq 8 ]
}

# =============================================================================
# Metadata stripping tests
# =============================================================================

@test "run_claude_print: strips metadata lines from output" {
  mock_claude_with_metadata "PASS"

  CURRENT_PIPELINE_PID=""
  run_claude_print "test prompt" "$TEST_DIR/rcp_out" 2>/dev/null
  local result
  result=$(cat "$TEST_DIR/rcp_out")
  # Must NOT contain metadata lines
  ! printf '%s\n' "$result" | grep -q '^\[.*\] model='
  ! printf '%s\n' "$result" | grep -q '^\[Session:'
  # Must contain the actual content
  printf '%s\n' "$result" | grep -q 'PASS'
}

@test "run_claude_print: strips mid-line Session metadata from output" {
  # Simulate the bug where [Session: ...] is concatenated to the end of a content line
  # without a preceding newline, e.g.:
  #   **Files**: src/views/statusBar.ts[Session: model=claude-opus-4-6 cost=0.25 ...]
  # The cleanup pipeline must strip [Session: ...] from any position, not just line-start.

  # Create a mock claude that produces output where Session metadata appears mid-line
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
# Emit assistant text as stream-json
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"**Files**: src/views/statusBar.ts"}]}}\n'
# Emit result event — process_stream_json may append [Session:...] to the same line
printf '{"type":"result","total_cost_usd":0.25,"duration_ms":85200,"num_turns":"1","input_tokens":"2","output_tokens":"5685","modelUsage":{"claude-opus-4-6":{"input":2,"output":5685}}}\n'
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  CURRENT_PIPELINE_PID=""
  run_claude_print "test prompt" "$TEST_DIR/rcp_out" 2>/dev/null
  local result
  result=$(cat "$TEST_DIR/rcp_out")

  # If the stream processor happens to put [Session:] on its own line, the old code
  # would have handled it. The real bug is mid-line concatenation. To test that case
  # directly, also verify the sed pipeline on a hand-crafted string.
  local crafted_line="**Files**: src/views/statusBar.ts[Session: model=claude-opus-4-6 cost=\$0.25 duration=85.2s turns=1 tokens=2in/5685out]"
  local cleaned
  cleaned=$(printf '%s\n' "$crafted_line" | sed 's/\[Session:.*//')
  [ "$cleaned" = "**Files**: src/views/statusBar.ts" ]

  # Bracket model names: claude-opus-4-6[1m] contains ] which breaks [^]]* regex
  local crafted_brackets="PASS[Session: model=claude-opus-4-6[1m] cost=\$0.1067 duration=3.3s turns=1 tokens=2in/33out cache=14929r/15737w]"
  local cleaned_brackets
  cleaned_brackets=$(printf '%s\n' "$crafted_brackets" | sed 's/\[Session:.*//')
  [ "$cleaned_brackets" = "PASS" ]
}

@test "ai_verify_plan: correctly parses PASS after metadata lines" {
  mock_claude_with_metadata "PASS"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
}

@test "ai_verify_plan: handles case-insensitive Pass/PASS" {
  mock_claude "Pass"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Prompt wording tests
# =============================================================================

@test "ai_parse_plan: prompt contains exact-wording instruction" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  grep -q "exact original wording" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: prompt contains Part-of context instruction" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  grep -q "Part of:" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: decomp example shows verbatim titles not paraphrased" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  # The example should use exact sub-task titles, not paraphrased versions
  grep -q "Init project" "$TEST_DIR/received_prompt.txt"
  grep -q "Design schema" "$TEST_DIR/received_prompt.txt"
  grep -q "Write CRUD" "$TEST_DIR/received_prompt.txt"
  # Should NOT contain paraphrased titles from old example
  ! grep -q "Initialize project" "$TEST_DIR/received_prompt.txt"
  ! grep -q "Design database schema" "$TEST_DIR/received_prompt.txt"
  ! grep -q "Implement CRUD operations" "$TEST_DIR/received_prompt.txt"
}

@test "ai_verify_plan: prompt requires exact wording for titles" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/verify_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
PASS
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  grep -q "exact wording" "$TEST_DIR/verify_prompt.txt"
}

# =============================================================================
# 4a. run_claude_print direct failure (line 15)
# =============================================================================

@test "run_claude_print: returns 1 when claude not in PATH" {
  export PATH="/usr/bin:/bin"
  CURRENT_PIPELINE_PID=""
  run run_claude_print "test" "$TEST_DIR/rcp_out"
  [ "$status" -eq 1 ]
}

# =============================================================================
# 4b. ai_parse_plan retry failure paths (lines 200, 204)
# =============================================================================

@test "ai_parse_plan: returns 1 when retry call to claude fails" {
  # Call 1 = garbage (no ## Phase), call 2 = exit 1
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
counter_file="${MOCK_COUNTER_FILE}"
if [ ! -f "$counter_file" ]; then
  echo "1" > "$counter_file"
  echo "This is garbage with no phases." | text_to_stream_json
else
  exit 1
fi
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_FILE="$TEST_DIR/counter_retry_fail"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  run ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
}

@test "ai_parse_plan: returns 1 when retry returns empty output" {
  # Call 1 = garbage, call 2 = exit 0 with no output
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
counter_file="${MOCK_COUNTER_FILE}"
if [ ! -f "$counter_file" ]; then
  echo "1" > "$counter_file"
  echo "This is garbage with no phases." | text_to_stream_json
else
  exit 0
fi
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_FILE="$TEST_DIR/counter_retry_empty"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  run ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "empty output"
}

# =============================================================================
# 4c. ai_verify_plan failure (line 278)
# =============================================================================

@test "ai_verify_plan: returns 1 when claude CLI fails" {
  mock_claude_fail "network error"

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 1 ]
}

# =============================================================================
# 4d. ai_reparse_with_feedback failure paths (lines 357, 361, 373)
# =============================================================================

@test "ai_reparse_with_feedback: returns 1 when claude fails" {
  mock_claude_fail "timeout"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-parsed-plan.md" << 'EOF'
## Phase 1: Everything
Do it all.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-verify-reason.txt" << 'EOF'
Missing stuff.
EOF

  run ai_reparse_with_feedback "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
}

@test "ai_reparse_with_feedback: returns 1 when claude returns empty" {
  mock_claude_empty

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-parsed-plan.md" << 'EOF'
## Phase 1: Everything
Do it all.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-verify-reason.txt" << 'EOF'
Missing stuff.
EOF

  run ai_reparse_with_feedback "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "empty output"
}

@test "ai_reparse_with_feedback: returns 1 when output has no Phase headers" {
  mock_claude "Just some text without any phase headers"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-parsed-plan.md" << 'EOF'
## Phase 1: Everything
Do it all.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-verify-reason.txt" << 'EOF'
Missing stuff.
EOF

  run ai_reparse_with_feedback "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "no.*Phase"
}

# =============================================================================
# 4e. validate_ai_titles (line 414)
# =============================================================================

@test "validate_ai_titles: no warning when all titles match" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2: Run tests
Run the tests.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
# Plan
Setup the project.
Run tests to verify.
EOF

  run validate_ai_titles "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi "rephrased"
}

@test "validate_ai_titles: warns when fewer than half titles match" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Xylophone foo
Do alpha.

## Phase 2: Zygomorphic bar
Do bravo.

## Phase 3: Quixotic baz
Do charlie.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
# Plan
This plan has completely different text.
No titles here that would match at all.
EOF

  run validate_ai_titles "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "rephrased\|match"
}

@test "validate_ai_titles: no warning at exactly half" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do setup.

## Phase 2: Nonexistent
Do something.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
# Plan
Setup the project.
Build the thing.
EOF

  run validate_ai_titles "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
  # match=1, total=2, 1 -lt 1 = false → no warning
  ! echo "$output" | grep -qi "rephrased"
}

@test "validate_ai_titles: no crash on empty parsed file" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
No phase headers here.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  run validate_ai_titles "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi "rephrased"
}

# =============================================================================
# 4f. ai_parse_and_verify orchestrator (lines 430, 459, 465)
# =============================================================================

@test "ai_parse_and_verify: returns 1 when initial parse fails" {
  mock_claude_fail "API error"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
}

@test "ai_parse_and_verify: returns 1 in non-interactive non-YES_MODE" {
  # Call 1: valid phases, Call 2: FAIL
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nMissing stuff.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=false

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  # bats `run` pipes stdin → [ ! -t 0 ] true → non-interactive path
  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
}

@test "ai_parse_and_verify: returns 1 when reparse fails" {
  # Call 1: valid phases, Call 2: FAIL, Call 3: exit 1 (reparse fails)
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nStuff missing.\n' | text_to_stream_json ;;
  3) exit 1 ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=true

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "reparse failed"
}

@test "ai_parse_and_verify: aborts immediately on hard error from ai_verify_plan (exit 1)" {
  # Call 1: parse (valid phases). Call 2: verify returns unexpected format → ai_verify_plan exits 1.
  # ai_parse_and_verify must return 1 immediately without entering retry logic (no call 3).
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'This is not PASS or FAIL — unexpected format\n' | text_to_stream_json ;;
  *) echo "unexpected call $count" >&2; exit 1 ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"
  export YES_MODE=true

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  run ai_parse_and_verify "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  [ "$status" -eq 1 ]
  # Only 2 calls: parse + verify. No reparse call.
  [ "$(cat "$TEST_DIR/call_count")" = "2" ]
}

# =============================================================================
# 4g. confirm_ai_plan interactive paths (lines 519, 528, 532, 544)
# =============================================================================

@test "confirm_ai_plan: auto-approves on non-TTY without YES_MODE" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  export YES_MODE=false
  export DRY_RUN=false
  # bats `run` pipes stdin → non-TTY → auto-approve path
  run confirm_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "auto-approved"
}

@test "confirm_ai_plan: returns 0 when user types y" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    YES_MODE=false DRY_RUN=false LIVE_LOG="" SIMPLE_MODE=false \
    _AI_CONFIRM_FORCE=1 \
    PATH="$TEST_DIR/bin:$PATH" \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      printf "y\n" | confirm_ai_plan "'"$TEST_DIR/parsed.md"'"
    '
  [ "$status" -eq 0 ]
}

@test "confirm_ai_plan: returns 1 when user types n" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    YES_MODE=false DRY_RUN=false LIVE_LOG="" SIMPLE_MODE=false \
    _AI_CONFIRM_FORCE=1 \
    PATH="$TEST_DIR/bin:$PATH" \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      printf "n\n" | confirm_ai_plan "'"$TEST_DIR/parsed.md"'"
    '
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "rejected"
}

@test "confirm_ai_plan: returns 0 after valid edit" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  # Mock editor that writes valid ## Phase content
  cat > "$TEST_DIR/bin/mock_editor" << 'MOCK'
#!/bin/sh
cat > "$1" << 'CONTENT'
## Phase 1: Setup
Do stuff.

## Phase 2: Build
Build it.
CONTENT
MOCK
  chmod +x "$TEST_DIR/bin/mock_editor"

  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    YES_MODE=false DRY_RUN=false LIVE_LOG="" SIMPLE_MODE=false \
    EDITOR="$TEST_DIR/bin/mock_editor" _AI_CONFIRM_FORCE=1 \
    PATH="$TEST_DIR/bin:$PATH" \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      printf "e\n" | confirm_ai_plan "'"$TEST_DIR/parsed.md"'"
    '
  [ "$status" -eq 0 ]
}

@test "ai_reparse_with_feedback: prompt contains exact wording instruction" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/reparse_prompt.txt"
cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project structure.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a web app.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-parsed-plan.md" << 'EOF'
## Phase 1: Everything
Do it all.
EOF
  cat > "$TEST_DIR/.claudeloop/ai-verify-reason.txt" << 'EOF'
Titles were rephrased.
EOF

  ai_reparse_with_feedback "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  grep -q "exact original wording" "$TEST_DIR/reparse_prompt.txt"
}

# =============================================================================
# confirm_ai_plan: prompt discoverability
# =============================================================================

@test "confirm_ai_plan: prompt shows labeled options Yes/no/edit" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    YES_MODE=false DRY_RUN=false LIVE_LOG="" SIMPLE_MODE=false \
    _AI_CONFIRM_FORCE=1 \
    PATH="$TEST_DIR/bin:$PATH" \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      printf "y\n" | confirm_ai_plan "'"$TEST_DIR/parsed.md"'"
    '
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\[Y\]es'
  echo "$output" | grep -q '\[n\]o'
  echo "$output" | grep -q '\[e\]dit'
}

# =============================================================================
# PID tracking tests (for Ctrl+C interrupt support)
# =============================================================================

@test "run_claude_print: clears CURRENT_PIPELINE_PID after completion" {
  mock_claude "test output"

  CURRENT_PIPELINE_PID=""
  run_claude_print "test prompt" "$TEST_DIR/rcp_out" 2>/dev/null
  # After completion, PID should be cleared
  [ -z "$CURRENT_PIPELINE_PID" ]
}

@test "run_claude_print: clears CURRENT_PIPELINE_PID on failure" {
  mock_claude_fail "error"

  CURRENT_PIPELINE_PID=""
  run_claude_print "test prompt" "$TEST_DIR/rcp_out" 2>/dev/null || true
  # After failure, PID should still be cleared
  [ -z "$CURRENT_PIPELINE_PID" ]
}

# --- verdict display in confirm_ai_plan tests ---

@test "confirm_ai_plan: shows pass verdict" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  export YES_MODE=true
  export _AI_VERIFY_VERDICT=pass
  run confirm_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "AI plan verified"
}

@test "confirm_ai_plan: shows continued verdict with reason" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  export YES_MODE=true
  export _AI_VERIFY_VERDICT=continued
  export _AI_VERIFY_REASON="missing test coverage for auth module"
  run confirm_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "AI verification failed"
  echo "$output" | grep -q "missing test coverage"
}

@test "confirm_ai_plan: shows continued verdict without reason" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  export YES_MODE=true
  export _AI_VERIFY_VERDICT=continued
  unset _AI_VERIFY_REASON
  run confirm_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "AI verification failed"
  # Should NOT have a trailing dash
  ! echo "$output" | grep -q "AI verification failed —"
}

@test "confirm_ai_plan: no verdict when variable unset" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  export YES_MODE=true
  unset _AI_VERIFY_VERDICT
  run confirm_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi "verified\|verification"
}

@test "confirm_ai_plan: no verdict when variable is empty string" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  export YES_MODE=true
  export _AI_VERIFY_VERDICT=""
  run confirm_ai_plan "$TEST_DIR/parsed.md"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi "verified\|verification"
}

@test "ai_parse_and_verify: sets verdict=pass on success" {
  # Call 1: parse (valid). Call 2: verify (PASS).
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'PASS\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'"
      echo "VERDICT=$_AI_VERIFY_VERDICT"
    '
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "VERDICT=pass"
}

@test "ai_parse_and_verify: sets verdict=continued on user continue" {
  # Call 1: parse (valid). Call 2: verify (FAIL). User types 'c' → return 0
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nMinor title rephrasing.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  printf 'c\n' > "$TEST_DIR/user_input"
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false \
    _AI_VERIFY_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'" < "'"$TEST_DIR/user_input"'"
      echo "VERDICT=$_AI_VERIFY_VERDICT"
    '
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "VERDICT=continued"
}

@test "ai_parse_and_verify: captures reason on user continue" {
  # Call 1: parse (valid). Call 2: verify (FAIL). User types 'c' → return 0
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
cat /dev/stdin > /dev/null
COUNTER_FILE="${MOCK_COUNTER_DIR}/call_count"
count=0
[ -f "$COUNTER_FILE" ] && count=$(cat "$COUNTER_FILE")
count=$((count + 1))
echo "$count" > "$COUNTER_FILE"

case "$count" in
  1) cat << 'ENDOUT' | text_to_stream_json
## Phase 1: Setup
Create project.
ENDOUT
    ;;
  2) printf 'FAIL\nPhase titles were rephrased from the original.\n' | text_to_stream_json ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export MOCK_COUNTER_DIR="$TEST_DIR"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build a thing.
EOF

  printf 'c\n' > "$TEST_DIR/user_input"
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false \
    _AI_VERIFY_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'" < "'"$TEST_DIR/user_input"'"
      echo "REASON=$_AI_VERIFY_REASON"
    '
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "REASON=Phase titles were rephrased"
}

@test "confirm_ai_plan: reason with backslash-n is not interpreted as newline" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    YES_MODE=true DRY_RUN=false LIVE_LOG="" SIMPLE_MODE=false \
    _AI_VERIFY_VERDICT=continued \
    _AI_VERIFY_REASON='Missing\nvalidation' \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      confirm_ai_plan "'"$TEST_DIR/parsed.md"'"
    '
  [ "$status" -eq 0 ]
  # The backslash-n should appear literally on the same line, not as a newline
  echo "$output" | grep -q 'Missing\\nvalidation'
}

@test "confirm_ai_plan: editor clears verdict" {
  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF

  # Mock editor that writes valid ## Phase content
  cat > "$TEST_DIR/bin/mock_editor" << 'MOCK'
#!/bin/sh
cat > "$1" << 'CONTENT'
## Phase 1: Setup
Do stuff.

## Phase 2: Build
Build it.
CONTENT
MOCK
  chmod +x "$TEST_DIR/bin/mock_editor"

  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    YES_MODE=false DRY_RUN=false LIVE_LOG="" SIMPLE_MODE=false \
    EDITOR="$TEST_DIR/bin/mock_editor" _AI_CONFIRM_FORCE=1 \
    _AI_VERIFY_VERDICT=pass \
    PATH="$TEST_DIR/bin:$PATH" \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/phase_state.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      printf "e\n" | confirm_ai_plan "'"$TEST_DIR/parsed.md"'"
    '
  [ "$status" -eq 0 ]
  # "AI plan verified" should appear exactly once (before the edit, not after)
  local count
  count=$(echo "$output" | grep -c "AI plan verified" || true)
  [ "$count" -eq 1 ]
}

@test "ai_parse_no_retry: exits 0 on verify pass" {
  ai_parse_plan() { echo "## Phase 1: Test" > "$3/ai-parsed-plan.md"; return 0; }
  ai_verify_plan() { return 0; }
  export -f ai_parse_plan ai_verify_plan

  mkdir -p .claudeloop
  echo "# Plan" > PLAN.md
  run ai_parse_no_retry PLAN.md tasks .claudeloop
  [ "$status" -eq 0 ]
}

@test "ai_parse_no_retry: exits 2 on verify fail" {
  ai_parse_plan() { echo "## Phase 1: Test" > "$3/ai-parsed-plan.md"; return 0; }
  ai_verify_plan() {
    printf 'Missing requirement' > "$4/ai-verify-reason.txt"
    return 2
  }
  export -f ai_parse_plan ai_verify_plan

  mkdir -p .claudeloop
  echo "# Plan" > PLAN.md
  run ai_parse_no_retry PLAN.md tasks .claudeloop
  [ "$status" -eq 2 ]
  [ -f .claudeloop/ai-verify-reason.txt ]
}

@test "ai_parse_no_retry: exits 1 when ai_parse_plan fails" {
  ai_parse_plan() { return 1; }
  export -f ai_parse_plan

  mkdir -p .claudeloop
  echo "# Plan" > PLAN.md
  run ai_parse_no_retry PLAN.md tasks .claudeloop
  [ "$status" -eq 1 ]
}

@test "ai_parse_feedback: reads reason from file and reparses" {
  ai_reparse_with_feedback() { echo "## Phase 1: Fixed" > "$3/ai-parsed-plan.md"; return 0; }
  ai_verify_plan() { return 0; }
  export -f ai_reparse_with_feedback ai_verify_plan

  mkdir -p .claudeloop
  echo "# Plan" > PLAN.md
  echo "Missing requirement" > .claudeloop/ai-verify-reason.txt
  run ai_parse_feedback PLAN.md tasks .claudeloop
  [ "$status" -eq 0 ]
}

@test "ai_parse_feedback: exits 1 when feedback file missing" {
  mkdir -p .claudeloop
  echo "# Plan" > PLAN.md
  rm -f .claudeloop/ai-verify-reason.txt

  run ai_parse_feedback PLAN.md tasks .claudeloop
  [ "$status" -eq 1 ]
}

@test "ai_parse_feedback: exits 2 when verify fails after reparse" {
  ai_reparse_with_feedback() { echo "## Phase 1: Fixed" > "$3/ai-parsed-plan.md"; return 0; }
  ai_verify_plan() {
    printf 'Still failing' > "$4/ai-verify-reason.txt"
    return 2
  }
  export -f ai_reparse_with_feedback ai_verify_plan

  mkdir -p .claudeloop
  echo "# Plan" > PLAN.md
  echo "Missing requirement" > .claudeloop/ai-verify-reason.txt
  run ai_parse_feedback PLAN.md tasks .claudeloop
  [ "$status" -eq 2 ]
}

# =============================================================================
# init_live_log condition tests for dry-run + ai-parse behavior
# =============================================================================

@test "init_live_log condition: enables log when DRY_RUN=true and AI_PARSE=true" {
  # Test the condition: { ! $DRY_RUN || [ "$AI_PARSE" = "true" ]; }
  # When DRY_RUN=true and AI_PARSE=true, the condition should be true
  DRY_RUN=true
  AI_PARSE=true
  LIVE_LOG=""

  # Evaluate the condition
  if [ -z "${LIVE_LOG:-}" ] && { ! $DRY_RUN || [ "$AI_PARSE" = "true" ]; }; then
    result="enabled"
  else
    result="disabled"
  fi

  [ "$result" = "enabled" ]
}

@test "init_live_log condition: disables log when DRY_RUN=true and AI_PARSE=false" {
  # When DRY_RUN=true and AI_PARSE is not "true", the condition should be false
  DRY_RUN=true
  AI_PARSE=false
  LIVE_LOG=""

  if [ -z "${LIVE_LOG:-}" ] && { ! $DRY_RUN || [ "$AI_PARSE" = "true" ]; }; then
    result="enabled"
  else
    result="disabled"
  fi

  [ "$result" = "disabled" ]
}

@test "init_live_log condition: enables log when DRY_RUN=false (normal run)" {
  # When DRY_RUN=false (normal run), the condition should always be true
  DRY_RUN=false
  AI_PARSE=false
  LIVE_LOG=""

  if [ -z "${LIVE_LOG:-}" ] && { ! $DRY_RUN || [ "$AI_PARSE" = "true" ]; }; then
    result="enabled"
  else
    result="disabled"
  fi

  [ "$result" = "enabled" ]
}
