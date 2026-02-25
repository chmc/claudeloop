#!/usr/bin/env bash
# bats file_tags=integration

# Integration tests for claudeloop
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
MAX_DELAY=0
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
  # Create a background process and kill it to get a dead PID
  sh -c 'sleep 100' &
  dead_pid=$!
  kill "$dead_pid" 2>/dev/null || true
  wait "$dead_pid" 2>/dev/null || true
  echo "$dead_pid" > "$TEST_DIR/.claudeloop/lock"

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
  sh -c 'sleep 100' &
  dead_pid=$!
  kill "$dead_pid" 2>/dev/null || true
  wait "$dead_pid" 2>/dev/null || true
  echo "$dead_pid" > "$TEST_DIR/.claudeloop/lock"
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
}

# =============================================================================
# Scenario 10: Quota error does not consume retry slot
# =============================================================================
@test "integration: quota error does not consume retry slot and phase retries" {
  # Call 1 (phase 1): quota error. Call 2 (phase 1 retry): success. Call 3 (phase 2): success.
  printf '1\n0\n0\n' > "$TEST_DIR/claude_exit_codes"
  printf 'rate limit exceeded\n\n\n' > "$TEST_DIR/claude_custom_outputs"

  _cl --plan PLAN.md --max-retries 2 --quota-retry-interval 0
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 3 ]
  [ "$(_completed_count)" -eq 2 ]
  # Attempts counter not consumed: phase 1 shows Attempts: 1
  grep -A5 "Phase 1: Setup" "$TEST_DIR/.claudeloop/PROGRESS.md" | grep -q "Attempts: 1"
}

# =============================================================================
# Scenario 11: Quota errors are independent of max-retries budget
# =============================================================================
@test "integration: quota errors are independent of max-retries budget" {
  # Calls 1+2 are quota errors (don't consume retries). Call 3 is a real error.
  # With max-retries=1, after 1 real failure, phase 1 is abandoned.
  printf '1\n1\n1\n' > "$TEST_DIR/claude_exit_codes"
  printf 'usage limit exceeded\nusage limit exceeded\n\n' > "$TEST_DIR/claude_custom_outputs"

  _cl --plan PLAN.md --max-retries 1 --quota-retry-interval 0
  [ "$status" -ne 0 ]
  [ "$(_call_count)" -eq 3 ]
  grep -q "Status: failed" "$TEST_DIR/.claudeloop/PROGRESS.md"
}

# =============================================================================
# Scenario 12: Empty log treated as failure (stdin closed — non-interactive)
# =============================================================================
@test "integration: empty log causes phase failure with non-zero exit" {
  # Call 1 (phase 1): silent exit 0 → empty response section → should fail
  printf '1\n' > "$TEST_DIR/claude_silent_calls"
  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --max-retries 1"
  [ "$status" -ne 0 ]
  # Log file exists (now always has headers)
  [ -f "$TEST_DIR/.claudeloop/logs/phase-1.log" ]
  grep -q "Status: failed" "$TEST_DIR/.claudeloop/PROGRESS.md"
}

# =============================================================================
# Scenario 13: Permission error in non-TTY mode fails immediately
# =============================================================================
@test "integration: permission error in non-TTY mode fails immediately" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  # Call 1: outputs permission prompt text; exit 0 (permission check reads output)
  printf "write permissions haven't been granted\n" \
    > "$TEST_DIR/claude_custom_outputs"
  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --max-retries 2"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "permission"
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
# write_config: auto-create and auto-update .claudeloop.conf
# =============================================================================

@test "write_config: creates .claudeloop.conf on first run with no args" {
  rm -f "$TEST_DIR/.claudeloop/.claudeloop.conf"
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  grep -q "^PLAN_FILE=" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "write_config: saves CLI-provided settings to new conf" {
  rm -f "$TEST_DIR/.claudeloop/.claudeloop.conf"
  _cl --plan PLAN.md --max-retries 5
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=5$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "write_config: updates existing conf key when CLI arg changes it" {
  printf 'MAX_RETRIES=2\n' >> "$TEST_DIR/.claudeloop/.claudeloop.conf"
  _cl --plan PLAN.md --max-retries 9
  [ "$status" -eq 0 ]
  grep -q "^MAX_RETRIES=9$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
  # Other keys untouched
  grep -q "^BASE_DELAY=0$" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

@test "write_config: does not create or modify conf during --dry-run" {
  rm -f "$TEST_DIR/.claudeloop/.claudeloop.conf"
  _cl --plan PLAN.md --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
}

@test "write_config: does not persist one-time flags like --reset or --phase" {
  rm -f "$TEST_DIR/.claudeloop/.claudeloop.conf"
  _cl --plan PLAN.md --reset
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.claudeloop/.claudeloop.conf" ]
  ! grep -q "RESET" "$TEST_DIR/.claudeloop/.claudeloop.conf"
  ! grep -q "START_PHASE" "$TEST_DIR/.claudeloop/.claudeloop.conf"
}

# =============================================================================
# --version / -V flag
# =============================================================================
@test "--version prints semver string" {
  run "$CLAUDELOOP" --version
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'
}

@test "-V is alias for --version" {
  run "$CLAUDELOOP" -V
  [ "$status" -eq 0 ]
  [ "$output" = "$("$CLAUDELOOP" --version)" ]
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
# YES_MODE / --yes flag
# =============================================================================

@test "yes_mode: --yes skips uncommitted-changes prompt and continues" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  # Modify a tracked file without committing → uncommitted changes
  printf '\n# extra line\n' >> "$TEST_DIR/PLAN.md"

  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --yes"
  [ "$status" -eq 0 ]
  [ "$(_completed_count)" -eq 2 ]
}

@test "yes_mode: non-TTY without --yes exits non-zero when uncommitted changes detected" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  # Modify a tracked file without committing → uncommitted changes
  printf '\n# extra line\n' >> "$TEST_DIR/PLAN.md"

  # Unset CLAUDECODE so YES_MODE is not auto-enabled by the parent environment
  run sh -c "exec </dev/null; unset CLAUDECODE; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "uncommitted"
}

@test "yes_mode: --yes auto-resumes interrupted session without prompting" {
  mkdir -p "$TEST_DIR/.claudeloop/state"
  cat > "$TEST_DIR/.claudeloop/state/current.json" << 'EOF'
{
  "plan_file": "PLAN.md",
  "progress_file": ".claudeloop/PROGRESS.md",
  "current_phase": "1",
  "interrupted": true,
  "timestamp": "2026-01-01T00:00:00Z"
}
EOF
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

  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"

  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --yes"
  [ "$status" -eq 0 ]
  # Only 1 call: phase 1 already completed, phase 2 runs
  [ "$(_call_count)" -eq 1 ]
}

# =============================================================================
# Fix 1: Resume mode — dirty repo with prior completed phase bypasses gate
# =============================================================================

@test "resume_mode: dirty repo with prior completed phase continues non-interactively" {
  # Commit .gitignore so setup_project has nothing to do
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"

  # PROGRESS.md shows Phase 1 already completed
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

  # Make a tracked file dirty — simulates prior session leaving uncommitted changes
  printf '\n# prior session change\n' >> "$TEST_DIR/PLAN.md"

  # Non-interactive, no --yes, no CLAUDECODE: resume mode should bypass the gate
  run sh -c "exec </dev/null; unset CLAUDECODE; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  # Only phase 2 ran (phase 1 was already completed)
  [ "$(_call_count)" -eq 1 ]
}

@test "resume_mode: fresh run without completed phases still exits non-zero when dirty" {
  # No PROGRESS.md — fresh run, RESUME_MODE must remain false
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  printf '\n# extra line\n' >> "$TEST_DIR/PLAN.md"

  run sh -c "exec </dev/null; unset CLAUDECODE; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "uncommitted"
}

# =============================================================================
# Fix 2: --mark-complete flag
# =============================================================================

@test "--mark-complete: marks phase as completed, skips it, runs remaining phases" {
  # Clean repo: no uncommitted changes; stdin closed to prevent any prompts
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"

  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --mark-complete 1"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "marked phase 1"
  # Only phase 2 ran (phase 1 was marked complete before main_loop)
  [ "$(_call_count)" -eq 1 ]
  [ "$(_completed_count)" -eq 2 ]
}

@test "--mark-complete: exits non-zero for phase not in plan" {
  _cl --plan PLAN.md --mark-complete 99
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not found"
}

@test "yes_mode: CLAUDECODE=1 enables yes-mode automatically" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  # Uncommitted changes that would normally error in non-TTY without --yes
  printf '\n# extra line\n' >> "$TEST_DIR/PLAN.md"

  run sh -c "exec </dev/null; cd '$TEST_DIR' && CLAUDECODE=1 '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  [ "$(_completed_count)" -eq 2 ]
}

# =============================================================================
# create_lock: --force tests
# =============================================================================

@test "create_lock: --force kills live lock and succeeds" {
  sh -c 'sleep 99' &
  fake_pid=$!
  mkdir -p "$TEST_DIR/.claudeloop"
  echo "$fake_pid" > "$TEST_DIR/.claudeloop/lock"

  _cl --plan PLAN.md --force --simple
  kill "$fake_pid" 2>/dev/null || true

  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "killing"
  echo "$output" | grep -q "$fake_pid"
}

@test "create_lock: --force does not break stale lock cleanup" {
  # Stale lock: process already dead — --force should still succeed (same as today)
  sh -c 'sleep 99' &
  dead_pid=$!
  kill "$dead_pid" 2>/dev/null || true
  wait "$dead_pid" 2>/dev/null || true
  mkdir -p "$TEST_DIR/.claudeloop"
  echo "$dead_pid" > "$TEST_DIR/.claudeloop/lock"

  _cl --plan PLAN.md --force
  [ "$status" -eq 0 ]
}

@test "create_lock: error message contains --force hint when no flag given" {
  mkdir -p "$TEST_DIR/.claudeloop"
  echo $$ > "$TEST_DIR/.claudeloop/lock"   # own PID = definitely alive

  _cl --plan PLAN.md --simple
  [ "$status" -ne 0 ]
  echo "$output" | grep -q -- "--force"
}

# =============================================================================
# Item 0: MAX_RETRIES default is 5
# =============================================================================
@test "default MAX_RETRIES is 5 (not 3)" {
  # Source retry.sh in a clean env (no MAX_RETRIES set) and verify the default
  result=$(unset MAX_RETRIES; sh -c ". '$CLAUDELOOP_DIR/lib/parser.sh'; . '$CLAUDELOOP_DIR/lib/retry.sh'; printf '%s' \"\$MAX_RETRIES\"")
  [ "$result" = "5" ]
}

# =============================================================================
# Item 1: --max-phase-time flag
# =============================================================================
@test "parse_args: --max-phase-time flag is accepted" {
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --max-phase-time 60 --dry-run"
  [ "$status" -eq 0 ]
}

@test "timeout: phase killed after MAX_PHASE_TIME seconds and retried" {
  # Stub: first call writes output in a loop (simulates stuck agent writing)
  # Writing in a loop ensures SIGPIPE is delivered when the downstream pipe breaks.
  cat > "$TEST_DIR/bin/claude" << EOF
#!/bin/sh
count_file="$TEST_DIR/claude_call_count"
count=\$(cat "\$count_file" 2>/dev/null || echo 0)
count=\$((count + 1))
printf '%s\n' "\$count" > "\$count_file"
if [ "\$count" -eq 1 ]; then
  # Write output every 0.5s so SIGPIPE kills us when the awk pipe breaks
  i=0
  while [ \$i -lt 60 ]; do
    printf 'still running iteration %s\n' "\$i"
    sleep 1
    i=\$((i + 1))
  done
  exit 1
fi
printf 'stub output for call %s\n' "\$count"
exit 0
EOF
  chmod +x "$TEST_DIR/bin/claude"

  _start=$(date '+%s')
  run sh -c "cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --max-retries 2 --max-phase-time 2"
  _end=$(date '+%s')
  _elapsed=$((_end - _start))

  [ "$status" -eq 0 ]
  # Must finish well before the 30s sleep would have ended
  [ "$_elapsed" -lt 15 ]
  # 3 calls: phase1-attempt1 (timeout), phase1-attempt2 (success), phase2 (success)
  [ "$(_call_count)" -eq 3 ]
}

# =============================================================================
# Item 2: Retry context — archive log + prompt injection
# =============================================================================
@test "retry context: archive log created for failed attempt" {
  # Call 1 fails (phase 1 attempt 1), call 2 succeeds (phase 1 attempt 2), call 3 succeeds (phase 2)
  printf '1\n0\n0\n' > "$TEST_DIR/claude_exit_codes"

  _cl --plan PLAN.md --max-retries 2
  [ "$status" -eq 0 ]

  # Archive log for phase 1 attempt 1 must exist
  [ -f "$TEST_DIR/.claudeloop/logs/phase-1.attempt-1.log" ]
}

@test "retry context: previous failure output injected into retry prompt" {
  # Stub: captures stdin (the prompt) to a per-call file, first call outputs error+fails
  cat > "$TEST_DIR/bin/claude" << EOF
#!/bin/sh
count_file="$TEST_DIR/claude_call_count"
count=\$(cat "\$count_file" 2>/dev/null || echo 0)
count=\$((count + 1))
printf '%s\n' "\$count" > "\$count_file"
cat > "$TEST_DIR/claude_prompt_\${count}.txt"
if [ "\$count" -eq 1 ]; then
  printf 'UNIQUE_ERROR_MARKER_XYZ123\n'
  exit 1
fi
printf 'stub output for call %s\n' "\$count"
exit 0
EOF
  chmod +x "$TEST_DIR/bin/claude"

  _cl --plan PLAN.md --max-retries 2
  [ "$status" -eq 0 ]

  # Prompt for call 2 (phase 1 retry) must reference the previous attempt's output
  grep -q "UNIQUE_ERROR_MARKER_XYZ123" "$TEST_DIR/claude_prompt_2.txt"
  # Prompt for call 1 must NOT mention "Previous Attempt Failed"
  ! grep -q "Previous Attempt Failed" "$TEST_DIR/claude_prompt_1.txt"
}

@test "retry context: no archive created on first attempt" {
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  # No attempt-1 archive: phase succeeded on first try
  [ ! -f "$TEST_DIR/.claudeloop/logs/phase-1.attempt-1.log" ]
}

# =============================================================================
# Item 3: live.log rotation
# =============================================================================
@test "live.log rotation: second run creates timestamped archive" {
  # First run
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]
  [ -s "$TEST_DIR/.claudeloop/live.log" ]

  # Second run (reset to re-run all phases)
  _cl --plan PLAN.md --reset
  [ "$status" -eq 0 ]

  # A rotated log file must exist
  rotated_count=$(ls "$TEST_DIR/.claudeloop/live-"*.log 2>/dev/null | wc -l | tr -d ' ')
  [ "$rotated_count" -gt 0 ]
}

@test "live.log rotation: rotated log contains content from first run" {
  # First run: phase 1 output goes into live.log
  _cl --plan PLAN.md
  [ "$status" -eq 0 ]

  # Second run: first run's live.log gets archived
  _cl --plan PLAN.md --reset
  [ "$status" -eq 0 ]

  rotated=$(ls "$TEST_DIR/.claudeloop/live-"*.log 2>/dev/null | head -1)
  [ -n "$rotated" ]
  [ -s "$rotated" ]
}

@test "create_lock: --force re-reads progress (completed phases not re-run)" {
  # Write a progress file with phase 1 already completed
  mkdir -p "$TEST_DIR/.claudeloop"
  cat > "$TEST_DIR/.claudeloop/PROGRESS.md" << 'PROG'
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

### ⏳ Phase 2: Build
Status: pending
PROG

  # Simulate a running instance with a live lock
  sh -c 'sleep 99' &
  fake_pid=$!
  echo "$fake_pid" > "$TEST_DIR/.claudeloop/lock"

  _cl --plan PLAN.md --force
  kill "$fake_pid" 2>/dev/null || true

  [ "$status" -eq 0 ]
  # Only phase 2 should have been executed (not phase 1 again)
  [ "$(_call_count)" -eq 1 ]
}
