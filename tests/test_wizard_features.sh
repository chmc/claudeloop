#!/usr/bin/env bats
# bats file_tags=wizard

# Tests for AI parsing, verify phases, and gitignore management.
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
printf 'PASS\n## Phase 1: Hello\nDo something\n'
printf '{"type":"tool_use","name":"Edit","input":{}}\n'
exit 0
EOF
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"
}

_cl_wizard() {
  local input="$1"; shift
  run sh -c "cd \"$TEST_DIR\" && printf '%s' \"$input\" | BASE_DELAY=0 _WIZARD_FORCE=1 \"$CLAUDELOOP\" $*"
}

# Helper: replace setup()'s pre-baked .gitignore with one that lacks .claudeloop/
_reset_gitignore_without_claudeloop() {
  printf 'node_modules/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "gitignore without claudeloop"
}

# =============================================================================
# AI parsing wizard questions
# =============================================================================

@test "wizard: asks about AI parsing and saves AI_PARSE=true" {
  _cl_wizard $'\n\n\n\n\n\n\ny\n\n\n'
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  grep -q "^AI_PARSE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: asks about granularity and saves GRANULARITY=steps" {
  _cl_wizard $'\n\n\n\n\n\n\ny\nsteps\n\n'
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  grep -q "^GRANULARITY=steps$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: default AI_PARSE=true saved to conf" {
  _cl_wizard $'\n\n\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^AI_PARSE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: skips AI_PARSE prompt when --ai-parse passed via CLI" {
  _cl_wizard $'\n\n\n\n\n\n\n\n\n' --ai-parse
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  [[ "$output" == *"AI parsing: using --ai-parse"* ]]
  grep -q "^AI_PARSE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# Verify phases wizard questions
# =============================================================================

@test "wizard: asks about verify phases and saves VERIFY_PHASES=true" {
  _cl_wizard $'\n\n\n\n\n\n\n\n\ny\n'
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  grep -q "^VERIFY_PHASES=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: skips verify question when --verify passed" {
  _cl_wizard $'\n\n\n\n\n\n\n\n\n' --verify
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  [[ "$output" == *"using --verify"* ]]
  grep -q "^VERIFY_PHASES=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# .gitignore management (non-interactive fallback via write_config)
# =============================================================================

@test "gitignore: auto-adds .claudeloop/ to existing .gitignore (non-interactive)" {
  _reset_gitignore_without_claudeloop
  run sh -c "exec </dev/null; cd '$TEST_DIR' && BASE_DELAY=0 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  grep -qF '.claudeloop' "$TEST_DIR/.gitignore"
}

@test "gitignore: auto-creates .gitignore when none exists (non-interactive)" {
  git -C "$TEST_DIR" rm -q .gitignore
  git -C "$TEST_DIR" commit -q -m "remove gitignore"
  run sh -c "exec </dev/null; cd '$TEST_DIR' && BASE_DELAY=0 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  grep -qF '.claudeloop' "$TEST_DIR/.gitignore"
}

@test "gitignore: no-op when .claudeloop/ already in .gitignore" {
  local before
  before=$(cat "$TEST_DIR/.gitignore")
  run sh -c "exec </dev/null; cd '$TEST_DIR' && BASE_DELAY=0 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/.gitignore")" = "$before" ]
}

# =============================================================================
# Gitignore wizard question + auto-commit
# =============================================================================

@test "wizard: asks gitignore question and modifies .gitignore on Y" {
  _reset_gitignore_without_claudeloop
  _cl_wizard $'\n\n\n\n\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Add .claudeloop/ to .gitignore"* ]]
  grep -qF '.claudeloop/' "$TEST_DIR/.gitignore"
}

@test "wizard: respects N for gitignore question" {
  _reset_gitignore_without_claudeloop
  _cl_wizard $'\n\n\n\n\n\n\n\n\n\n\n'"n"$'\n'
  [[ "$output" == *"Add .claudeloop/ to .gitignore"* ]]
  ! grep -qF '.claudeloop' "$TEST_DIR/.gitignore"
}

@test "wizard: gitignore question skipped when .claudeloop already present" {
  _cl_wizard $'\n\n\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Add .claudeloop/ to .gitignore"* ]]
}

@test "wizard: gitignore auto-committed after wizard" {
  _reset_gitignore_without_claudeloop
  _cl_wizard $'\n\n\n\n\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  [ -z "$(git -C "$TEST_DIR" status --porcelain .gitignore)" ]
  git -C "$TEST_DIR" log --oneline -1 -- .gitignore | grep -qF "chore: add .claudeloop/ to .gitignore"
}
