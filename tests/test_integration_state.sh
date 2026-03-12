#!/usr/bin/env bash
# bats file_tags=integration

# Integration tests for claudeloop — config, state, --yes mode, resume,
# verification, and --mark-complete tests.
# Extracted from test_integration.sh.

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
printf 'PASS\n## Phase 1: Setup\nInitialize the project\n\n## Phase 2: Build\nBuild the project\n'
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

# Helper: write a verify-aware claude stub that distinguishes execution calls
# from verification calls (detected by "verification agent" in stdin prompt).
# Verification calls emit tool-call evidence and VERIFICATION_PASSED verdict.
_write_verify_claude_stub() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/claude" << EOF
#!/bin/sh
count_file="${dir}/claude_call_count"
count=\$(cat "\$count_file" 2>/dev/null || echo 0)
count=\$((count + 1))
printf '%s\n' "\$count" > "\$count_file"

# Save stdin for prompt assertions
cat > "${dir}/claude_stdin_\${count}" 2>/dev/null || true

exit_codes_file="${dir}/claude_exit_codes"
exit_code=0
if [ -f "\$exit_codes_file" ]; then
    exit_code=\$(sed -n "\${count}p" "\$exit_codes_file" 2>/dev/null || echo "")
    [ -z "\$exit_code" ] && exit_code=0
fi

# Detect verification calls by checking saved stdin for "verification agent" keyword
is_verify=false
if grep -q "verification agent" "${dir}/claude_stdin_\${count}" 2>/dev/null; then
  is_verify=true
fi

if \$is_verify; then
  # Verification call: emit stream-json tool-call evidence + verdict keyword
  printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
  printf '{"type":"content_block_start","content_block":{"type":"text","text":"All tests passed.\nVERIFICATION_PASSED\n"}}\n'
else
  # Execution call: normal stub output
  printf 'stub output for call %s\n' "\$count"
  printf '{"type":"tool_use","name":"Edit","input":{}}\n'
fi

exit "\$exit_code"
EOF
  chmod +x "$dir/bin/claude"
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
  run sh -c "cd '$TEST_DIR' && VERIFY_PHASES=false REFACTOR_PHASES=false '$CLAUDELOOP' --plan PLAN.md --max-retries 5"
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
  run sh -c "cd '$TEST_DIR' && VERIFY_PHASES=false REFACTOR_PHASES=false '$CLAUDELOOP' --plan PLAN.md --reset"
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
# --verify tests
# =============================================================================

@test "integration: --verify runs verification after each phase" {
  _write_verify_claude_stub "$TEST_DIR"
  _cl --plan PLAN.md --verify
  [ "$status" -eq 0 ]
  # 2 phases × 2 calls each (execute + verify) = 4 total
  [ "$(_call_count)" -eq 4 ]
  [ "$(_completed_count)" -eq 2 ]
}

@test "integration: --verify fails phase when verification fails" {
  _write_verify_claude_stub "$TEST_DIR"
  # Call 1: execute phase 1 (exit 0)
  # Call 2: verify phase 1 (exit 1 → verification failure)
  # Call 3: retry execute phase 1 (exit 0)
  # Call 4: verify phase 1 (exit 0 → pass)
  # Call 5: execute phase 2 (exit 0)
  # Call 6: verify phase 2 (exit 0)
  printf '0\n1\n0\n0\n0\n0\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN.md --verify --max-retries 2
  [ "$status" -eq 0 ]
  [ "$(_completed_count)" -eq 2 ]
}

@test "integration: --verify retry includes verification failure context" {
  _write_verify_claude_stub "$TEST_DIR"
  # Call 1: execute phase 1 (exit 0)
  # Call 2: verify phase 1 (exit 1)
  # Call 3: retry execute phase 1 — prompt should contain verify context
  # Call 4: verify phase 1 (exit 0)
  # Call 5: execute phase 2 (exit 0)
  # Call 6: verify phase 2 (exit 0)
  # Use max-retries 5 so attempt 2 still gets full verification (tier 1)
  printf '0\n1\n0\n0\n0\n0\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN.md --verify --max-retries 5
  [ "$status" -eq 0 ]
  # The retry prompt (call 3) must mention the previous attempt failure
  [ -f "$TEST_DIR/claude_stdin_3" ]
  grep -q "Previous Attempt Failed" "$TEST_DIR/claude_stdin_3"
}

# =============================================================================
# Bug fix: load_config reads last line without trailing newline
# =============================================================================

@test "integration: load_config reads last line without trailing newline" {
  # Write conf without trailing newline — AI_PARSE=true is last line
  printf 'BASE_DELAY=0\nAI_PARSE=true' > "$TEST_DIR/.claudeloop/.claudeloop.conf"
  local _parser="${BATS_TEST_DIRNAME}/../lib/parser.sh"
  run sh -c "
    cd '$TEST_DIR'
    AI_PARSE=''
    PLAN_FILE='' PROGRESS_FILE='' MAX_RETRIES='' SIMPLE_MODE=''
    PHASE_PROMPT_FILE='' BASE_DELAY='' QUOTA_RETRY_INTERVAL=''
    SKIP_PERMISSIONS='' STREAM_TRUNCATE_LEN='' HOOKS_ENABLED='' MAX_PHASE_TIME=''
    IDLE_TIMEOUT='' GRANULARITY='' VERIFY_PHASES=''
    . '$_parser'
    . '${BATS_TEST_DIRNAME}/../lib/config.sh'
    load_config
    printf '%s' \"\$AI_PARSE\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# =============================================================================
# Bug fix: update_conf_key ensures trailing newline
# =============================================================================

@test "integration: update_conf_key ensures trailing newline after sed update" {
  . "${BATS_TEST_DIRNAME}/../lib/config.sh"
  printf 'KEY1=old\nKEY2=val2' > "$TEST_DIR/test.conf"
  update_conf_key "$TEST_DIR/test.conf" KEY1 new
  # File must end with newline
  [ -z "$(tail -c 1 "$TEST_DIR/test.conf")" ]
  # Value must be updated
  grep -q "^KEY1=new" "$TEST_DIR/test.conf"
}

# =============================================================================
# Bug fix: --phase N resets completed phases from N onward
# =============================================================================

@test "integration: --phase 2 with phase 2 already completed resets it to pending and runs it" {
  # Simulate a previous run where both phases completed
  mkdir -p "$TEST_DIR/.claudeloop"
  cat > "$TEST_DIR/.claudeloop/PROGRESS.md" << 'PROGRESS'
# Progress for PLAN.md
Last updated: 2026-01-01 00:00:00

## Status Summary
- Total phases: 2
- Completed: 2
- In progress: 0
- Pending: 0
- Failed: 0

## Phase Details

### ✅ Phase 1: Setup
Status: completed
Attempts: 1
Started: 2026-01-01 00:00:00
Completed: 2026-01-01 00:01:00

### ✅ Phase 2: Build
Status: completed
Attempts: 1
Started: 2026-01-01 00:01:00
Completed: 2026-01-01 00:02:00
PROGRESS
  # --phase 2 should reset phase 2 and re-run it
  _cl --plan PLAN.md --phase 2
  [ "$status" -eq 0 ]
  # Phase 2 should have been re-executed (1 claude call)
  [ "$(_call_count)" -eq 1 ]
  [ "$(_completed_count)" -eq 2 ]
}
