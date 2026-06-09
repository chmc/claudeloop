#!/usr/bin/env bats
# bats file_tags=config

# Tests for --model / --model-verify CLI flags and per-step model resolution

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Test
Do something
EOF
  git -C "$TEST_DIR" add .
  git -C "$TEST_DIR" commit -q -m "init"
}

# ── adapter unit tests (source adapter directly) ─────────────────────────────

@test "_claude_exec_args: no --model flag when MODEL is empty" {
  EFFORT_LEVEL="medium" MODEL="" MODEL_VERIFY=""
  . "$CLAUDELOOP_DIR/lib/adapters/claude.sh"
  result=$(_claude_exec_args)
  [[ "$result" != *"--model"* ]]
}

@test "_claude_exec_args exec: emits --model sonnet when MODEL=sonnet" {
  EFFORT_LEVEL="medium" MODEL="sonnet" MODEL_VERIFY=""
  . "$CLAUDELOOP_DIR/lib/adapters/claude.sh"
  result=$(_claude_exec_args exec)
  [[ "$result" == *"--model sonnet"* ]]
}

@test "_claude_exec_args verify: emits --model opus when MODEL_VERIFY=opus" {
  EFFORT_LEVEL="medium" MODEL="sonnet" MODEL_VERIFY="opus"
  . "$CLAUDELOOP_DIR/lib/adapters/claude.sh"
  result=$(_claude_exec_args verify)
  [[ "$result" == *"--model opus"* ]]
}

@test "_claude_exec_args verify: falls back to MODEL when MODEL_VERIFY is empty" {
  EFFORT_LEVEL="medium" MODEL="sonnet" MODEL_VERIFY=""
  . "$CLAUDELOOP_DIR/lib/adapters/claude.sh"
  result=$(_claude_exec_args verify)
  [[ "$result" == *"--model sonnet"* ]]
}

@test "_claude_exec_args refactor: uses MODEL not MODEL_VERIFY" {
  EFFORT_LEVEL="medium" MODEL="sonnet" MODEL_VERIFY="opus"
  . "$CLAUDELOOP_DIR/lib/adapters/claude.sh"
  result=$(_claude_exec_args refactor)
  [[ "$result" == *"--model sonnet"* ]]
  [[ "$result" != *"--model opus"* ]]
}

@test "_claude_exec_args verify: no --model flag when both MODEL and MODEL_VERIFY empty" {
  EFFORT_LEVEL="medium" MODEL="" MODEL_VERIFY=""
  . "$CLAUDELOOP_DIR/lib/adapters/claude.sh"
  result=$(_claude_exec_args verify)
  [[ "$result" != *"--model"* ]]
}

# ── CLI flag tests ─────────────────────────────────────────────────────────────

@test "--model accepts value and does not crash" {
  run env YES_MODE=true "$CLAUDELOOP_DIR/claudeloop" \
    --plan "$TEST_DIR/PLAN.md" \
    --dry-run \
    --model sonnet \
    --progress "$TEST_DIR/PROGRESS.md" \
    2>/dev/null
  [ "$status" -eq 0 ]
}

@test "--model-verify accepts value and does not crash" {
  run env YES_MODE=true "$CLAUDELOOP_DIR/claudeloop" \
    --plan "$TEST_DIR/PLAN.md" \
    --dry-run \
    --model-verify opus \
    --progress "$TEST_DIR/PROGRESS.md" \
    2>/dev/null
  [ "$status" -eq 0 ]
}

@test "--model requires an argument" {
  run "$CLAUDELOOP_DIR/claudeloop" --model 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"--model requires"* ]]
}

@test "--model-verify requires an argument" {
  run "$CLAUDELOOP_DIR/claudeloop" --model-verify 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"--model-verify requires"* ]]
}

@test "--model accepted alongside --dry-run without error" {
  run env YES_MODE=true "$CLAUDELOOP_DIR/claudeloop" \
    --plan "$TEST_DIR/PLAN.md" \
    --dry-run \
    --model sonnet \
    --progress "$TEST_DIR/PROGRESS.md" \
    2>/dev/null
  [ "$status" -eq 0 ]
}

@test "--model-verify accepted alongside --dry-run without error" {
  run env YES_MODE=true "$CLAUDELOOP_DIR/claudeloop" \
    --plan "$TEST_DIR/PLAN.md" \
    --dry-run \
    --model-verify opus \
    --progress "$TEST_DIR/PROGRESS.md" \
    2>/dev/null
  [ "$status" -eq 0 ]
}

@test "MODEL env var accepted without error" {
  run env MODEL=sonnet YES_MODE=true \
    "$CLAUDELOOP_DIR/claudeloop" --dry-run \
    --plan "$TEST_DIR/PLAN.md" \
    --progress "$TEST_DIR/PROGRESS.md" 2>/dev/null
  [ "$status" -eq 0 ]
}
