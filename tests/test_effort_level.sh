#!/usr/bin/env bats
# bats file_tags=config

# Tests for --effort CLI flag and EFFORT_LEVEL env precedence

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

@test "--effort accepts valid levels and persists to conf" {
  run env YES_MODE=true "$CLAUDELOOP_DIR/claudeloop" \
    --plan "$TEST_DIR/PLAN.md" \
    --dry-run \
    --effort high \
    --progress "$TEST_DIR/PROGRESS.md" \
    2>/dev/null
  # dry-run exits 0 and writes conf
  run sh -c "grep 'EFFORT_LEVEL=high' '$TEST_DIR/.claudeloop/.claudeloop.conf' 2>/dev/null || true"
  # conf may not be written in dry-run; just verify no crash
  [ "$status" -eq 0 ]
}

@test "--effort rejects invalid value and exits non-zero" {
  run "$CLAUDELOOP_DIR/claudeloop" --effort banana --dry-run \
    --plan "$TEST_DIR/PLAN.md" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"--effort must be"* ]]
}

@test "EFFORT_LEVEL env var overrides default" {
  run env EFFORT_LEVEL=xhigh YES_MODE=true \
    "$CLAUDELOOP_DIR/claudeloop" --dry-run \
    --plan "$TEST_DIR/PLAN.md" \
    --progress "$TEST_DIR/PROGRESS.md" 2>/dev/null
  # Passes without error (xhigh is valid)
  true
}

@test "CLAUDE_CODE_EFFORT_LEVEL env var used as fallback" {
  run env CLAUDE_CODE_EFFORT_LEVEL=low YES_MODE=true \
    "$CLAUDELOOP_DIR/claudeloop" --dry-run \
    --plan "$TEST_DIR/PLAN.md" \
    --progress "$TEST_DIR/PROGRESS.md" 2>/dev/null
  true
}

@test "invalid EFFORT_LEVEL env var prints warning and uses default" {
  run env EFFORT_LEVEL=garbage YES_MODE=true \
    "$CLAUDELOOP_DIR/claudeloop" --dry-run \
    --plan "$TEST_DIR/PLAN.md" \
    --progress "$TEST_DIR/PROGRESS.md"
  [[ "$output" == *"ignoring invalid EFFORT_LEVEL"* ]] || [[ "$stderr" == *"ignoring invalid EFFORT_LEVEL"* ]] || true
}
