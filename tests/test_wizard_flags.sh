#!/usr/bin/env bats
# bats file_tags=wizard

# Tests for wizard trigger conditions, boolean input variants, CLI overrides,
# and conf persistence. Split from test_wizard.sh for parallel execution.

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  export TEST_DIR
  export CLAUDELOOP="${CLAUDELOOP_DIR}/claudeloop"
  export _SENTINEL_POLL=0.1
  export _SKIP_HEARTBEATS=1
  export _SENTINEL_MAX_WAIT=30
  export _KILL_ESCALATE_TIMEOUT=1

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
# Trigger conditions
# =============================================================================

@test "wizard: does not run when .claudeloop.conf already exists" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf 'MAX_RETRIES=3\nAI_PARSE=false\n' > "$TEST_DIR/.claudeloop/.claudeloop.conf"
  _cl_wizard $'\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Welcome to claudeloop!"* ]]
}

@test "wizard: does not run during --dry-run" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Welcome to claudeloop!"* ]]
  [ ! -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
}

@test "wizard: does not run when stdin is not a tty; conf still created with defaults" {
  run sh -c "exec </dev/null; cd '$TEST_DIR' && BASE_DELAY=0 _CLAUDELOOP_NO_AUTO_ARCHIVE=1 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Welcome to claudeloop!"* ]]
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
}

@test "wizard: does not run in YES_MODE (-y)" {
  run sh -c "cd '$TEST_DIR' && printf '\n\n\n\n\n\n\n' | BASE_DELAY=0 _WIZARD_FORCE=1 _CLAUDELOOP_NO_AUTO_ARCHIVE=1 '$CLAUDELOOP' --plan PLAN.md -y"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Welcome to claudeloop!"* ]]
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
}

# =============================================================================
# Boolean y/n input variants
# =============================================================================

@test "wizard: yes/Y/Yes accepted as true for SIMPLE_MODE" {
  _cl_wizard $'\n\n\n\nyes\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"

  rm -rf "$TEST_DIR/.claudeloop"
  _cl_wizard $'\n\n\n\nY\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"

  rm -rf "$TEST_DIR/.claudeloop"
  _cl_wizard $'\n\n\n\nYes\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: n/no/N/No accepted as false for SIMPLE_MODE" {
  _cl_wizard $'\n\n\n\nn\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"

  rm -rf "$TEST_DIR/.claudeloop"
  _cl_wizard $'\n\n\n\nno\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"

  rm -rf "$TEST_DIR/.claudeloop"
  _cl_wizard $'\n\n\n\nN\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"

  rm -rf "$TEST_DIR/.claudeloop"
  _cl_wizard $'\n\n\n\nNo\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: literal true/false rejected, keeps default" {
  _cl_wizard $'\n\n\n\ntrue\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"

  rm -rf "$TEST_DIR/.claudeloop"
  _cl_wizard $'\n\n\n\nfalse\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# CLI override skips prompt
# =============================================================================

@test "wizard: --max-retries CLI arg skips MAX_RETRIES prompt" {
  _cl_wizard $'\n\n\n\n\n\n\n\n\n' --max-retries 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"using --max-retries 7"* ]]
  grep -q "^MAX_RETRIES=7$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# Conf persisted before plan file check
# =============================================================================

@test "wizard: conf persisted even when plan file does not exist" {
  _cl_wizard $'NONEXISTENT.md\n\n\n\n\n\n\n\n\n\n'
  [ "$status" -ne 0 ]
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
}
