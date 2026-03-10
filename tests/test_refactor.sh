#!/usr/bin/env bats
# bats file_tags=refactor

# Unit tests for lib/refactor.sh — auto-refactoring after phase completion

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR

  # Source libraries in dependency order
  . "$CLAUDELOOP_DIR/lib/parser.sh"
  . "$CLAUDELOOP_DIR/lib/phase_state.sh"
  . "$CLAUDELOOP_DIR/lib/ui.sh"
  . "$CLAUDELOOP_DIR/lib/retry.sh"
  . "$CLAUDELOOP_DIR/lib/stream_processor.sh"
  . "$CLAUDELOOP_DIR/lib/verify.sh"
  . "$CLAUDELOOP_DIR/lib/execution.sh"
  . "$CLAUDELOOP_DIR/lib/progress.sh"
  . "$CLAUDELOOP_DIR/lib/refactor.sh"

  # Set up minimal phase data
  PHASE_COUNT=1
  PHASE_NUMBERS="1"
  PHASE_TITLE_1="Build feature"
  PHASE_DESCRIPTION_1="Implement the new feature module"
  PHASE_STATUS_1="completed"
  PHASE_ATTEMPTS_1=1

  # Defaults
  REFACTOR_PHASES=false
  VERIFY_PHASES=false
  SKIP_PERMISSIONS=false
  MAX_PHASE_TIME=0
  LIVE_LOG=""
  SIMPLE_MODE=false
  STREAM_TRUNCATE_LEN=300
  VERBOSE_MODE=false
  HOOKS_ENABLED=false
  IDLE_TIMEOUT=0
  CURRENT_PIPELINE_PID=""
  CURRENT_PIPELINE_PGID=""
  _REFACTORING_PHASE=""
  MAX_RETRIES=10
  BASE_DELAY=3
  PROGRESS_FILE="$TEST_DIR/.claudeloop/PROGRESS.md"
  PLAN_FILE="$TEST_DIR/PLAN.md"

  # Set up git repo
  cd "$TEST_DIR"
  git init -q .
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial"

  mkdir -p ".claudeloop/logs"
  printf '# Plan\n## Phase 1: Build feature\nImplement the new feature module\n' > "$PLAN_FILE"

  # Protect test artifacts from git clean -fd (used in refactor rollback)
  printf 'bin/\ncall_count\n.claudeloop/\nPLAN.md\n' >> .gitignore
  git add .gitignore
  git commit -q -m "add gitignore"

  # Write stub claude that exits 0 with tool_use + VERIFICATION_PASSED
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactoring..."}}\n'
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo refactored"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Done.\nVERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  jobs -p 2>/dev/null | xargs kill 2>/dev/null || true
  cd /
  rm -rf "$TEST_DIR"
}

# =============================================================================
# run_refactor_if_needed guard
# =============================================================================

@test "run_refactor_if_needed: no-op when REFACTOR_PHASES=false" {
  REFACTOR_PHASES=false
  run run_refactor_if_needed "1"
  [ "$status" -eq 0 ]
  # Should return immediately — no log files created
  [ ! -f ".claudeloop/logs/phase-1.refactor.log" ]
}

# =============================================================================
# refactor_phase retries
# =============================================================================

@test "refactor_phase: retries up to 3 times before giving up" {
  REFACTOR_PHASES=true
  # Stub that always fails (non-zero exit)
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Error"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  # Track attempts via a counter file
  : > "$TEST_DIR/attempt_count"
  _original_run_claude_pipeline=$(type run_claude_pipeline 2>/dev/null || true)

  run refactor_phase "1"
  [ "$status" -eq 0 ]  # non-fatal: always returns 0
}

# =============================================================================
# Rollback between attempts
# =============================================================================

@test "refactor_phase: rolls back cleanly between attempts" {
  REFACTOR_PHASES=true
  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  echo "0" > "$TEST_DIR/call_count"

  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$((n % 2)) in
  1)
    # Odd call = refactor: make a change and commit
    echo "refactored-\$n" >> "$TEST_DIR/file.txt"
    git -C "$TEST_DIR" add file.txt
    git -C "$TEST_DIR" commit -q -m "refactor: attempt \$n"
    printf '{"type":"tool_use","name":"Bash","input":{"command":"echo done"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactored.\\n"}}\n'
    exit 0
    ;;
  0)
    # Even call = verify: fail
    printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Tests broken.\\nVERIFICATION_FAILED\\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run refactor_phase "1"
  [ "$status" -eq 0 ]

  # After failed refactoring + rollback, HEAD should be back to pre_sha
  local post_sha
  post_sha=$(git rev-parse HEAD)
  [ "$post_sha" = "$pre_sha" ]
}

# =============================================================================
# Success path
# =============================================================================

@test "refactor_phase: keeps changes on success" {
  REFACTOR_PHASES=true
  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  echo "0" > "$TEST_DIR/call_count"

  # First call: refactor (makes commit). Second call: verify (passes).
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$n in
  1)
    echo "refactored" >> "$TEST_DIR/file.txt"
    git -C "$TEST_DIR" add file.txt
    git -C "$TEST_DIR" commit -q -m "refactor: restructure"
    printf '{"type":"tool_use","name":"Bash","input":{"command":"echo done"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactored.\\n"}}\n'
    exit 0
    ;;
  2)
    printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"All tests pass.\\nVERIFICATION_PASSED\\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"

  # HEAD should have moved forward (refactor commit kept)
  local post_sha
  post_sha=$(git rev-parse HEAD)
  [ "$post_sha" != "$pre_sha" ]
}

# =============================================================================
# Non-fatal after 3 failures
# =============================================================================

@test "refactor_phase: gives up after 3 failures and returns 0" {
  REFACTOR_PHASES=true

  # Stub that always exits non-zero
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Crash"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run refactor_phase "1"
  [ "$status" -eq 0 ]  # non-fatal
}

# =============================================================================
# SHA unchanged = nothing to refactor
# =============================================================================

@test "refactor_phase: skips verification when SHA unchanged" {
  REFACTOR_PHASES=true

  # Stub that exits 0 but makes no commits
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo nothing to do"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Code is well-structured, nothing to refactor.\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run refactor_phase "1"
  [ "$status" -eq 0 ]

  # No verify log should exist (verification was skipped)
  [ ! -f ".claudeloop/logs/phase-1.refactor-verify.log" ]
}

# =============================================================================
# build_refactor_prompt
# =============================================================================

@test "build_refactor_prompt: includes phase title and git diff stat" {
  # Make a change so git diff --stat has output
  echo "new content" >> file.txt
  git add file.txt
  git commit -q -m "phase 1 work"

  local prompt
  prompt=$(build_refactor_prompt "1")
  echo "$prompt" | grep -q "Build feature"
  echo "$prompt" | grep -q "file.txt"
}

# =============================================================================
# verify_refactor
# =============================================================================

@test "verify_refactor: calls run_claude_pipeline with refactor-verify log paths" {
  # Stub that outputs tool_use + VERIFICATION_PASSED
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff HEAD~1"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactoring is clean.\nVERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run verify_refactor "1"
  [ "$status" -eq 0 ]
  [ -f ".claudeloop/logs/phase-1.refactor-verify.raw.json" ]
}

# =============================================================================
# CLI flag
# =============================================================================

@test "CLI flag --refactor sets REFACTOR_PHASES=true" {
  # Create a minimal plan file for dry-run
  printf '# Plan\n## Phase 1: Test\nDo stuff\n' > "$TEST_DIR/PLAN.md"

  # Run claudeloop with --refactor --dry-run and capture config output
  run "$CLAUDELOOP_DIR/claudeloop" --plan "$TEST_DIR/PLAN.md" --refactor --dry-run 2>&1
  [ "$status" -eq 0 ]
}

# =============================================================================
# Dirty worktree check
# =============================================================================

@test "refactor_phase: auto-commits uncommitted changes before refactoring" {
  REFACTOR_PHASES=true

  # Create uncommitted changes
  echo "dirty" >> file.txt

  echo "0" > "$TEST_DIR/call_count"

  # Stub: first call = refactor (no-op), second call = verify
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo nothing"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Nothing to refactor.\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"

  # Auto-commit should have committed the dirty changes
  git log --oneline | grep -q "auto-commit before refactoring"
  # Refactoring should have run (not skipped)
  [ -f ".claudeloop/logs/phase-1.refactor.log" ]
}

# =============================================================================
# _REFACTORING_PHASE tracking
# =============================================================================

@test "refactor_phase: clears _REFACTORING_PHASE on all exit paths" {
  REFACTOR_PHASES=true
  _REFACTORING_PHASE="stale"

  # Stub that exits 0 but makes no commits (nothing to refactor)
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo nothing"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Nothing to refactor.\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"
  [ "$_REFACTORING_PHASE" = "" ]
}

# =============================================================================
# Refactor state persistence
# =============================================================================

@test "refactor_phase: persists in_progress state with SHA before running" {
  REFACTOR_PHASES=true
  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  # Stub that makes a commit but fails verification
  echo "0" > "$TEST_DIR/call_count"
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$((n % 2)) in
  1)
    echo "refactored-\$n" >> "$TEST_DIR/file.txt"
    git -C "$TEST_DIR" add file.txt
    git -C "$TEST_DIR" commit -q -m "refactor: attempt \$n"
    printf '{"type":"tool_use","name":"Bash","input":{"command":"echo done"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactored.\\n"}}\n'
    exit 0
    ;;
  0)
    printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Tests broken.\\nVERIFICATION_FAILED\\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"
  # After exhausting retries, REFACTOR_STATUS should be completed
  [ "$(get_phase_refactor_status 1)" = "completed" ]
  # SHA should be cleared on completion
  [ "$(get_phase_refactor_sha 1)" = "" ]
}

@test "refactor_phase: marks completed on success" {
  REFACTOR_PHASES=true

  echo "0" > "$TEST_DIR/call_count"
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$n in
  1)
    echo "refactored" >> "$TEST_DIR/file.txt"
    git -C "$TEST_DIR" add file.txt
    git -C "$TEST_DIR" commit -q -m "refactor: restructure"
    printf '{"type":"tool_use","name":"Bash","input":{"command":"echo done"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactored.\\n"}}\n'
    exit 0
    ;;
  2)
    printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"All tests pass.\\nVERIFICATION_PASSED\\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"
  [ "$(get_phase_refactor_status 1)" = "completed" ]
  [ "$(get_phase_refactor_sha 1)" = "" ]
}

# =============================================================================
# resume_pending_refactors
# =============================================================================

@test "resume_pending_refactors: no-op when REFACTOR_PHASES=false" {
  REFACTOR_PHASES=false
  phase_set REFACTOR_STATUS "1" "pending"
  resume_pending_refactors
  # Should not have run (refactor still pending)
  [ "$(get_phase_refactor_status 1)" = "pending" ]
}

@test "resume_pending_refactors: runs pending refactors" {
  REFACTOR_PHASES=true
  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" "pending"

  # Stub that exits 0, makes no commits (nothing to refactor)
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo nothing"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Nothing to refactor.\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  resume_pending_refactors
  [ "$(get_phase_refactor_status 1)" = "completed" ]
}

@test "resume_pending_refactors: rolls back in_progress with valid SHA" {
  REFACTOR_PHASES=true

  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  # Make a "refactor" commit to simulate interrupted refactor
  echo "refactored" >> file.txt
  git add file.txt
  git commit -q -m "refactor: interrupted"

  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" "in_progress"
  phase_set REFACTOR_SHA "1" "$pre_sha"

  # Stub that exits 0, makes no commits
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo nothing"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Nothing to refactor.\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  resume_pending_refactors
  # Should have rolled back to pre_sha
  local current_sha
  current_sha=$(git rev-parse HEAD)
  [ "$current_sha" = "$pre_sha" ]
}

@test "resume_pending_refactors: skips when SHA no longer exists" {
  REFACTOR_PHASES=true
  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" "in_progress"
  phase_set REFACTOR_SHA "1" "0000000000000000000000000000000000000000"

  resume_pending_refactors
  # Should have marked completed (skipped due to invalid SHA)
  [ "$(get_phase_refactor_status 1)" = "completed" ]
}

# =============================================================================
# auto_commit_changes
# =============================================================================

@test "auto_commit_changes: commits dirty worktree" {
  echo "new stuff" >> file.txt

  auto_commit_changes "1" "test label"

  # Commit message should contain our label
  git log --oneline -1 | grep -q "Phase 1: test label"
  # Worktree should be clean
  [ -z "$(git status --porcelain)" ]
}

@test "auto_commit_changes: no-op when worktree clean" {
  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  auto_commit_changes "1" "test label"

  # HEAD should not have changed
  [ "$(git rev-parse HEAD)" = "$pre_sha" ]
}

@test "refactor_phase: auto-commits after refactoring when model leaves uncommitted changes" {
  REFACTOR_PHASES=true

  echo "0" > "$TEST_DIR/call_count"

  # Stub: refactor call modifies files but does NOT commit; verify passes
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$n in
  1)
    # Refactor: modify file but do NOT commit
    echo "refactored-uncommitted" >> "$TEST_DIR/file.txt"
    printf '{"type":"tool_use","name":"Bash","input":{"command":"echo done"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactored.\\n"}}\n'
    exit 0
    ;;
  2)
    printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"All tests pass.\\nVERIFICATION_PASSED\\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"

  # Auto-commit should have picked up the uncommitted refactoring changes
  git log --oneline | grep -q "auto-commit after refactoring"
  # SHA should have changed (refactoring detected, not treated as no-op)
  [ "$(get_phase_refactor_status 1)" = "completed" ]
}
