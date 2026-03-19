#!/usr/bin/env bash

# Test Runner for ClaudeLoop
# Runs all test files using bats (parallel by default, --serial for sequential)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse flags
SERIAL=false
for arg in "$@"; do
  case "$arg" in
    --serial) SERIAL=true ;;
  esac
done

echo "ClaudeLoop Test Runner"
echo "======================"
if $SERIAL; then
  echo "(sequential mode)"
else
  echo "(parallel mode)"
fi
echo

# Check if bats is installed
BATS_CMD=""
if command -v bats &> /dev/null; then
  BATS_CMD="bats"
elif [ -x /opt/homebrew/bin/bats ]; then
  BATS_CMD="/opt/homebrew/bin/bats"
else
  echo -e "${YELLOW}Warning: bats-core is not installed${NC}"
  echo
  echo "To install bats-core:"
  echo "  macOS:   brew install bats-core"
  echo "  Linux:   apt-get install bats (or use npm: npm install -g bats)"
  echo "  Other:   https://github.com/bats-core/bats-core#installation"
  echo
  exit 1
fi

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure claudeloop has execute permission (frequently lost by git operations)
chmod +x "$SCRIPT_DIR/../claudeloop" 2>/dev/null || true

export PATH="/opt/homebrew/bin:$PATH"

# Skip the original monolithic file if split files exist
SKIP_FILES=""
if [ -f test_integration_basic.sh ] && [ -f test_integration_retry.sh ] && [ -f test_integration_state.sh ]; then
  SKIP_FILES="test_integration.sh"
fi

# Collect test files
TEST_FILES=()
for test_file in test_*.sh; do
  [ -f "$test_file" ] || continue
  [ "$test_file" = "$SKIP_FILES" ] && continue
  TEST_FILES+=("$test_file")
done

if [ ${#TEST_FILES[@]} -eq 0 ]; then
  echo "No test files found."
  exit 1
fi

echo "Running ${#TEST_FILES[@]} test files..."
echo

run_serial() {
  local failed=0
  for test_file in "${TEST_FILES[@]}"; do
    echo -e "${YELLOW}Running $test_file${NC}"
    if $BATS_CMD "$test_file"; then
      echo -e "${GREEN}✓ $test_file passed${NC}"
      echo
    else
      echo -e "${RED}✗ $test_file failed${NC}"
      echo
      failed=$((failed + 1))
    fi
  done
  return $failed
}

run_parallel() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local pids=()
  local files=()

  # Launch all test files as background jobs
  for test_file in "${TEST_FILES[@]}"; do
    local out_file="$tmp_dir/${test_file}.out"
    local rc_file="$tmp_dir/${test_file}.rc"
    (
      $BATS_CMD "$test_file" > "$out_file" 2>&1
      echo $? > "$rc_file"
    ) &
    pids+=($!)
    files+=("$test_file")
  done

  echo -e "${BLUE}Launched ${#pids[@]} test files in parallel...${NC}"
  echo

  # Wait for all jobs
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Collect results
  local failed=0
  local failed_files=()
  for test_file in "${files[@]}"; do
    local rc_file="$tmp_dir/${test_file}.rc"
    local out_file="$tmp_dir/${test_file}.out"
    local rc=1
    [ -f "$rc_file" ] && rc=$(cat "$rc_file")
    if [ "$rc" -eq 0 ]; then
      echo -e "${GREEN}✓ $test_file${NC}"
    else
      echo -e "${RED}✗ $test_file${NC}"
      failed=$((failed + 1))
      failed_files+=("$test_file")
    fi
  done

  # Print full output for failures
  if [ ${#failed_files[@]} -gt 0 ]; then
    echo
    echo "======================"
    echo -e "${RED}Failed test output:${NC}"
    for test_file in "${failed_files[@]}"; do
      echo
      echo -e "${RED}--- $test_file ---${NC}"
      cat "$tmp_dir/${test_file}.out"
    done
  fi

  rm -rf "$tmp_dir"
  return $failed
}

# Run tests
FAILED=0
if $SERIAL; then
  run_serial || FAILED=$?
else
  run_parallel || FAILED=$?
fi

# Summary
echo
echo "======================"
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}$FAILED test file(s) failed${NC}"
  exit 1
fi
