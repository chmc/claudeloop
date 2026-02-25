#!/usr/bin/env bash
# bats file_tags=ai_parser

# Test AI Parser Library
# TDD: tests written FIRST

setup() {
  export TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/.claudeloop"
  export LIVE_LOG=""
  export SIMPLE_MODE=false
  . "${BATS_TEST_DIRNAME}/../lib/ui.sh"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
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
  rm -rf "$TEST_DIR"
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

@test "ai_verify_plan: returns 1 when AI says FAIL" {
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
  [ "$status" -eq 1 ]
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

@test "ai_verify_plan: returns 0 with warning on unexpected format" {
  mock_claude "Looks good to me, everything checks out."

  cat > "$TEST_DIR/parsed.md" << 'EOF'
## Phase 1: Setup
Do stuff.
EOF
  cat > "$TEST_DIR/original.md" << 'EOF'
Build something.
EOF

  run ai_verify_plan "$TEST_DIR/parsed.md" "$TEST_DIR/original.md"
  [ "$status" -eq 0 ]
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

  run run_claude_print "test prompt"
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
  run_claude_print "test prompt" > /dev/null 2> "$stderr_file"
  grep -q "line one" "$stderr_file"
  grep -q "line two" "$stderr_file"
  grep -q "line three" "$stderr_file"
}

@test "run_claude_print: stdout still returns full output for capture" {
  mock_claude "capture this output"

  local result
  result=$(run_claude_print "test prompt" 2>/dev/null)
  [ "$result" = "capture this output" ]
}

@test "run_claude_print: exit code recovered correctly on failure" {
  mock_claude_fail "some error"

  run run_claude_print "test prompt"
  [ "$status" -eq 1 ]
}

@test "run_claude_print: logs output to LIVE_LOG when set" {
  mock_claude "AI response line 1
AI response line 2"

  export LIVE_LOG="$TEST_DIR/live.log"
  : > "$LIVE_LOG"

  run_claude_print "test prompt" > /dev/null 2>/dev/null
  # LIVE_LOG should contain the AI response (written by process_stream_json)
  grep -q "AI response line 1" "$LIVE_LOG"
  grep -q "AI response line 2" "$LIVE_LOG"
}

@test "run_claude_print: does not log to LIVE_LOG when unset" {
  mock_claude "some output"

  export LIVE_LOG=""
  run_claude_print "test prompt" > /dev/null 2>/dev/null
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
  [ "$status" -eq 1 ]
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

@test "ai_parse_and_verify: exits when user says n" {
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

  # Pipe "n" for the retry prompt
  local script_dir="${BATS_TEST_DIRNAME}/.."
  run env \
    LIVE_LOG="" SIMPLE_MODE=false MOCK_COUNTER_DIR="$TEST_DIR" \
    PATH="$TEST_DIR/bin:$PATH" YES_MODE=false \
    _AI_VERIFY_FORCE=1 \
    sh -c '
      . "'"$script_dir"'/lib/ui.sh"
      . "'"$script_dir"'/lib/parser.sh"
      . "'"$script_dir"'/lib/stream_processor.sh"
      . "'"$script_dir"'/lib/ai_parser.sh"
      printf "n\n" | ai_parse_and_verify "'"$TEST_DIR/plan.md"'" "tasks" "'"$TEST_DIR/.claudeloop"'"
    '
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
