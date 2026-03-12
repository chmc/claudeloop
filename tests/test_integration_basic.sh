#!/usr/bin/env bash
# bats file_tags=integration

# Integration tests for claudeloop — basic: core execution, arg parsing, lock management, setup_project
# Uses a stub 'claude' binary and a temporary git repo.
# .claudeloop.conf sets BASE_DELAY=0 so retry tests run instantly.

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

# Write the stub claude script into TEST_DIR/bin/
_write_claude_stub() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/claude" << EOF
#!/bin/sh
count_file="${dir}/claude_call_count"
count=\$(cat "\$count_file" 2>/dev/null || echo 0)
count=\$((count + 1))
printf '%s\n' "\$count" > "\$count_file"
exit_codes_file="${dir}/claude_exit_codes"
exit_code=0
if [ -f "\$exit_codes_file" ]; then
    exit_code=\$(sed -n "\${count}p" "\$exit_codes_file" 2>/dev/null || echo "")
    [ -z "\$exit_code" ] && exit_code=0
fi
silent_calls_file="${dir}/claude_silent_calls"
if grep -qx "\$count" "\$silent_calls_file" 2>/dev/null; then
  exit "\$exit_code"
fi
printf 'stub output for call %s\n' "\$count"
printf '{"type":"tool_use","name":"Edit","input":{}}\n'
custom_outputs_file="${dir}/claude_custom_outputs"
if [ -f "\$custom_outputs_file" ]; then
  custom_text=\$(sed -n "\${count}p" "\$custom_outputs_file" 2>/dev/null || echo "")
  [ -n "\$custom_text" ] && printf '%s\n' "\$custom_text"
fi
exit "\$exit_code"
EOF
  chmod +x "$dir/bin/claude"
}

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR
  export CLAUDELOOP="${CLAUDELOOP_DIR}/claudeloop"
  export _SENTINEL_POLL=0.1
  export _SKIP_HEARTBEATS=1

  # Initialize git repo
  git -C "$TEST_DIR" init -q
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test User"

  # Write stub claude
  _write_claude_stub "$TEST_DIR"
  export PATH="$TEST_DIR/bin:$PATH"

  # Default 2-phase plan (no dependencies)
  cat > "$TEST_DIR/PLAN.md" << 'PLAN'
## Phase 1: Setup
Initialize the project

## Phase 2: Build
Build the project
PLAN

  # Config: zero delays for fast tests
  mkdir -p "$TEST_DIR/.claudeloop"
  cat > "$TEST_DIR/.claudeloop/.claudeloop.conf" << 'CONF'
BASE_DELAY=0
AI_PARSE=false
VERIFY_PHASES=false
REFACTOR_PHASES=false
CONF

  git -C "$TEST_DIR" add PLAN.md
  git -C "$TEST_DIR" commit -q -m "initial"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: run claudeloop from TEST_DIR
_cl() {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' $*"
}

# Helper: count completed phases in PROGRESS.md
_completed_count() {
  grep -c "Status: completed" "$TEST_DIR/.claudeloop/PROGRESS.md" 2>/dev/null || echo 0
}

# Helper: get claude call count
_call_count() {
  cat "$TEST_DIR/claude_call_count" 2>/dev/null || echo 0
}

# =============================================================================
# Scenario 1: Happy path
# =============================================================================
@test "integration: happy path exits 0 and all phases completed" {
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.claudeloop/PROGRESS.md" ]
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Scenario 2: Single retry — phase 1 fails once then succeeds
# =============================================================================
@test "integration: phase retried once then succeeds" {
  # Call 1 (phase 1): exit 1  Call 2 (phase 1 retry): exit 0  Call 3 (phase 2): exit 0
  printf '1\n0\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN.md --max-retries 3
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 3 ]
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Scenario 3: Exhaust retries — phase always fails
# =============================================================================
@test "integration: exhausted retries exits non-zero with failed status" {
  # Phase 1 always fails; MAX_RETRIES=2 → 2 attempts then give up
  printf '1\n1\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN.md --max-retries 2
  [ "$status" -ne 0 ]
  grep -q "Status: failed" "$TEST_DIR/.claudeloop/PROGRESS.md"
}

# =============================================================================
# Scenario 4: Dependency blocking — phase 2 blocked when phase 1 fails
# =============================================================================
@test "integration: phase 2 blocked when dependency phase 1 fails" {
  cat > "$TEST_DIR/PLAN_DEP.md" << 'PLAN'
## Phase 1: Setup
Initialize

## Phase 2: Build
Build it
Depends on: Phase 1
PLAN
  git -C "$TEST_DIR" add PLAN_DEP.md
  git -C "$TEST_DIR" commit -q -m "add dep plan"

  # Phase 1 always fails with MAX_RETRIES=1 → 1 attempt only
  printf '1\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN_DEP.md --max-retries 1
  [ "$status" -ne 0 ]
  # Only 1 claude call: phase 1 failed, phase 2 never ran
  [ "$(_call_count)" -eq 1 ]
}

# =============================================================================
# Scenario 5: --reset flag reruns all phases
# =============================================================================
@test "integration: --reset clears prior progress and reruns all phases" {
  # First run: complete everything
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]

  # Reset call counter
  rm -f "$TEST_DIR/claude_call_count"

  # Second run with --reset: should rerun both phases
  _cl --plan PLAN.md --reset
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 2 ]
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Scenario 6: --phase N skip — phases before N marked completed, N runs
# =============================================================================
@test "integration: --phase 2 skips phase 1 and runs only phase 2" {
  _cl --plan PLAN.md --phase 2
  [ "$status" -eq 0 ]
  # Only 1 claude call (phase 2 only)
  [ "$(_call_count)" -eq 1 ]
  # Both phases show as completed in PROGRESS.md
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Scenario 7: Resume from checkpoint (phase 1 already completed in PROGRESS.md)
# =============================================================================
@test "integration: resumes execution skipping already-completed phases" {
  # Write a PROGRESS.md with phase 1 already completed
  mkdir -p "$TEST_DIR/.claudeloop"
  cat > "$TEST_DIR/.claudeloop/PROGRESS.md" << 'PROGRESS'
# Progress for PLAN.md
Last updated: 2026-01-01 00:00:00

## Status Summary
- Total phases: 2
- Completed: 1
- In progress: 0
- Pending: 1
- Failed: 0

## Phase Details

### ✅ Phase 1: Setup
Status: completed
Started: 2026-01-01 00:00:00
Completed: 2026-01-01 00:01:00
Attempts: 1

### ⏳ Phase 2: Build
Status: pending
PROGRESS

  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  # Only 1 claude call: phase 1 was already done
  [ "$(_call_count)" -eq 1 ]
}

# =============================================================================
# Scenario 8: Lock file conflict — exits non-zero with live PID lock
# =============================================================================
@test "integration: rejects second invocation when lock file has live PID" {
  mkdir -p "$TEST_DIR/.claudeloop"
  # Write our own PID: we're definitely alive
  echo $$ > "$TEST_DIR/.claudeloop/lock"

  _cl --plan PLAN.md
  [ "$status" -ne 0 ]
  # No claude calls should have been made
  [ "$(_call_count)" -eq 0 ]
}

# =============================================================================
# Scenario 8b: Stale lock file is removed and run succeeds
# =============================================================================
@test "integration: stale lock file is cleaned up and run succeeds" {
  mkdir -p "$TEST_DIR/.claudeloop"
  # Use a PID that is guaranteed to not be running (max PID + 1 range)
  echo "4194304" > "$TEST_DIR/.claudeloop/lock"

  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
}

# =============================================================================
# Scenario 9: Log files created and non-empty
# =============================================================================
@test "integration: log files are created and non-empty for each phase" {
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.claudeloop/logs/phase-1.log" ]
  [ -s "$TEST_DIR/.claudeloop/logs/phase-1.log" ]
  [ -f "$TEST_DIR/.claudeloop/logs/phase-2.log" ]
  [ -s "$TEST_DIR/.claudeloop/logs/phase-2.log" ]
}

# =============================================================================
# parse_args tests (via subprocess)
# =============================================================================
@test "parse_args: --plan flag is accepted" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --dry-run"
  [ "$status" -eq 0 ]
}

@test "parse_args: --max-retries flag is accepted" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --max-retries 5 --dry-run"
  [ "$status" -eq 0 ]
}

@test "parse_args: --dry-run validates plan without executing claude" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --dry-run"
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 0 ]
}

@test "parse_args: unknown flag exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --unknown-flag 2>&1"
  [ "$status" -ne 0 ]
}

@test "parse_args: --plan without value exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires"* ]] || [[ "$output" == *"argument"* ]]
}

@test "parse_args: --max-retries without value exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --max-retries 2>&1"
  [ "$status" -ne 0 ]
}

@test "parse_args: --phase without value exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --phase 2>&1"
  [ "$status" -ne 0 ]
}

@test "parse_args: --mark-complete without value exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --mark-complete 2>&1"
  [ "$status" -ne 0 ]
}

@test "parse_args: --max-phase-time without value exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --max-phase-time 2>&1"
  [ "$status" -ne 0 ]
}

@test "parse_args: --quota-retry-interval without value exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --quota-retry-interval 2>&1"
  [ "$status" -ne 0 ]
}

@test "parse_args: --phase-prompt without value exits non-zero" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --phase-prompt 2>&1"
  [ "$status" -ne 0 ]
}

# =============================================================================
# create_lock / remove_lock tests (via subprocess)
# =============================================================================
@test "create_lock: live PID lock prevents execution" {
  mkdir -p "$TEST_DIR/.claudeloop"
  echo $$ > "$TEST_DIR/.claudeloop/lock"
  _cl --plan PLAN.md
  [ "$status" -ne 0 ]
}

@test "create_lock: stale PID lock is removed and execution succeeds" {
  mkdir -p "$TEST_DIR/.claudeloop"
  # Use a PID that is guaranteed to not be running (max PID + 1 range)
  echo "4194304" > "$TEST_DIR/.claudeloop/lock"
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
}

# =============================================================================
# Scenario 14: setup_project — .gitignore creation and patching
# =============================================================================

@test "setup_project: creates .gitignore when none exists and user says yes" {
  rm -f "$TEST_DIR/.gitignore"
  # Answer 'y' to "Create .gitignore?" and 'n' to platform prompt
  run sh -c "printf 'y\nn\n' | (cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md)"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.gitignore" ]
  grep -qF '.claudeloop/' "$TEST_DIR/.gitignore"
}

@test "setup_project: non-interactive always creates .gitignore (pipe input ignored)" {
  rm -f "$TEST_DIR/.gitignore"
  # In non-interactive (piped) mode stdin is not a TTY — auto-creates regardless of pipe content
  run sh -c "printf 'n\n' | (cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md)"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.gitignore" ]
  grep -qF '.claudeloop/' "$TEST_DIR/.gitignore"
}

@test "setup_project: patches existing .gitignore missing .claudeloop/" {
  printf '*.log\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  run sh -c "printf 'y\n' | (cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md)"
  [ "$status" -eq 0 ]
  grep -qF '*.log' "$TEST_DIR/.gitignore"
  grep -qF '.claudeloop/' "$TEST_DIR/.gitignore"
}

@test "setup_project: skips prompt when .claudeloop/ already in .gitignore" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  # No stdin input — if it prompts, read will fail and the test will see unexpected behaviour
  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  # .gitignore unchanged (no duplicate entry)
  [ "$(grep -c '.claudeloop' "$TEST_DIR/.gitignore")" -eq 1 ]
}

@test "setup_project: dry-run never creates .gitignore" {
  rm -f "$TEST_DIR/.gitignore"
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --dry-run"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.gitignore" ]
}

@test "setup_project: --yes auto-creates .gitignore without prompting" {
  rm -f "$TEST_DIR/.gitignore"
  # exec </dev/null closes stdin; if code tries to prompt, read gets empty input
  # --yes should bypass prompts entirely
  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --yes"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.gitignore" ]
  grep -qF '.claudeloop/' "$TEST_DIR/.gitignore"
}

@test "setup_project: --yes auto-patches existing .gitignore without prompting" {
  printf '*.log\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --yes"
  [ "$status" -eq 0 ]
  grep -qF '.claudeloop/' "$TEST_DIR/.gitignore"
}

# =============================================================================
# Scenario 15: Stale in_progress (SIGKILL) — phase retried on resume
# =============================================================================
@test "integration: stale in_progress phase from SIGKILL is retried on resume" {
  # Simulate SIGKILL mid-execution: PROGRESS.md left with Phase 1 in_progress
  mkdir -p "$TEST_DIR/.claudeloop"
  cat > "$TEST_DIR/.claudeloop/PROGRESS.md" << 'PROGRESS'
# Progress for PLAN.md
Last updated: 2026-01-01 00:00:00

## Status Summary
- Total phases: 2
- Completed: 0
- In progress: 1
- Pending: 1
- Failed: 0

## Phase Details

### 🔄 Phase 1: Setup
Status: in_progress
Started: 2026-01-01 00:00:00
Attempts: 1

### ⏳ Phase 2: Build
Status: pending
PROGRESS

  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  # Phase 1 must be re-run (was stuck as in_progress), then phase 2 → 2 calls total
  [ "$(_call_count)" -eq 2 ]
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# Resume: header shows correct completed count
# =============================================================================
@test "integration: resume prompt shows interrupted phase title" {
  mkdir -p "$TEST_DIR/.claudeloop/state"
  cat > "$TEST_DIR/.claudeloop/state/current.json" << 'EOF'
{
  "plan_file": "PLAN.md",
  "progress_file": ".claudeloop/PROGRESS.md",
  "current_phase": "2",
  "interrupted": true,
  "timestamp": "2026-01-01T00:00:00Z"
}
EOF
  # Answer N to decline resuming; check phase info appears in the resume prompt block
  run sh -c "cd '$TEST_DIR' && echo 'N' | '$CLAUDELOOP' --plan PLAN.md"
  # "Phase 2: Build" must appear within 2 lines of the "Found interrupted" warning
  echo "$output" | grep -A2 "Found interrupted" | grep -q "Phase 2.*Build"
}

# =============================================================================
# Scenario 17: execution creates non-empty live.log
# =============================================================================
@test "execution creates non-empty live.log" {
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  [ -s "$TEST_DIR/.claudeloop/live.log" ]
  grep -q "Phase 1" "$TEST_DIR/.claudeloop/live.log"
}

# =============================================================================
# Scenario 16: CLAUDECODE env var is stripped before spawning claude
# =============================================================================
@test "integration: CLAUDECODE is unset before spawning claude processes" {
  # Embed TEST_DIR into the stub at write-time so the path is resolved now
  cat > "$TEST_DIR/bin/claude" << EOF
#!/bin/sh
if [ -n "\${CLAUDECODE:-}" ]; then exit 99; fi
count_file="$TEST_DIR/claude_call_count"
count=\$(cat "\$count_file" 2>/dev/null || echo 0)
count=\$((count + 1))
printf '%s\n' "\$count" > "\$count_file"
printf 'stub output for call %s\n' "\$count"
printf '{"type":"tool_use","name":"Edit","input":{}}\n'
exit 0
EOF
  chmod +x "$TEST_DIR/bin/claude"

  CLAUDECODE=1 run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md"
  # If CLAUDECODE leaked into the stub, it would exit 99 and the phase would fail
  [ "$status" -eq 0 ]
  [ "$(_completed_count)" -eq 2 ]
}

@test "integration: initial header shows correct completed count when resuming" {
  # Write a PROGRESS.md with phase 1 already completed
  mkdir -p "$TEST_DIR/.claudeloop"
  cat > "$TEST_DIR/.claudeloop/PROGRESS.md" << 'PROGRESS'
# Progress for PLAN.md
Last updated: 2026-01-01 00:00:00

## Status Summary
- Total phases: 2
- Completed: 1
- In progress: 0
- Pending: 1
- Failed: 0

## Phase Details

### ✅ Phase 1: Setup
Status: completed
Started: 2026-01-01 00:00:00
Completed: 2026-01-01 00:01:00
Attempts: 1

### ⏳ Phase 2: Build
Status: pending
PROGRESS

  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  # The FIRST occurrence of "Progress:" in output must show 1/2, not 0/2
  first_progress=$(echo "$output" | grep "Progress:" | head -1)
  [[ "$first_progress" == *"Progress: 1/2 phases completed"* ]]
}

# =============================================================================
# Checkmark output tests
# =============================================================================
@test "integration: normal run shows checkmark Parsing plan file" {
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  # Output should contain the green-checkmark parsing message
  echo "$output" | grep -q "Parsing plan file"
  echo "$output" | grep "Parsing plan file" | grep -q "✓"
}

@test "integration: dry-run shows checkmark Parsing plan file" {
  _cl --plan PLAN.md --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Parsing plan file"
  echo "$output" | grep "Parsing plan file" | grep -q "✓"
  # Should NOT show "Using cached plan" for a normal parse
  ! echo "$output" | grep -q "Using cached plan"
}
