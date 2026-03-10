#!/usr/bin/env bash
# bats file_tags=integration

# Integration tests for claudeloop — retry logic, quota, failures, timeouts, log rotation
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
# Item 0: MAX_RETRIES default is 10
# =============================================================================
@test "default MAX_RETRIES is 15" {
  # Source retry.sh in a clean env (no MAX_RETRIES set) and verify the default
  result=$(unset MAX_RETRIES; sh -c ". '$CLAUDELOOP_DIR/lib/parser.sh'; . '$CLAUDELOOP_DIR/lib/phase_state.sh'; . '$CLAUDELOOP_DIR/lib/retry.sh'; printf '%s' \"\$MAX_RETRIES\"")
  [ "$result" = "15" ]
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
printf '{"type":"tool_use","name":"Edit","input":{}}\n'
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
printf '{"type":"tool_use","name":"Edit","input":{}}\n'
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

# =============================================================================
# Pipeline hang regression: first process lingering doesn't block completion
# =============================================================================
@test "integration: pipeline does not hang when first process lingers after last exits" {
  # Simulate Claude CLI that keeps running after stream processor exits.
  # The stub outputs a result event then sleeps 30s — the sentinel-based wait
  # should detect stream processor exit and kill the lingering Claude process.
  cat > "$TEST_DIR/bin/claude" << EOF
#!/bin/sh
count_file="$TEST_DIR/claude_call_count"
count=\$(cat "\$count_file" 2>/dev/null || echo 0)
count=\$((count + 1))
printf '%s\n' "\$count" > "\$count_file"
# Emit a result event so stream processor exits, then linger
printf '{"type":"result","total_cost_usd":0.001,"duration_ms":1000,"num_turns":1,"usage":{"input_tokens":100,"output_tokens":10}}\n'
sleep 30
EOF
  chmod +x "$TEST_DIR/bin/claude"

  _start=$(date '+%s')
  _cl --plan PLAN.md
  _end=$(date '+%s')
  _elapsed=$((_end - _start))

  [ "$status" -eq 0 ]
  # Must finish well before 30s (Claude lingers but pipeline should be killed)
  [ "$_elapsed" -lt 20 ]
  [ "$(_completed_count)" -eq 2 ]
}
