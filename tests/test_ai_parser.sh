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
  . "${BATS_TEST_DIRNAME}/../lib/ai_parser.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: create a mock claude that outputs given text
mock_claude() {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat << 'ENDOUT'
$1
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"
}

# Helper: create a mock claude that writes to stderr and exits non-zero
mock_claude_fail() {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
echo "$1" >&2
exit 1
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"
}

# Helper: create a mock claude that outputs nothing
mock_claude_empty() {
  cat > "$TEST_DIR/bin/claude" << 'MOCK'
#!/bin/sh
exit 0
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"
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
  export PATH="$TEST_DIR/bin:/usr/bin:/bin"
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
counter_file="/tmp/bats_ai_parser_counter_$$"
# Use parent's counter file if set
counter_file="${MOCK_COUNTER_FILE:-$counter_file}"
if [ ! -f "$counter_file" ]; then
  echo "1" > "$counter_file"
  echo "This is garbage with no phases at all."
else
  cat << 'ENDOUT'
## Phase 1: Setup
Create the project.

## Phase 2: Build
Build it.
ENDOUT
fi
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"
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

  run run_claude_print "test prompt" 120
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "API key expired"
}

# --- granularity tests ---

@test "ai_parse_plan: prompt includes phases granularity instruction" {
  # Mock claude that dumps its stdin to a file for inspection
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT'
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "phases" "$TEST_DIR/.claudeloop"
  grep -q "3-8 high-level phases" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: prompt includes tasks granularity instruction" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT'
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "tasks" "$TEST_DIR/.claudeloop"
  grep -q "5-20 total items" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: prompt includes steps granularity instruction" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT'
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"

  cat > "$TEST_DIR/plan.md" << 'EOF'
Build something.
EOF

  ai_parse_plan "$TEST_DIR/plan.md" "steps" "$TEST_DIR/.claudeloop"
  grep -q "10-40 total items" "$TEST_DIR/received_prompt.txt"
}

@test "ai_parse_plan: prompt includes execution context about separate AI instances" {
  cat > "$TEST_DIR/bin/claude" << MOCK
#!/bin/sh
cat > "$TEST_DIR/received_prompt.txt"
cat << 'ENDOUT'
## Phase 1: Setup
Do stuff.
ENDOUT
MOCK
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"

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
