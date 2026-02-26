#!/usr/bin/env bats
# bats file_tags=wizard

# Tests for the interactive setup wizard (run_setup_wizard).
# The wizard fires only when: no .claudeloop.conf, stdin is a tty or
# _WIZARD_FORCE=1, and --dry-run is not set.
#
# Setup pre-creates and commits .gitignore (with .claudeloop/) and PLAN.md
# so that validate_environment and setup_project never prompt for user input,
# leaving all piped input available for the wizard only.
#
# Input convention: use $'\n\n5\n...' (bash C-string literals) NOT
# "$(printf '\n\n5\n...')" — command substitution strips trailing newlines,
# which breaks the wizard's `read` calls (reads partial last line → EOF → early return).

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR
  export CLAUDELOOP="${CLAUDELOOP_DIR}/claudeloop"

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

  # Write stub claude that exits 0 with output (avoids empty-log check)
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/claude" << 'EOF'
#!/bin/sh
printf 'stub output\n'
exit 0
EOF
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Drive wizard with piped input + _WIZARD_FORCE=1 to bypass [ -t 0 ]
# Usage: _cl_wizard "<input>" [claudeloop args...]
# IMPORTANT: pass input as $'...' literals, NOT "$(printf '...')" — command
# substitution strips trailing newlines, breaking the wizard's read calls.
_cl_wizard() {
  local input="$1"; shift
  run sh -c "cd \"$TEST_DIR\" && printf '%s' \"$input\" | BASE_DELAY=0 MAX_DELAY=0 _WIZARD_FORCE=1 \"$CLAUDELOOP\" $*"
}

# =============================================================================
# Trigger conditions
# =============================================================================

@test "wizard: does not run when .claudeloop.conf already exists" {
  mkdir -p "$TEST_DIR/.claudeloop"
  printf 'MAX_RETRIES=3\n' > "$TEST_DIR/.claudeloop/.claudeloop.conf"
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
  # exec </dev/null ensures stdin is not a tty — wizard should skip
  run sh -c "exec </dev/null; cd '$TEST_DIR' && BASE_DELAY=0 MAX_DELAY=0 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Welcome to claudeloop!"* ]]
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
}

# =============================================================================
# Default values — all 7 prompts answered with Enter (no --plan CLI arg,
# so the plan file prompt IS shown as the first of the 7 prompts)
# =============================================================================

@test "wizard: prints welcome message" {
  _cl_wizard $'\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Welcome to claudeloop!"* ]]
}

@test "wizard: default PLAN_FILE=PLAN.md saved to conf" {
  _cl_wizard $'\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^PLAN_FILE=PLAN\.md$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: default PROGRESS_FILE saved to conf" {
  _cl_wizard $'\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^PROGRESS_FILE=\.claudeloop/PROGRESS\.md$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: default MAX_RETRIES=5 saved to conf" {
  _cl_wizard $'\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=5$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: default QUOTA_RETRY_INTERVAL=900 saved to conf" {
  _cl_wizard $'\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^QUOTA_RETRY_INTERVAL=900$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: default SIMPLE_MODE=false saved to conf" {
  _cl_wizard $'\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: default SKIP_PERMISSIONS=false saved to conf" {
  _cl_wizard $'\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SKIP_PERMISSIONS=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# Custom values
# Prompts in order (no CLI args → all 7 shown):
#   1. Plan file  2. Progress file  3. Max retries  4. Quota interval
#   5. Simple mode  6. Skip permissions  7. Phase prompt file
# =============================================================================

@test "wizard: custom MAX_RETRIES=5 saved to conf" {
  # plan=\n, progress=\n, retries=5, quota=\n, simple=\n, skip=\n, prompt=\n
  _cl_wizard $'\n\n5\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=5$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: MAX_RETRIES=0 accepted and saved" {
  _cl_wizard $'\n\n0\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=0$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: custom QUOTA_RETRY_INTERVAL=1800 saved to conf" {
  # plan=\n, progress=\n, retries=\n, quota=1800, simple=\n, skip=\n, prompt=\n
  _cl_wizard $'\n\n\n1800\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^QUOTA_RETRY_INTERVAL=1800$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: QUOTA_RETRY_INTERVAL=0 accepted and saved" {
  _cl_wizard $'\n\n\n0\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^QUOTA_RETRY_INTERVAL=0$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: SIMPLE_MODE=true accepted and saved" {
  # plan=\n, progress=\n, retries=\n, quota=\n, simple=true, skip=\n, prompt=\n
  _cl_wizard $'\n\n\n\ntrue\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SIMPLE_MODE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: SKIP_PERMISSIONS=true accepted and saved" {
  # plan=\n, progress=\n, retries=\n, quota=\n, simple=\n, skip=true, prompt=\n
  _cl_wizard $'\n\n\n\n\ntrue\n\n'
  [ "$status" -eq 0 ]
  grep -q "^SKIP_PERMISSIONS=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: custom PHASE_PROMPT_FILE saved to conf" {
  # Create a valid prompt file so execute_phase doesn't fail
  printf 'Execute phase {{PHASE_NUM}}: {{PHASE_TITLE}}\n{{PHASE_DESCRIPTION}}\n' \
    > "$TEST_DIR/my_prompt.txt"
  # plan=\n, progress=\n, retries=\n, quota=\n, simple=\n, skip=\n, prompt=my_prompt.txt
  _cl_wizard $'\n\n\n\n\n\nmy_prompt.txt\n'
  [ "$status" -eq 0 ]
  grep -q "^PHASE_PROMPT_FILE=my_prompt\.txt$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# Numeric validation — non-digit input silently keeps default
# =============================================================================

@test "wizard: MAX_RETRIES=-1 rejected: keeps default 5" {
  _cl_wizard $'\n\n-1\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=5$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: MAX_RETRIES=abc rejected: keeps default 5" {
  _cl_wizard $'\n\nabc\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=5$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: QUOTA_RETRY_INTERVAL=bad rejected: keeps default 900" {
  _cl_wizard $'\n\n\nbad\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^QUOTA_RETRY_INTERVAL=900$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# CLI override skips prompt
# With --max-retries 7: retries prompt is skipped → only 6 prompts remain
# =============================================================================

@test "wizard: --max-retries CLI arg skips MAX_RETRIES prompt" {
  # plan=\n, progress=\n, (retries skipped — CLI), quota=\n, simple=\n, skip=\n, prompt=\n
  _cl_wizard $'\n\n\n\n\n\n' --max-retries 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"using --max-retries 7"* ]]
  grep -q "^MAX_RETRIES=7$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# Conf persisted before plan file check
# =============================================================================

@test "wizard: conf persisted even when plan file does not exist" {
  # Enter NONEXISTENT.md at the plan file prompt → wizard sets PLAN_FILE=NONEXISTENT.md
  # write_config runs and creates conf, then plan file check fails → exit non-zero
  _cl_wizard $'NONEXISTENT.md\n\n\n\n\n\n\n'
  [ "$status" -ne 0 ]
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
}

# =============================================================================
# setup_project: .gitignore management
# =============================================================================

# Helper: replace setup()'s pre-baked .gitignore with one that lacks .claudeloop/
# and re-commit so validate_environment sees a clean tree.
_reset_gitignore_without_claudeloop() {
  printf 'node_modules/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "gitignore without claudeloop"
}

@test "setup_project: auto-adds .claudeloop/ to existing .gitignore (non-interactive)" {
  _reset_gitignore_without_claudeloop
  run sh -c "exec </dev/null; cd '$TEST_DIR' && BASE_DELAY=0 MAX_DELAY=0 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  grep -qF '.claudeloop' "$TEST_DIR/.gitignore"
}

@test "setup_project: auto-creates .gitignore when none exists (non-interactive)" {
  git -C "$TEST_DIR" rm -q .gitignore
  git -C "$TEST_DIR" commit -q -m "remove gitignore"
  run sh -c "exec </dev/null; cd '$TEST_DIR' && BASE_DELAY=0 MAX_DELAY=0 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  grep -qF '.claudeloop' "$TEST_DIR/.gitignore"
}

# Regression guard (passes even without the fix — ensures no-op stays a no-op after fix)
@test "setup_project: no-op when .claudeloop/ already in .gitignore" {
  # setup() pre-creates .gitignore with .claudeloop/ — should remain exactly as-is
  local before
  before=$(cat "$TEST_DIR/.gitignore")
  run sh -c "exec </dev/null; cd '$TEST_DIR' && BASE_DELAY=0 MAX_DELAY=0 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/.gitignore")" = "$before" ]
}

# =============================================================================
# AI parsing wizard questions
# Prompts in order (no CLI args → all 9 shown):
#   1. Plan file  2. Progress file  3. Max retries  4. Quota interval
#   5. Simple mode  6. Skip permissions  7. Phase prompt file
#   8. AI parse (true/false)  9. Granularity (phases/tasks/steps)
# =============================================================================

@test "wizard: asks about AI parsing and saves AI_PARSE=true" {
  # 7 defaults + AI_PARSE=true + GRANULARITY=default
  # Exit may be non-zero because AI parsing runs (and fails with stub claude)
  _cl_wizard $'\n\n\n\n\n\n\ntrue\n\n'
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  grep -q "^AI_PARSE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: asks about granularity and saves GRANULARITY=steps" {
  # 7 defaults + AI_PARSE=true + GRANULARITY=steps
  _cl_wizard $'\n\n\n\n\n\n\ntrue\nsteps\n'
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  grep -q "^GRANULARITY=steps$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: default AI_PARSE=false saved to conf" {
  # 8 prompts (AI_PARSE=false, so granularity not asked)
  _cl_wizard $'\n\n\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  grep -q "^AI_PARSE=false$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: skips AI_PARSE prompt when --ai-parse passed via CLI" {
  # With --ai-parse: AI_PARSE prompt is skipped, GRANULARITY prompt shown
  # Exit may be non-zero because AI parsing runs with stub claude
  _cl_wizard $'\n\n\n\n\n\n\n\n' --ai-parse
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  [[ "$output" == *"AI parsing: using --ai-parse"* ]]
  grep -q "^AI_PARSE=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# Verify phases wizard questions
# Prompts in order (no CLI args → all 10 shown):
#   1. Plan file  2. Progress file  3. Max retries  4. Quota interval
#   5. Simple mode  6. Skip permissions  7. Phase prompt file
#   8. AI parse  9. Granularity (only if AI_PARSE=true)  10. Verify phases
# =============================================================================

@test "wizard: asks about verify phases and saves VERIFY_PHASES=true" {
  # 8 defaults (AI_PARSE=false so granularity skipped) + VERIFY_PHASES=true
  # Exit may be non-zero because verification runs (stub lacks tool-call evidence)
  _cl_wizard $'\n\n\n\n\n\n\n\ntrue\n'
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  grep -q "^VERIFY_PHASES=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "wizard: skips verify question when --verify passed" {
  # Exit may be non-zero because verification runs with stub
  _cl_wizard $'\n\n\n\n\n\n\n\n' --verify
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  [[ "$output" == *"using --verify"* ]]
  grep -q "^VERIFY_PHASES=true$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}
