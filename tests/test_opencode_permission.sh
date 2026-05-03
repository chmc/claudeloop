#!/usr/bin/env bats
# bats file_tags=opencode,permission

# Tests for lib/adapters/permission_opencode.sh — OpenCode permission handling

setup() {
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/.."
  source "${BATS_TEST_DIRNAME}/../lib/ui.sh"
  source "${BATS_TEST_DIRNAME}/../lib/permission_interface.sh"
  source "${BATS_TEST_DIRNAME}/../lib/adapters/permission_opencode.sh"
  VERBOSE_MODE=false
  SKIP_PERMISSIONS=true
  _tmpdir="$BATS_TEST_TMPDIR"
}

teardown() { :; }

# --- _opencode_extract_field() ---

@test "_opencode_extract_field: extracts simple string field" {
  local json='{"type":"permission.updated","id":"perm123"}'
  run _opencode_extract_field "$json" "id"
  [ "$status" -eq 0 ]
  [ "$output" = "perm123" ]
}

@test "_opencode_extract_field: extracts type field" {
  local json='{"type":"permission.updated","properties":{"id":"perm123","sessionID":"sess456"}}'
  run _opencode_extract_field "$json" "type"
  [ "$status" -eq 0 ]
  [ "$output" = "permission.updated" ]
}

@test "_opencode_extract_field: extracts sessionID from nested structure" {
  local json='{"type":"permission.updated","properties":{"id":"perm123","sessionID":"sess456","type":"file.write","title":"Write to file"}}'
  run _opencode_extract_field "$json" "sessionID"
  [ "$status" -eq 0 ]
  [ "$output" = "sess456" ]
}

@test "_opencode_extract_field: returns empty for missing field" {
  local json='{"type":"permission.updated"}'
  run _opencode_extract_field "$json" "nonexistent"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "_opencode_extract_field: handles escaped quotes in value" {
  local json='{"title":"Write \"config\" file","type":"test"}'
  run _opencode_extract_field "$json" "title"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# --- _opencode_permission_filter() ---

@test "_opencode_permission_filter: passes non-permission events through unchanged" {
  local input='{"type":"session.created","model":"gpt-4"}
{"type":"message.part.updated","text":"Hello"}
{"type":"session.idle"}'
  result=$(printf '%s\n' "$input" | _opencode_permission_filter)
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 3 ]
  echo "$result" | grep -q '"type":"session.created"'
  echo "$result" | grep -q '"type":"message.part.updated"'
  echo "$result" | grep -q '"type":"session.idle"'
}

@test "_opencode_permission_filter: intercepts permission.updated and does not pass downstream" {
  SKIP_PERMISSIONS=true
  OPENCODE_SESSION_ID="test-session"
  local input='{"type":"permission.updated","properties":{"id":"perm123","sessionID":"sess456","type":"file.write","title":"Write to file"}}
{"type":"session.idle"}'
  # Stub curl to prevent actual HTTP calls
  curl() { :; }
  export -f curl
  result=$(printf '%s\n' "$input" | _opencode_permission_filter 2>/dev/null)
  # Only session.idle should pass through, not permission.updated
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 1 ]
  echo "$result" | grep -q '"type":"session.idle"'
  ! echo "$result" | grep -q '"type":"permission.updated"'
}

@test "_opencode_permission_filter: handles empty input gracefully" {
  result=$(printf '' | _opencode_permission_filter)
  [ -z "$result" ]
}

@test "_opencode_permission_filter: handles single non-permission event" {
  local input='{"type":"file.edited","path":"/tmp/test.txt"}'
  result=$(printf '%s\n' "$input" | _opencode_permission_filter)
  [ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 1 ]
  echo "$result" | grep -q '"type":"file.edited"'
}

# --- Environment variable defaults ---

@test "OPENCODE_HTTP_HOST: defaults to localhost" {
  unset OPENCODE_HTTP_HOST
  source "${BATS_TEST_DIRNAME}/../lib/adapters/permission_opencode.sh"
  [ "$OPENCODE_HTTP_HOST" = "localhost" ]
}

@test "OPENCODE_HTTP_PORT: defaults to 8080" {
  unset OPENCODE_HTTP_PORT
  source "${BATS_TEST_DIRNAME}/../lib/adapters/permission_opencode.sh"
  [ "$OPENCODE_HTTP_PORT" = "8080" ]
}

@test "OPENCODE_HTTP_HOST: respects custom value" {
  OPENCODE_HTTP_HOST="custom.host"
  source "${BATS_TEST_DIRNAME}/../lib/adapters/permission_opencode.sh"
  [ "$OPENCODE_HTTP_HOST" = "custom.host" ]
}

@test "OPENCODE_HTTP_PORT: respects custom value" {
  OPENCODE_HTTP_PORT="9999"
  source "${BATS_TEST_DIRNAME}/../lib/adapters/permission_opencode.sh"
  [ "$OPENCODE_HTTP_PORT" = "9999" ]
}
