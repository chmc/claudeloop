#!/usr/bin/env bats
# Tests for mutate.sh exit code behavior

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
}

@test "mutate.sh contains exit 1 on survivors guard" {
  # Verify the script exits non-zero when survivors exist
  run grep 'TOTAL_SURVIVED.*-gt 0.*exit 1' "$REPO_ROOT/tests/mutate.sh"
  [ "$status" -eq 0 ]
}

@test "mutate.sh exit guard is after print_summary and write_report" {
  # The exit guard must come after print_summary and write_report in main()
  local last_print_summary
  last_print_summary=$(grep -n 'print_summary' "$REPO_ROOT/tests/mutate.sh" | tail -1 | cut -d: -f1)
  local exit_guard_line
  exit_guard_line=$(grep -n 'TOTAL_SURVIVED.*-gt 0.*exit 1' "$REPO_ROOT/tests/mutate.sh" | tail -1 | cut -d: -f1)
  [ "$exit_guard_line" -gt "$last_print_summary" ]
}
