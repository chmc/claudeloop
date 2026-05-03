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

# --- _opencode_send_permission_response() HTTP tests ---

@test "_opencode_send_permission_response: sends correct HTTP body with always response" {
  OPENCODE_HTTP_HOST="localhost"
  OPENCODE_HTTP_PORT="9999"

  # Capture curl arguments
  curl() {
    printf '%s\n' "$@" > "$_tmpdir/curl_args"
  }
  export -f curl

  _opencode_send_permission_response "sess123" "perm456" "always"
  wait  # Wait for background process

  # Verify the URL format
  grep -q "http://localhost:9999/session/sess123/permissions/perm456" "$_tmpdir/curl_args"
  # Verify JSON body
  grep -q '{"response":"always"}' "$_tmpdir/curl_args"
}

@test "_opencode_send_permission_response: sends correct HTTP body with once response" {
  OPENCODE_HTTP_HOST="localhost"
  OPENCODE_HTTP_PORT="8080"

  curl() {
    printf '%s\n' "$@" > "$_tmpdir/curl_args"
  }
  export -f curl

  _opencode_send_permission_response "mysession" "myperm" "once"
  wait

  grep -q '{"response":"once"}' "$_tmpdir/curl_args"
}

@test "_opencode_send_permission_response: sends correct HTTP body with reject response" {
  OPENCODE_HTTP_HOST="localhost"
  OPENCODE_HTTP_PORT="8080"

  curl() {
    printf '%s\n' "$@" > "$_tmpdir/curl_args"
  }
  export -f curl

  _opencode_send_permission_response "sess" "perm" "reject"
  wait

  grep -q '{"response":"reject"}' "$_tmpdir/curl_args"
}

@test "_opencode_send_permission_response: logs warning on HTTP failure but does not block" {
  OPENCODE_HTTP_HOST="localhost"
  OPENCODE_HTTP_PORT="8080"
  VERBOSE_MODE=true

  # Mock curl to fail
  curl() {
    return 1
  }
  export -f curl

  # Should not block - function returns immediately, background logs warning
  result=$(_opencode_send_permission_response "sess" "perm" "always" 2>"$_tmpdir/stderr")
  wait

  # Function returns without error (curl runs in background)
  [ -z "$result" ]
}

# --- _opencode_handle_permission() response mapping tests ---

@test "_opencode_handle_permission: allow decision maps to always HTTP response" {
  SKIP_PERMISSIONS=true  # Forces allow decision

  # Capture what response type is sent
  _opencode_send_permission_response() {
    echo "$3" > "$_tmpdir/response_type"
  }

  local json='{"type":"permission.updated","id":"perm1","sessionID":"sess1","type":"file.write","title":"test"}'
  _opencode_handle_permission "$json"

  [ "$(cat "$_tmpdir/response_type")" = "always" ]
}

@test "_opencode_handle_permission: missing permissionID returns error" {
  SKIP_PERMISSIONS=true
  OPENCODE_SESSION_ID="fallback-session"

  # Stub the send function
  _opencode_send_permission_response() { :; }

  local json='{"type":"permission.updated","sessionID":"sess1"}'
  run _opencode_handle_permission "$json"

  [ "$status" -eq 1 ]
}

@test "_opencode_handle_permission: falls back to OPENCODE_SESSION_ID env var" {
  SKIP_PERMISSIONS=true
  OPENCODE_SESSION_ID="env-session-id"

  # Capture session ID used
  _opencode_send_permission_response() {
    echo "$1" > "$_tmpdir/session_id"
  }

  # JSON without sessionID field
  local json='{"type":"permission.updated","id":"perm123","type":"file.write","title":"test"}'
  _opencode_handle_permission "$json"

  [ "$(cat "$_tmpdir/session_id")" = "env-session-id" ]
}
