#!/usr/bin/env bash

# Test Runner for ClaudeLoop
# Runs all test files using bats

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "ClaudeLoop Test Runner"
echo "======================"
echo

# Check if bats is installed
if ! command -v bats &> /dev/null; then
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

# Run all test files
echo "Running tests..."
echo

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Ensure we use bash 5+ for tests (required for associative arrays)
export PATH="/opt/homebrew/bin:$PATH"

# Run each test file
for test_file in test_*.sh; do
  if [ -f "$test_file" ]; then
    echo -e "${YELLOW}Running $test_file${NC}"
    # Run with explicit bash 5
    if /opt/homebrew/bin/bats "$test_file"; then
      echo -e "${GREEN}✓ $test_file passed${NC}"
      echo
    else
      echo -e "${RED}✗ $test_file failed${NC}"
      echo
      FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  fi
done

# Summary
echo "======================"
if [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed${NC}"
  exit 1
fi
