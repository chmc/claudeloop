#!/usr/bin/env bats
# bats file_tags=wizard

# Tests for wizard default values, custom values, and numeric validation.
# Split from test_wizard.sh for parallel execution.

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  export TEST_DIR
  export CLAUDELOOP="${CLAUDELOOP_DIR}/claudeloop"
  export _SENTINEL_POLL=0.1
  export _SKIP_HEARTBEATS=1

  # Initialize git repo
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test User"

  # Pre-create .gitignore (prevents setup_project from prompting)
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"

  # Create PLAN.md
  cat > "$TEST_DIR/PLAN.md" << 'PLAN'
## Phase 1: Hello
Do something
PLAN

  git -C "$TEST_DIR" add .gitignore PLAN.md
  git -C "$TEST_DIR" commit -q -m "initial"

  # Write stub claude that exits 0 with valid output (supports AI parsing + execution)
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/claude" << 'EOF'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf 'PASS\n## Phase 1: Hello\nDo something\n'
printf '{"type":"tool_use","name":"Edit","input":{}}\n'
exit 0
EOF
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"
}

_cl_wizard() {
  local input="$1"; shift
  run sh -c "cd \"$TEST_DIR\" && printf '%s' \"$input\" | BASE_DELAY=0 _WIZARD_FORCE=1 _CLAUDELOOP_NO_AUTO_ARCHIVE=1 \"$CLAUDELOOP\" $*"
}

# =============================================================================
# Default values — consolidated: one wizard invocation, multiple assertions
# =============================================================================

@test "wizard: default values saved to conf" {
  _cl_wizard $'\n\n\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Welcome to claudeloop!"* ]]
  grep -q "^PLAN_FILE=\.claudeloop/ai-parsed-plan\.md$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
  grep -q "^PROGRESS_FILE=\.claudeloop/PROGRESS\.md$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
  grep -q "^MAX_RETRIES=15$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
  grep -q "^QUOTA_RETRY_INTERVAL=900$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
  grep -q "^SIMPLE_MODE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
  grep -q "^SKIP_PERMISSIONS=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# Custom values
# =============================================================================

@test "wizard: custom MAX_RETRIES=5 saved to conf" {
  _cl_wizard $'\n\n5\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=5$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: MAX_RETRIES=0 accepted and saved" {
  _cl_wizard $'\n\n0\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=0$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: custom QUOTA_RETRY_INTERVAL=1800 saved to conf" {
  _cl_wizard $'\n\n\n1800\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^QUOTA_RETRY_INTERVAL=1800$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: QUOTA_RETRY_INTERVAL=0 accepted and saved" {
  _cl_wizard $'\n\n\n0\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^QUOTA_RETRY_INTERVAL=0$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: SIMPLE_MODE=true accepted and saved" {
  _cl_wizard $'\n\n\n\ny\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: SKIP_PERMISSIONS=true accepted and saved" {
  _cl_wizard $'\n\n\n\n\ny\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SKIP_PERMISSIONS=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: custom PHASE_PROMPT_FILE saved to conf" {
  printf 'Execute phase {{PHASE_NUM}}: {{PHASE_TITLE}}\n{{PHASE_DESCRIPTION}}\n' \
    > "$TEST_DIR/my_prompt.txt"
  _cl_wizard $'\n\n\n\n\n\nmy_prompt.txt\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^PHASE_PROMPT_FILE=my_prompt\.txt$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# Numeric validation — non-digit input silently keeps default
# =============================================================================

@test "wizard: MAX_RETRIES=-1 rejected: keeps default 15" {
  _cl_wizard $'\n\n-1\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=15$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: MAX_RETRIES=abc rejected: keeps default 15" {
  _cl_wizard $'\n\nabc\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=15$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: QUOTA_RETRY_INTERVAL=bad rejected: keeps default 900" {
  _cl_wizard $'\n\n\nbad\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^QUOTA_RETRY_INTERVAL=900$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}
