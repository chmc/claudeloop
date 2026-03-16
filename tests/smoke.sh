#!/bin/sh
# Smoke tests for claudeloop
# Runs basic checks to verify the app works end-to-end.
# Uses a stub 'claude' binary — no real AI calls.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDELOOP="${SCRIPT_DIR}/../claudeloop"
FIXTURES="${SCRIPT_DIR}/fixtures/smoke-plans"

export _CLAUDELOOP_NO_AUTO_ARCHIVE=1

PASS_COUNT=0
FAIL_COUNT=0
TMPDIR_ROOT=""

cleanup() {
  [ -n "$TMPDIR_ROOT" ] && rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

# Create a temp dir for all test state
TMPDIR_ROOT=$(mktemp -d)

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "  PASS: %s\n" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  FAIL: %s\n" "$1"
  [ -n "$2" ] && printf "        %s\n" "$2"
}

# Write a stub claude binary into the given directory
write_stub() {
  dir="$1"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/claude" << STUBEOF
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
printf 'stub output for call %s\n' "\$count"
printf '{"type":"tool_use","name":"Edit","input":{}}\n'
exit "\$exit_code"
STUBEOF
  chmod +x "$dir/bin/claude"
}

# Setup a test directory with git repo, stub, and zero-delay config
setup_test_dir() {
  td="${TMPDIR_ROOT}/$1"
  mkdir -p "$td"
  git -C "$td" init -q
  git -C "$td" config user.email "test@test.com"
  git -C "$td" config user.name "Test"
  write_stub "$td"
  mkdir -p "$td/.claudeloop"
  cat > "$td/.claudeloop/.claudeloop.conf" << 'CONF'
BASE_DELAY=0
AI_PARSE=false
VERIFY_PHASES=false
REFACTOR_PHASES=false
CONF
  printf '%s' "$td"
}

printf "=== claudeloop smoke tests ===\n\n"

# ---- Check 1: Dry-run with valid plan exits 0 ----
printf "Check 1: Dry-run valid plan\n"
if "$CLAUDELOOP" --plan "$FIXTURES/single-phase.md" --dry-run > /dev/null 2>&1; then
  pass "dry-run valid plan exits 0"
else
  fail "dry-run valid plan exited non-zero"
fi

# ---- Check 2: Dry-run with nonexistent plan exits non-zero ----
printf "Check 2: Dry-run invalid plan\n"
if "$CLAUDELOOP" --plan "/nonexistent/plan.md" --dry-run > /dev/null 2>&1; then
  fail "dry-run nonexistent plan should exit non-zero"
else
  pass "dry-run nonexistent plan exits non-zero"
fi

# ---- Check 3: Stub execution of 2-phase plan ----
printf "Check 3: Stub execution 2-phase plan\n"
TD=$(setup_test_dir "check3")
cp "$FIXTURES/two-phase-deps.md" "$TD/PLAN.md"
git -C "$TD" add PLAN.md && git -C "$TD" commit -q -m "init"

if (cd "$TD" && PATH="$TD/bin:$PATH" "$CLAUDELOOP" --plan PLAN.md -y) > /dev/null 2>&1; then
  pass "stub execution exits 0"
else
  fail "stub execution exited non-zero"
fi

completed=$(grep -c "Status: completed" "$TD/.claudeloop/PROGRESS.md" 2>/dev/null || echo 0)
if [ "$completed" -eq 2 ]; then
  pass "both phases completed"
else
  fail "expected 2 completed phases, got $completed"
fi

if [ -d "$TD/.claudeloop/logs" ] && [ "$(ls "$TD/.claudeloop/logs/" 2>/dev/null | wc -l)" -gt 0 ]; then
  pass "phase logs exist"
else
  fail "no phase logs found"
fi

# ---- Check 4: 3-phase plan with deps — execution order ----
printf "Check 4: 3-phase plan with dependencies\n"
TD=$(setup_test_dir "check4")
cat > "$TD/PLAN.md" << 'PLAN'
## Phase 1: First
Step one

## Phase 2: Second
Step two

**Dependencies:** Phase 1

## Phase 3: Third
Step three

**Dependencies:** Phase 2
PLAN
git -C "$TD" add PLAN.md && git -C "$TD" commit -q -m "init"

if (cd "$TD" && PATH="$TD/bin:$PATH" "$CLAUDELOOP" --plan PLAN.md -y) > /dev/null 2>&1; then
  pass "3-phase dep execution exits 0"
else
  fail "3-phase dep execution exited non-zero"
fi

completed=$(grep -c "Status: completed" "$TD/.claudeloop/PROGRESS.md" 2>/dev/null || echo 0)
if [ "$completed" -eq 3 ]; then
  pass "all 3 phases completed"
else
  fail "expected 3 completed phases, got $completed"
fi

# Check execution order: phase logs should be numbered sequentially
logs_dir="$TD/.claudeloop/logs"
if [ -d "$logs_dir" ]; then
  log_phases=$(ls "$logs_dir" 2>/dev/null | grep '\.log$' | sed 's/^phase-//' | sed 's/\.log$//' | sort -n | tr '\n' ' ' | sed 's/ $//')
  if [ "$log_phases" = "1 2 3" ]; then
    pass "phases executed in dependency order"
  else
    fail "unexpected phase order: $log_phases" "expected: 1 2 3"
  fi
else
  fail "no logs directory found"
fi

# ---- Summary ----
printf "\n=== Results: %s passed, %s failed ===\n" "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
