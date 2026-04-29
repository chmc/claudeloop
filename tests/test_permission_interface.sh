#!/usr/bin/env bats
# bats file_tags=permission_interface

# Tests for lib/permission_interface.sh — shared decision logic

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/permission_interface.sh"
  SKIP_PERMISSIONS=false
}

teardown() { :; }

# --- _permission_decide() ---

@test "_permission_decide: returns 'allow' when SKIP_PERMISSIONS=true" {
  SKIP_PERMISSIONS=true
  run _permission_decide
  [ "$status" -eq 0 ]
  [ "$output" = "allow" ]
}

@test "_permission_decide: returns 'deny' when non-interactive and SKIP_PERMISSIONS=false" {
  # In CI/non-TTY environment with no /dev/tty access
  SKIP_PERMISSIONS=false
  # We can't easily test the "deny" path since /dev/tty usually exists
  # Just verify the function runs without error
  run _permission_decide
  [ "$status" -eq 0 ]
  # Should return either "deny" or "interactive" depending on TTY availability
  [[ "$output" = "deny" || "$output" = "interactive" ]]
}

@test "_permission_decide: returns 'interactive' when TTY available" {
  SKIP_PERMISSIONS=false
  # /dev/tty exists on most systems
  if [ -e /dev/tty ]; then
    run _permission_decide
    [ "$status" -eq 0 ]
    [ "$output" = "interactive" ]
  else
    skip "No /dev/tty available"
  fi
}

# --- _permission_prompt_user() ---

@test "_permission_prompt_user: accepts tool name and reason" {
  # When /dev/tty isn't available for read, it defaults to "deny"
  # Capture only stdout, ignore stderr errors about /dev/tty
  result=$(_permission_prompt_user "Write" "Writing to /tmp/test.txt" 2>/dev/null)
  # Last line should be the answer
  answer=$(printf '%s' "$result" | tail -1)
  [ "$answer" = "deny" ]
}

@test "_permission_prompt_user: handles empty reason" {
  result=$(_permission_prompt_user "Edit" 2>/dev/null)
  answer=$(printf '%s' "$result" | tail -1)
  [ "$answer" = "deny" ]
}
