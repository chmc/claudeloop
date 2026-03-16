#!/usr/bin/env bash
# bats file_tags=integration

# Integration tests for claudeloop — resume mode, --mark-complete, locks,
# --verify, config helpers, and --phase.
# Split from test_integration_state.sh for parallel execution.

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
  TEST_DIR="$BATS_TEST_TMPDIR"
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

# Helper: write a verify-aware claude stub
_write_verify_claude_stub() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/claude" << EOF
#!/bin/sh
count_file="${dir}/claude_call_count"
count=\$(cat "\$count_file" 2>/dev/null || echo 0)
count=\$((count + 1))
printf '%s\n' "\$count" > "\$count_file"

cat > "${dir}/claude_stdin_\${count}" 2>/dev/null || true

exit_codes_file="${dir}/claude_exit_codes"
exit_code=0
if [ -f "\$exit_codes_file" ]; then
    exit_code=\$(sed -n "\${count}p" "\$exit_codes_file" 2>/dev/null || echo "")
    [ -z "\$exit_code" ] && exit_code=0
fi

is_verify=false
if grep -q "verification agent" "${dir}/claude_stdin_\${count}" 2>/dev/null; then
  is_verify=true
fi

if \$is_verify; then
  printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
  printf '{"type":"content_block_start","content_block":{"type":"text","text":"All tests passed.\nVERIFICATION_PASSED\n"}}\n'
else
  printf 'stub output for call %s\n' "\$count"
  printf '{"type":"tool_use","name":"Edit","input":{}}\n'
fi

exit "\$exit_code"
EOF
  chmod +x "$dir/bin/claude"
}

# =============================================================================
# Resume mode
# =============================================================================

@test "resume_mode: dirty repo with prior completed phase continues non-interactively" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"

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

  printf '\n# prior session change\n' >> "$TEST_DIR/PLAN.md"

  run sh -c "exec </dev/null; unset CLAUDECODE; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 1 ]
}

@test "resume_mode: fresh run without completed phases still exits non-zero when dirty" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
  printf '\n# extra line\n' >> "$TEST_DIR/PLAN.md"

  run sh -c "exec </dev/null; unset CLAUDECODE; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "uncommitted"
}

# =============================================================================
# --mark-complete flag
# =============================================================================

@test "--mark-complete: marks phase as completed, skips it, runs remaining phases" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"

  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --mark-complete 1"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "marked phase 1"
  [ "$(_call_count)" -eq 1 ]
  [ "$(_completed_count)" -eq 2 ]
}

@test "--mark-complete: exits non-zero for phase not in plan" {
  _cl --plan PLAN.md --mark-complete 99
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not found"
}

# =============================================================================
# CLAUDECODE=1 auto yes-mode
# =============================================================================

@test "yes_mode: CLAUDECODE=1 enables yes-mode automatically" {
  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"
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
  echo $$ > "$TEST_DIR/.claudeloop/lock"

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
  [ "$(_call_count)" -eq 4 ]
  [ "$(_completed_count)" -eq 2 ]
}

@test "integration: --verify fails phase when verification fails" {
  _write_verify_claude_stub "$TEST_DIR"
  printf '0\n1\n0\n0\n0\n0\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN.md --verify --max-retries 2
  [ "$status" -eq 0 ]
  [ "$(_completed_count)" -eq 2 ]
}

@test "integration: --verify retry includes verification failure context" {
  _write_verify_claude_stub "$TEST_DIR"
  printf '0\n1\n0\n0\n0\n0\n' > "$TEST_DIR/claude_exit_codes"
  _cl --plan PLAN.md --verify --max-retries 5
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/claude_stdin_3" ]
  grep -q "Previous Attempt Failed" "$TEST_DIR/claude_stdin_3"
}

# =============================================================================
# Bug fix: load_config reads last line without trailing newline
# =============================================================================

@test "integration: load_config reads last line without trailing newline" {
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
  [ -z "$(tail -c 1 "$TEST_DIR/test.conf")" ]
  grep -q "^KEY1=new" "$TEST_DIR/test.conf"
}

# =============================================================================
# --phase N resets completed phases from N onward
# =============================================================================

@test "integration: --phase 2 with phase 2 already completed resets it to pending and runs it" {
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
  _cl --plan PLAN.md --phase 2
  [ "$status" -eq 0 ]
  [ "$(_call_count)" -eq 1 ]
  [ "$(_completed_count)" -eq 2 ]
}
