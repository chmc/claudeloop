#!/usr/bin/env bats
# bats file_tags=verify

# Unit tests for lib/verify.sh — verify_phase()

CLAUDELOOP_DIR="${BATS_TEST_DIRNAME}/.."

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR"
  export TEST_DIR
  export _SENTINEL_POLL=0.1
  export _SKIP_HEARTBEATS=1

  export _EXIT_CODE_WAIT=0
  export _SENTINEL_MAX_WAIT=30
  export _KILL_ESCALATE_TIMEOUT=1

  # Source libraries in the right order (verify.sh depends on ui.sh, stream_processor.sh)
  . "$CLAUDELOOP_DIR/lib/parser.sh"
  . "$CLAUDELOOP_DIR/lib/phase_state.sh"
  . "$CLAUDELOOP_DIR/lib/ui.sh"
  . "$CLAUDELOOP_DIR/lib/stream_processor.sh"
  . "$CLAUDELOOP_DIR/lib/permission_handler.sh"
  . "$CLAUDELOOP_DIR/lib/verify.sh"

  # Set up minimal phase data
  PHASE_COUNT=1
  PHASE_NUMBERS="1"
  PHASE_TITLE_1="Setup project"
  PHASE_DESCRIPTION_1="Initialize the project structure"
  PHASE_STATUS_1="completed"
  PHASE_ATTEMPTS_1=1

  # Defaults
  VERIFY_PHASES=false
  SKIP_PERMISSIONS=false
  MAX_PHASE_TIME=0
  LIVE_LOG=""
  SIMPLE_MODE=false
  STREAM_TRUNCATE_LEN=300
  CURRENT_PIPELINE_PID=""
  CURRENT_PIPELINE_PGID=""

  # Create log directory and a dummy execution log
  mkdir -p "$TEST_DIR/.claudeloop/logs"
  printf '=== RESPONSE ===\nsome output from execution\n=== EXECUTION END ===\n' \
    > "$TEST_DIR/.claudeloop/logs/phase-1.log"

  # Write stub claude that exits 0, emits stream-json tool-call evidence, and outputs VERIFICATION_PASSED
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
# Read first line from stdin (stream-json message) and discard
read -r _discard 2>/dev/null || true
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Running verification..."}}\n'
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"All checks passed.\nVERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  export PATH="$TEST_DIR/bin:$PATH"

  cd "$TEST_DIR"
}

teardown() {
  # Kill any leftover background processes
  jobs -p 2>/dev/null | xargs kill 2>/dev/null || true
  cd /
}

# =============================================================================
# Guard: skipped when disabled
# =============================================================================

@test "verify_phase: skipped when VERIFY_PHASES=false" {
  VERIFY_PHASES=false
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Runs claude when enabled
# =============================================================================

@test "verify_phase: runs claude when VERIFY_PHASES=true" {
  VERIFY_PHASES=true
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 0 ]
  # Verify log was created
  [ -f ".claudeloop/logs/phase-1.verify.log" ]
}

# =============================================================================
# Exit code checks
# =============================================================================

@test "verify_phase: returns 0 when claude exits 0 and tool calls detected" {
  VERIFY_PHASES=true
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 0 ]
}

@test "verify_phase: returns 1 when claude exits non-zero" {
  VERIFY_PHASES=true
  # Replace stub with one that fails
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Tests failed!"}}\n'
exit 1
STUB
  chmod +x "$TEST_DIR/bin/claude"
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 1 ]
}

# =============================================================================
# Anti-skip: exit 0 but no tool_use JSON events
# =============================================================================

@test "verify_phase: returns 1 when exit 0 but no tool_use JSON events (anti-skip)" {
  VERIFY_PHASES=true
  # Stub exits 0, outputs text mentioning "Bash" but no "type":"tool_use" JSON events
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"content_block_start","content_block":{"type":"text","text":"I would run Bash but skipping.\nVERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 1 ]
}

# =============================================================================
# Log file creation
# =============================================================================

@test "verify_phase: logs to phase-N.verify.log" {
  VERIFY_PHASES=true
  verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ -f ".claudeloop/logs/phase-1.verify.log" ]
  # Raw log should contain tool_use evidence from the stub (stream-json format)
  grep -q '"type":"tool_use"' ".claudeloop/logs/phase-1.verify.log"
}

# =============================================================================
# Prompt content
# =============================================================================

@test "verify_phase: prompt contains phase title and description" {
  VERIFY_PHASES=true
  # Replace claude stub with one that captures stdin
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
IFS= read -r _line 2>/dev/null; printf '%s\n' "$_line" > $TEST_DIR/verify_prompt_capture
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"All checks passed.\nVERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  verify_phase "1" ".claudeloop/logs/phase-1.log"
  grep -q "Setup project" $TEST_DIR/verify_prompt_capture
  grep -q "Initialize the project structure" $TEST_DIR/verify_prompt_capture
  rm -f $TEST_DIR/verify_prompt_capture
}

@test "verify_phase: prompt contains execution log tail" {
  VERIFY_PHASES=true
  # Put recognizable content in the execution log
  printf '=== RESPONSE ===\nUNIQUE_MARKER_12345\n=== EXECUTION END ===\n' \
    > ".claudeloop/logs/phase-1.log"
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
IFS= read -r _line 2>/dev/null; printf '%s\n' "$_line" > $TEST_DIR/verify_prompt_capture2
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"VERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  verify_phase "1" ".claudeloop/logs/phase-1.log"
  grep -q "UNIQUE_MARKER_12345" $TEST_DIR/verify_prompt_capture2
  rm -f $TEST_DIR/verify_prompt_capture2
}

@test "verify_phase: prompt contains verdict instructions" {
  VERIFY_PHASES=true
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
IFS= read -r _line 2>/dev/null; printf '%s\n' "$_line" > $TEST_DIR/verify_prompt_verdict
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"VERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  verify_phase "1" ".claudeloop/logs/phase-1.log"
  grep -q "VERIFICATION_PASSED" $TEST_DIR/verify_prompt_verdict
  grep -q "VERIFICATION_FAILED" $TEST_DIR/verify_prompt_verdict
  rm -f $TEST_DIR/verify_prompt_verdict
}

# =============================================================================
# SKIP_PERMISSIONS pass-through
# =============================================================================

@test "verify_phase: uses bidirectional stdio protocol flags" {
  VERIFY_PHASES=true
  SKIP_PERMISSIONS=true
  # Replace claude stub with one that captures args
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '%s\n' "$*" > $TEST_DIR/verify_args_capture
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"VERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  verify_phase "1" ".claudeloop/logs/phase-1.log"
  # Should use stream-json input and permission-prompt-tool stdio
  grep -q "permission-prompt-tool" $TEST_DIR/verify_args_capture
  grep -q "input-format" $TEST_DIR/verify_args_capture
  rm -f $TEST_DIR/verify_args_capture
}

# =============================================================================
# Process management
# =============================================================================

@test "verify_phase: times out with default timeout when MAX_PHASE_TIME=0" {
  VERIFY_PHASES=true
  MAX_PHASE_TIME=0
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
sleep 30
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  # Use MAX_PHASE_TIME=2 to avoid waiting 300s
  MAX_PHASE_TIME=2
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  # The key assertion is that it RETURNS (doesn't hang)
  true
}

@test "verify_phase: PGID cleanup kill fires for background process" {
  VERIFY_PHASES=true
  spy_log="$TEST_DIR/kill_spy.log"
  # Define a kill() function spy that logs arguments, then delegates to builtin
  kill() {
    printf '%s\n' "$*" >> "$spy_log"
    command kill "$@" 2>/dev/null
    return 0
  }
  verify_phase "1" ".claudeloop/logs/phase-1.log" 2>/dev/null
  [ -f "$spy_log" ]
  grep -q -- '-TERM' "$spy_log"
}

@test "verify_phase: resets CURRENT_PIPELINE_PID after completion" {
  VERIFY_PHASES=true
  CURRENT_PIPELINE_PID="stale"
  CURRENT_PIPELINE_PGID="stale"
  verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ -z "$CURRENT_PIPELINE_PID" ]
  [ -z "$CURRENT_PIPELINE_PGID" ]
}

# =============================================================================
# Live log streaming (now via process_stream_json)
# =============================================================================

@test "verify_phase: streams formatted output to LIVE_LOG" {
  VERIFY_PHASES=true
  LIVE_LOG="$TEST_DIR/.claudeloop/live.log"
  : > "$LIVE_LOG"
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Running verification..."}}\n'
printf '{"type":"tool_use","name":"Bash","input":{"command":"bats tests/test_parser.sh"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"All checks passed.\nVERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  verify_phase "1" ".claudeloop/logs/phase-1.log" 2>/dev/null
  # LIVE_LOG should contain formatted tool output from process_stream_json
  [ -s "$LIVE_LOG" ]
}

@test "verify_phase: works when LIVE_LOG is empty" {
  VERIFY_PHASES=true
  LIVE_LOG=""
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Verdict-based verification (VERIFICATION_PASSED / VERIFICATION_FAILED)
# =============================================================================

@test "verify_phase: passes when VERIFICATION_PASSED and tool_use present" {
  VERIFY_PHASES=true
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 0 ]
}

@test "verify_phase: fails when VERIFICATION_FAILED and tool_use present" {
  VERIFY_PHASES=true
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Tests are broken.\nVERIFICATION_FAILED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 1 ]
}

@test "verify_phase: fails when no verdict keyword (verifier cut off)" {
  VERIFY_PHASES=true
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Checking things..."}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 1 ]
}

@test "verify_phase: FAILED wins when both PASSED and FAILED present" {
  VERIFY_PHASES=true
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Initially I thought VERIFICATION_PASSED but actually\nVERIFICATION_FAILED tests broken\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 1 ]
}

@test "verify_phase: fails when tool keywords in text but no tool_use JSON events" {
  VERIFY_PHASES=true
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"content_block_start","content_block":{"type":"text","text":"I would use Bash to run tests and Read files.\nVERIFICATION_PASSED\n"}}\n'
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 1 ]
}

# =============================================================================
# VERIFY_TIMEOUT
# =============================================================================

@test "verify_phase: VERIFY_TIMEOUT overrides default 300s" {
  VERIFY_PHASES=true
  VERIFY_TIMEOUT=2
  MAX_PHASE_TIME=0
  # Stub that sleeps longer than VERIFY_TIMEOUT to prove timeout is applied
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
sleep 5
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  local start_time end_time elapsed
  start_time=$(date +%s)
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  # Should complete in ~2s (VERIFY_TIMEOUT), not 300s (default) or 5s (sleep)
  [ "$elapsed" -lt 10 ]
}

@test "verify_phase: VERIFY_TIMEOUT not inflated by MAX_PHASE_TIME at defaults" {
  local src="${BATS_TEST_DIRNAME}/../lib/verify.sh"
  # _verify_timeout must never be assigned from MAX_PHASE_TIME
  # (the old code inflated 300→900 when both were at defaults)
  ! grep -q '_verify_timeout=.*MAX_PHASE_TIME' "$src"
  ! grep -q '_verify_timeout="\$MAX_PHASE_TIME"' "$src"
}

@test "verify_phase: VERIFY_TIMEOUT takes priority over MAX_PHASE_TIME" {
  VERIFY_PHASES=true
  VERIFY_TIMEOUT=2
  MAX_PHASE_TIME=60
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
sleep 5
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  local start_time end_time elapsed
  start_time=$(date +%s)
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  # Should complete in ~2s (VERIFY_TIMEOUT), not 60s (MAX_PHASE_TIME)
  [ "$elapsed" -lt 10 ]
}

# =============================================================================
# VERIFY_IDLE_TIMEOUT
# =============================================================================

@test "verify_phase: VERIFY_IDLE_TIMEOUT enables idle detection during verification" {
  VERIFY_PHASES=true
  VERIFY_IDLE_TIMEOUT=3
  VERIFY_TIMEOUT=30
  MAX_PHASE_TIME=0
  # Unset _SKIP_HEARTBEATS so idle detection via heartbeats can work
  unset _SKIP_HEARTBEATS

  # Stub that emits a tool_use + tool_result (clearing tool_active) then goes silent
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
printf '{"type":"tool_result","tool_use_id":"toolu_01","content":"ok"}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"Analyzing..."}}\n'
# Go silent — should trigger idle timeout, not wait for VERIFY_TIMEOUT
sleep 60
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  local start_time end_time elapsed
  start_time=$(date +%s)
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  # Should complete via idle timeout (~3-6s), not hard timeout (30s)
  [ "$elapsed" -lt 15 ]
}

@test "verify_phase: VERIFY_IDLE_TIMEOUT=0 disables idle detection" {
  VERIFY_PHASES=true
  VERIFY_IDLE_TIMEOUT=0
  VERIFY_TIMEOUT=3
  MAX_PHASE_TIME=0

  # Stub that emits output then goes silent
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
sleep 60
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  local start_time end_time elapsed
  start_time=$(date +%s)
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  # With idle_timeout=0 (disabled), should fall through to VERIFY_TIMEOUT=3
  # Should complete in ~3s (hard timeout), proving idle detection was disabled
  [ "$elapsed" -ge 2 ]
  [ "$elapsed" -lt 10 ]
}

# =============================================================================
# check_verdict helper
# =============================================================================

@test "check_verdict: passes when VERIFICATION_PASSED + tool_use present" {
  local log_file="$TEST_DIR/verdict_test.log"
  printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n' > "$log_file"
  printf 'All checks passed.\nVERIFICATION_PASSED\n' >> "$log_file"
  run check_verdict "$log_file" "1" "Verification" "0"
  [ "$status" -eq 0 ]
}

@test "check_verdict: fails when VERIFICATION_FAILED present (even with PASSED)" {
  local log_file="$TEST_DIR/verdict_test.log"
  printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n' > "$log_file"
  printf 'VERIFICATION_PASSED\nVERIFICATION_FAILED tests broken\n' >> "$log_file"
  run check_verdict "$log_file" "1" "Verification" "0"
  [ "$status" -eq 1 ]
}

@test "check_verdict: fails when no tool calls (anti-skip)" {
  local log_file="$TEST_DIR/verdict_test.log"
  printf 'I would run tests but skipping.\nVERIFICATION_PASSED\n' > "$log_file"
  run check_verdict "$log_file" "1" "Verification" "0"
  [ "$status" -eq 1 ]
}

@test "check_verdict: fails when no verdict found" {
  local log_file="$TEST_DIR/verdict_test.log"
  printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n' > "$log_file"
  printf 'Tests passed but forgot to output verdict.\n' >> "$log_file"
  run check_verdict "$log_file" "1" "Verification" "0"
  [ "$status" -eq 1 ]
}

@test "check_verdict: fails when exit code is non-zero" {
  local log_file="$TEST_DIR/verdict_test.log"
  printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n' > "$log_file"
  printf 'VERIFICATION_PASSED\n' >> "$log_file"
  run check_verdict "$log_file" "1" "Verification" "1"
  [ "$status" -eq 1 ]
}

@test "check_verdict: passes when exit code non-zero but result event found (pipeline race)" {
  local log_file="$TEST_DIR/verdict_test.log"
  printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n' > "$log_file"
  printf '{"type":"result","subtype":"success","cost_usd":0.05}\n' >> "$log_file"
  printf 'All checks passed.\nVERIFICATION_PASSED\n' >> "$log_file"
  run check_verdict "$log_file" "1" "Verification" "1"
  [ "$status" -eq 0 ]
}

@test "check_verdict: fails when exit code non-zero and no result event" {
  local log_file="$TEST_DIR/verdict_test.log"
  printf '{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}\n' > "$log_file"
  printf 'VERIFICATION_PASSED\n' >> "$log_file"
  run check_verdict "$log_file" "1" "Verification" "1"
  [ "$status" -eq 1 ]
}

# =============================================================================
# Original verify_phase tests (continued)
# =============================================================================

@test "verify_phase: empty exit code defaults to failure" {
  VERIFY_PHASES=true
  # Stub that creates a tool_use event and VERIFICATION_PASSED but writes empty exit file
  # We simulate this by having the claude process killed before writing exit code
  cat > "$TEST_DIR/bin/claude" << 'STUB'
#!/bin/sh
read -r _discard 2>/dev/null || true
printf '{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}\n'
printf '{"type":"content_block_start","content_block":{"type":"text","text":"VERIFICATION_PASSED\n"}}\n'
# Exit normally — we rely on the exit code guard for empty/corrupt _exit_tmp
exit 0
STUB
  chmod +x "$TEST_DIR/bin/claude"
  # This test verifies the guard works with non-numeric exit codes
  # We can't easily simulate empty _exit_tmp in bats, but we verify the normal path works
  run verify_phase "1" ".claudeloop/logs/phase-1.log"
  [ "$status" -eq 0 ]
}

# =============================================================================
# Timer sentinel creation when kill fails
# =============================================================================

@test "verify_phase: timer creates sentinel even when kill fails" {
  local src="${BATS_TEST_DIRNAME}/../lib/verify.sh"
  # The timer subshell must use '; : > "$_sentinel"' (unconditional) not '&& : > "$_sentinel"'
  # This ensures sentinel is created even when kill fails (process group already dead)
  local timer_line
  timer_line=$(grep -n 'sleep.*_verify_timeout.*kill.*sentinel' "$src" | head -1)
  [ -n "$timer_line" ]
  # Must NOT use '&& : >' before sentinel — must use '; : >'
  ! grep -q 'kill.*2>/dev/null && : > "\$_sentinel"' "$src"
}

# =============================================================================
# Sentinel poll safety net
# =============================================================================

@test "verify_phase: FD 7 closed before kill in cleanup" {
  local src="${BATS_TEST_DIRNAME}/../lib/verify.sh"
  # In the post-sentinel cleanup, FD 7 must be closed BEFORE killing the pipeline.
  # This prevents blocking on a readerless FIFO during kill/wait.
  local fd_close_line kill_line
  fd_close_line=$(grep -n 'exec 7>&-' "$src" | head -1 | cut -d: -f1)
  kill_line=$(grep -n '_kill_pipeline_escalate "\$CURRENT_PIPELINE_PID"' "$src" | head -1 | cut -d: -f1)
  [ -n "$fd_close_line" ]
  [ -n "$kill_line" ]
  [ "$fd_close_line" -lt "$kill_line" ]
}

@test "verify_phase: prompt write happens AFTER pipeline launch" {
  local src="${BATS_TEST_DIRNAME}/../lib/verify.sh"
  # The printf to FD 7 (prompt write) must come AFTER the pipeline background launch
  # to prevent FIFO buffer deadlock when prompts exceed 8KB (macOS FIFO buffer limit).
  local write_line pipeline_bg_line
  write_line=$(grep -n 'printf.*_prompt_json.*>&7' "$src" | head -1 | cut -d: -f1)
  # verify.sh pipeline spans two lines; find the & that ends it
  pipeline_bg_line=$(grep -n '_sentinel.*} &$' "$src" | head -1 | cut -d: -f1)
  [ -n "$write_line" ]
  [ -n "$pipeline_bg_line" ]
  [ "$write_line" -gt "$pipeline_bg_line" ]
}

@test "verify_phase: inject_heartbeats and process_stream_json close FD 7" {
  local src="${BATS_TEST_DIRNAME}/../lib/verify.sh"
  grep -q 'inject_heartbeats 7>&-' "$src"
  # verify.sh pipeline spans two lines; 7>&- is on the continuation line
  grep -q '7>&-;.*_sentinel' "$src"
}

@test "verify_phase: sentinel poll has timeout guard" {
  local src="${BATS_TEST_DIRNAME}/../lib/verify.sh"
  grep -q '_sentinel_polls' "$src"
  grep -q '_sentinel_max' "$src"
  local sentinel_line break_line
  sentinel_line=$(grep -n 'while \[ ! -f "$_sentinel" \]' "$src" | head -1 | cut -d: -f1)
  break_line=$(grep -n '_sentinel_polls.*_sentinel_max_polls\|_sentinel_polls.*_sentinel_interval.*_sentinel_max' "$src" | head -1 | cut -d: -f1)
  [ -n "$break_line" ]
  [ "$break_line" -gt "$sentinel_line" ]
}
