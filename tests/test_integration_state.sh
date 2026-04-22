#!/usr/bin/env bash
# bats file_tags=integration

# Integration tests for claudeloop — config, state, and --yes mode.
# Extracted from test_integration.sh.

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

# Write the stub claude script into TEST_DIR/bin/
_write_claude_stub() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/claude" << EOF
#!/bin/sh
read -r _discard 2>/dev/null || true
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

  export _EXIT_CODE_WAIT=0
  export _SENTINEL_MAX_WAIT=30
  export _KILL_ESCALATE_TIMEOUT=1
  export _CLAUDELOOP_NO_AUTO_ARCHIVE=1

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

@test "completed_run: interrupted state skips resume prompt when all phases done" {
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
Started: 2026-01-01 00:00:00
Completed: 2026-01-01 00:01:00
Attempts: 1

### ✅ Phase 2: Build
Status: completed
Started: 2026-01-01 00:01:00
Completed: 2026-01-01 00:02:00
Attempts: 1
PROGRESS

  printf '.claudeloop/\n' > "$TEST_DIR/.gitignore"
  git -C "$TEST_DIR" add .gitignore
  git -C "$TEST_DIR" commit -q -m "add gitignore"

  # Unset so startup archive detection fires (setup() exports it at line 48)
  unset _CLAUDELOOP_NO_AUTO_ARCHIVE
  run sh -c "exec </dev/null; cd '$TEST_DIR' && '$CLAUDELOOP' --plan PLAN.md --yes"
  local _cl_output="$output"
  local _cl_status="$status"
  [ "$_cl_status" -eq 0 ]
  # Must NOT show interrupted session prompt
  run sh -c 'printf "%s" "$1" | grep -q "Found interrupted session"' _ "$_cl_output"
  [ "$status" -ne 0 ]
  # Must show archive prompt instead
  echo "$_cl_output" | grep -q "Previous run is complete"
}

# =============================================================================
# --replay: regenerate replay.html
# =============================================================================

@test "replay: generates replay.html for active run" {
  # Create minimal PROGRESS.md
  cat > "$TEST_DIR/.claudeloop/PROGRESS.md" << 'PROGRESS'
## Phase 1: Setup
Status: completed
Started: 2026-01-01 00:00:00
Completed: 2026-01-01 00:01:00
Attempts: 1
PROGRESS

  _cl --replay
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Generated .claudeloop/replay.html"
  [ -f "$TEST_DIR/.claudeloop/replay.html" ]
}

@test "replay: errors when no .claudeloop directory" {
  local empty_dir="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty_dir"
  run sh -c "cd '$empty_dir' && '$CLAUDELOOP' --replay"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "No .claudeloop directory found"
}

@test "replay: warns when PROGRESS.md missing but still generates" {
  # Remove PROGRESS.md but keep .claudeloop dir
  rm -f "$TEST_DIR/.claudeloop/PROGRESS.md"
  _cl --replay
  # Should warn but still succeed (generate_replay handles empty data)
  echo "$output" | grep -q "No PROGRESS.md found"
}

@test "replay: generates for archived run" {
  local archive_dir="$TEST_DIR/.claudeloop/archive/20260316-143022"
  mkdir -p "$archive_dir/logs"
  cat > "$archive_dir/PROGRESS.md" << 'PROGRESS'
## Phase 1: Setup
Status: completed
Started: 2026-01-01 00:00:00
Completed: 2026-01-01 00:01:00
Attempts: 1
PROGRESS

  _cl --replay 20260316-143022
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Generated .claudeloop/archive/20260316-143022/replay.html"
  [ -f "$archive_dir/replay.html" ]
}

@test "replay: errors for nonexistent archive" {
  _cl --replay nonexistent
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Archive not found"
}
