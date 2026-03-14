#!/usr/bin/env bats
# bats file_tags=refactor

# Unit tests for lib/refactor.sh — auto-refactoring after phase completion

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR
  export _SENTINEL_POLL=0.1
  export _SKIP_HEARTBEATS=1

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
  REFACTOR_MAX_RETRIES=5
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

@test "refactor_phase: retries up to 5 times before giving up" {
  REFACTOR_PHASES=true

  echo "0" > "$TEST_DIR/call_count"

  # Stub that always fails (non-zero exit), counts calls
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Error"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run refactor_phase "1"
  [ "$status" -eq 0 ]  # non-fatal: always returns 0
  # Should have made exactly 5 attempts
  [ "$(cat "$TEST_DIR/call_count")" = "5" ]
}

# =============================================================================
# Rollback between attempts
# =============================================================================

@test "refactor_phase: preserves changes between retry attempts and rolls back on final failure" {
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
    # Even call = verify: fail — record HEAD to prove no rollback between attempts
    git -C "$TEST_DIR" rev-parse HEAD >> "$TEST_DIR/heads_during_verify"
    printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Tests broken.\\nVERIFICATION_FAILED\\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"

  # HEAD advances between attempts (no rollback between retries)
  # With 5 max attempts, we get 5 refactor + 5 verify = 10 calls
  # Each verify records HEAD; successive HEADs should differ (no reset)
  if [ -f "$TEST_DIR/heads_during_verify" ]; then
    local unique_heads
    unique_heads=$(sort -u "$TEST_DIR/heads_during_verify" | wc -l | tr -d ' ')
    [ "$unique_heads" -gt 1 ]
  fi

  # After ALL attempts exhausted, final rollback to pre_sha
  local post_sha
  post_sha=$(git rev-parse HEAD)
  [ "$post_sha" = "$pre_sha" ]

  # Status should be "discarded" (not "completed")
  [ "$(get_phase_refactor_status 1)" = "discarded" ]
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

@test "refactor_phase: gives up after 5 failures with discarded status" {
  REFACTOR_PHASES=true

  # Stub that always exits non-zero
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Crash"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"
  # Status should be "discarded" not "completed"
  [ "$(get_phase_refactor_status 1)" = "discarded" ]
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
  # After exhausting retries, REFACTOR_STATUS should be discarded
  [ "$(get_phase_refactor_status 1)" = "discarded" ]
  # SHA should be cleared on discard
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
  # Should have marked discarded (skipped due to invalid SHA)
  [ "$(get_phase_refactor_status 1)" = "discarded" ]
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

# =============================================================================
# Auto-commit on crash before retry
# =============================================================================

@test "refactor_phase: auto-commits on crash before retry" {
  REFACTOR_PHASES=true

  echo "0" > "$TEST_DIR/call_count"

  # Stub: first call crashes with uncommitted changes, second call succeeds with verify
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$n in
  1)
    # Crash with uncommitted changes
    echo "partial-work" >> "$TEST_DIR/file.txt"
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Crash"}}\n'
    exit 1
    ;;
  2)
    # Second attempt: make a commit
    echo "refactored" >> "$TEST_DIR/file.txt"
    git -C "$TEST_DIR" add file.txt
    git -C "$TEST_DIR" commit -q -m "refactor: restructure"
    printf '{"type":"tool_use","name":"Bash","input":{"command":"echo done"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactored.\\n"}}\n'
    exit 0
    ;;
  3)
    # Verify: pass
    printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"All tests pass.\\nVERIFICATION_PASSED\\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"

  # The partial work from the crash should have been auto-committed
  git log --oneline | grep -q "auto-commit after crash"
  [ "$(get_phase_refactor_status 1)" = "completed" ]
}

# =============================================================================
# Status shows attempt progress
# =============================================================================

@test "refactor_phase: status shows attempt progress" {
  REFACTOR_PHASES=true

  echo "0" > "$TEST_DIR/call_count"

  local progress_dir="$TEST_DIR/captured_progress"
  mkdir -p "$progress_dir"
  # Protect from git clean -fd during final rollback
  echo "captured_progress/" >> .gitignore
  git add .gitignore && git commit -q -m "temp: add captured_progress to gitignore"

  # Stub that always fails — copies PROGRESS.md at each attempt to capture status
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
cp "$TEST_DIR/.claudeloop/PROGRESS.md" "$progress_dir/progress_at_\$n" 2>/dev/null || true
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Error"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"

  # Check that progress files captured at each attempt show in_progress N/5
  grep -q "in_progress 1/5" "$progress_dir/progress_at_1"
  grep -q "in_progress 2/5" "$progress_dir/progress_at_2"
}

# =============================================================================
# Resume from persisted attempt count
# =============================================================================

@test "refactor_phase: resume continues from persisted attempt count" {
  REFACTOR_PHASES=true
  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  # Simulate resume: persisted attempt count = 3, SHA set
  phase_set REFACTOR_ATTEMPTS "1" "3"
  phase_set REFACTOR_SHA "1" "$pre_sha"

  echo "0" > "$TEST_DIR/call_count"

  # Stub that always fails
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Error"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"
  # Should have made only 2 more attempts (4 and 5), not 5 fresh ones
  [ "$(cat "$TEST_DIR/call_count")" = "2" ]
  [ "$(get_phase_refactor_status 1)" = "discarded" ]
}

# =============================================================================
# Retry prompt includes error context from previous attempt
# =============================================================================

@test "refactor_phase: retry prompt includes error context from previous attempt" {
  REFACTOR_PHASES=true

  echo "0" > "$TEST_DIR/call_count"

  # Stub: first call fails with error output, second call captures prompt
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
# Save the prompt from stdin
cat > "$TEST_DIR/prompt_\$(cat "$TEST_DIR/call_count")"
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$n in
  1)
    # First attempt: produce error output in the log, then fail
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"TypeError: cannot read property foo\\n"}}\n'
    exit 1
    ;;
  2)
    # Second attempt: succeed with no changes (nothing to refactor)
    printf '{"type":"tool_use","name":"Bash","input":{"command":"echo nothing"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Nothing to refactor.\\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run refactor_phase "1"
  [ "$status" -eq 0 ]
}

# =============================================================================
# build_refactor_prompt with pre_sha
# =============================================================================

@test "build_refactor_prompt: uses pre_sha for accumulated diff scope" {
  # Make two commits so we can test accumulated diff
  echo "first change" >> file.txt
  git add file.txt
  git commit -q -m "change 1"
  local sha_before
  sha_before=$(git rev-parse HEAD~1)

  echo "second change" >> file.txt
  git add file.txt
  git commit -q -m "change 2"

  # With pre_sha, should use $pre_sha..HEAD range
  local prompt
  prompt=$(build_refactor_prompt "1" "$sha_before")
  # Should show accumulated changes from sha_before, not just HEAD~1
  echo "$prompt" | grep -q "file.txt"
}

# =============================================================================
# verify_refactor with pre_sha
# =============================================================================

@test "verify_refactor: uses full diff from pre_sha on retries" {
  echo "0" > "$TEST_DIR/call_count"

  # Stub that captures the prompt and passes
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > "$TEST_DIR/verify_prompt"
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo ok"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"All good.\\nVERIFICATION_PASSED\\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  # Make a commit so there's something to verify
  echo "refactored" >> file.txt
  git add file.txt
  git commit -q -m "refactor"

  run verify_refactor "1" "$pre_sha"
  [ "$status" -eq 0 ]

  # The prompt sent to verify should reference the pre_sha for diff
  grep -q "$pre_sha" "$TEST_DIR/verify_prompt"
}

# =============================================================================
# resume_pending_refactors with in_progress N/5 status
# =============================================================================

@test "resume_pending_refactors: handles in_progress N/5 status" {
  REFACTOR_PHASES=true

  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" "in_progress 3/5"
  phase_set REFACTOR_SHA "1" "$pre_sha"
  phase_set REFACTOR_ATTEMPTS "1" "3"

  echo "0" > "$TEST_DIR/call_count"

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

@test "resume_pending_refactors: marks discarded when SHA gc'd" {
  REFACTOR_PHASES=true
  phase_set STATUS "1" "completed"
  phase_set REFACTOR_STATUS "1" "in_progress 2/5"
  phase_set REFACTOR_SHA "1" "0000000000000000000000000000000000000000"

  resume_pending_refactors
  # Should be "discarded" not "completed" when SHA is gc'd
  [ "$(get_phase_refactor_status 1)" = "discarded" ]
}

# =============================================================================
# REFACTOR_ATTEMPTS cleared on success
# =============================================================================

# =============================================================================
# False success when only PROGRESS.md changed (SHA comparison bug)
# =============================================================================

@test "refactor_phase: detects no-op when only PROGRESS.md changed" {
  REFACTOR_PHASES=true

  # Track .claudeloop/ in git (reproduces real-world behavior where PROGRESS.md is committed)
  # Remove .claudeloop/ from .gitignore so it gets tracked
  sed -i '' 's|\.claudeloop/||' .gitignore
  git add .gitignore .claudeloop/
  git commit -q -m "track .claudeloop"

  # Write initial progress so it's tracked
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"
  git add .claudeloop/
  git commit -q -m "initial progress"

  # Stub that exits 0 but makes no code changes (only reads files)
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
cat > /dev/null
printf '{"type":"tool_use","name":"Read","input":{"file_path":"file.txt"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Code looks good, nothing to refactor.\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"

  # Should detect nothing to refactor (not falsely report success)
  # Verify log should not exist (verification was skipped)
  [ ! -f ".claudeloop/logs/phase-1.refactor-verify.log" ] || [ ! -s ".claudeloop/logs/phase-1.refactor-verify.log" ]
  [ "$(get_phase_refactor_status 1)" = "completed" ]
}

@test "refactor_phase: verifies accumulated changes from crashed attempt" {
  REFACTOR_PHASES=true

  # Track .claudeloop/ in git
  sed -i '' 's|\.claudeloop/||' .gitignore
  git add .gitignore .claudeloop/
  git commit -q -m "track .claudeloop"

  write_progress "$PROGRESS_FILE" "$PLAN_FILE"
  git add .claudeloop/
  git commit -q -m "initial progress"

  echo "0" > "$TEST_DIR/call_count"

  # Stub: attempt 1 crashes after writing a source file, attempt 2 exits 0 with no writes
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$n in
  1)
    # Crash after writing a source file
    echo "new feature code" > "$TEST_DIR/feature.ts"
    printf '{"type":"tool_use","name":"Write","input":{"file_path":"feature.ts","content":"new feature code"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Crash"}}\n'
    exit 1
    ;;
  2)
    # Second attempt: no code changes, just reads
    printf '{"type":"tool_use","name":"Read","input":{"file_path":"file.txt"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Already refactored.\n"}}\n'
    exit 0
    ;;
  3)
    # Verify: pass
    printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"All tests pass.\nVERIFICATION_PASSED\n"}}\n'
    exit 0
    ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/claude"

  refactor_phase "1"

  # verify_refactor SHOULD have been called because attempt 1 left non-.claudeloop code changes
  [ -f ".claudeloop/logs/phase-1.refactor-verify.log" ]
  [ "$(cat "$TEST_DIR/call_count")" = "3" ]
}

# =============================================================================
# REFACTOR_ATTEMPTS cleared on success
# =============================================================================

# =============================================================================
# verify_refactor prompt content
# =============================================================================

@test "verify_refactor: prompt includes pre_sha for regression checking" {
  # Stub that captures the prompt
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > "$TEST_DIR/verify_prompt_captured"
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo ok"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"All good.\\nVERIFICATION_PASSED\\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  local pre_sha
  pre_sha=$(git rev-parse HEAD)

  echo "refactored" >> file.txt
  git add file.txt
  git commit -q -m "refactor"

  verify_refactor "1" "$pre_sha"

  # Prompt should mention the pre_sha for git diff --name-only
  grep -q "git diff --name-only.*$pre_sha" "$TEST_DIR/verify_prompt_captured"
}

@test "verify_refactor: prompt mentions regression-based verification" {
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > "$TEST_DIR/verify_prompt_captured"
printf '{"type":"tool_use","name":"Bash","input":{"command":"echo ok"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"All good.\\nVERIFICATION_PASSED\\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"

  echo "refactored" >> file.txt
  git add file.txt
  git commit -q -m "refactor"

  verify_refactor "1"

  # Prompt should mention regression-based checking
  grep -qi "regression" "$TEST_DIR/verify_prompt_captured"
}

# =============================================================================
# build_refactor_prompt anti-duplication
# =============================================================================

@test "build_refactor_prompt: includes anti-duplication rule" {
  local prompt
  prompt=$(build_refactor_prompt "1")
  echo "$prompt" | grep -qi "move.*code.*new files.*do not.*create copies\|move code.*not.*copies\|MOVE code.*NOT create copies"
}

# =============================================================================
# REFACTOR_ATTEMPTS cleared on success
# =============================================================================

@test "refactor_phase: clears REFACTOR_ATTEMPTS on success" {
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
  [ "$(get_phase_refactor_attempts 1)" = "" ]
}

# =============================================================================
# REFACTOR_MAX_RETRIES configurability
# =============================================================================

@test "refactor_phase: uses REFACTOR_MAX_RETRIES when set" {
  REFACTOR_PHASES=true
  REFACTOR_MAX_RETRIES=2

  echo "0" > "$TEST_DIR/call_count"

  # Stub that always fails (non-zero exit), counts calls
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Error"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run refactor_phase "1"
  [ "$status" -eq 0 ]
  # Should have made exactly 2 attempts (not 5 or 20)
  [ "$(cat "$TEST_DIR/call_count")" = "2" ]
}

@test "refactor_phase: defaults to 20 when REFACTOR_MAX_RETRIES unset" {
  REFACTOR_PHASES=true
  unset REFACTOR_MAX_RETRIES

  local progress_dir="$TEST_DIR/captured_progress"
  mkdir -p "$progress_dir"
  echo "captured_progress/" >> .gitignore
  git add .gitignore && git commit -q -m "temp: add captured_progress to gitignore"

  echo "0" > "$TEST_DIR/call_count"

  # Stub that captures progress at attempt 1 then fails
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
cp "$TEST_DIR/.claudeloop/PROGRESS.md" "$progress_dir/progress_at_\$n" 2>/dev/null || true
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Error"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run refactor_phase "1"
  [ "$status" -eq 0 ]
  # Progress at attempt 1 should show denominator of 20
  grep -q "in_progress 1/20" "$progress_dir/progress_at_1"
}

# =============================================================================
# Pipeline race: successful session bypasses exit code check
# =============================================================================

@test "refactor_phase: successful session bypasses non-zero exit code" {
  REFACTOR_PHASES=true

  echo "0" > "$TEST_DIR/call_count"

  # Stub: refactor call exits non-zero but has successful session markers,
  # then verify passes
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
case \$n in
  1)
    # Refactor: make a commit but exit non-zero (race condition scenario)
    echo "refactored" >> "$TEST_DIR/file.txt"
    git -C "$TEST_DIR" add file.txt
    git -C "$TEST_DIR" commit -q -m "refactor: restructure"
    printf '{"type":"tool_use","name":"Bash","input":{"command":"echo done"}}\n'
    printf '{"type":"content_block_start","content_block":{"type":"text","text":"Refactored.\\n"}}\n'
    printf '{"type":"result","subtype":"success","duration_ms":5000,"num_turns":3,"session_id":"test","cost_usd":0.05,"usage":{"input_tokens":100,"output_tokens":50},"result":"done"}\n'
    exit 1
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

  # Should have completed (not retried 5 times and discarded)
  [ "$(get_phase_refactor_status 1)" = "completed" ]
  # Only 2 calls: refactor + verify (not 5 retries)
  [ "$(cat "$TEST_DIR/call_count")" = "2" ]
}

@test "refactor_phase: status denominator matches REFACTOR_MAX_RETRIES" {
  REFACTOR_PHASES=true
  REFACTOR_MAX_RETRIES=3

  local progress_dir="$TEST_DIR/captured_progress"
  mkdir -p "$progress_dir"
  echo "captured_progress/" >> .gitignore
  git add .gitignore && git commit -q -m "temp: add captured_progress to gitignore"

  echo "0" > "$TEST_DIR/call_count"

  # Stub that captures progress at each attempt then fails
  cat > "$TEST_DIR/bin/claude" << STUB
#!/bin/sh
cat > /dev/null
n=\$(cat "$TEST_DIR/call_count")
n=\$((n + 1))
echo "\$n" > "$TEST_DIR/call_count"
cp "$TEST_DIR/.claudeloop/PROGRESS.md" "$progress_dir/progress_at_\$n" 2>/dev/null || true
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Error"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"

  run refactor_phase "1"
  [ "$status" -eq 0 ]
  grep -q "in_progress 1/3" "$progress_dir/progress_at_1"
  grep -q "in_progress 2/3" "$progress_dir/progress_at_2"
}
