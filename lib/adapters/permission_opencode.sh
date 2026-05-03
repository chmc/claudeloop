#!/bin/sh
# OpenCode Permission Adapter - HTTP-based permission protocol
# Handles OpenCode's permission requests via HTTP POST to session endpoint.

# Load shared permission interface for decision logic
if [ -n "$SCRIPT_DIR" ]; then
  . "$SCRIPT_DIR/lib/permission_interface.sh"
fi

# HTTP endpoint configuration
OPENCODE_HTTP_HOST="${OPENCODE_HTTP_HOST:-localhost}"
OPENCODE_HTTP_PORT="${OPENCODE_HTTP_PORT:-8080}"

# Extract a field value from JSON using awk
# Handles nested properties (e.g., "properties.id")
# Args: $1 - JSON string, $2 - field name
# Returns: field value (stdout), empty string if not found
_opencode_extract_field() {
  printf '%s' "$1" | awk -v key="$2" '{
    tag = "\"" key "\":\""
    i = index($0, tag)
    if (i == 0) { print ""; exit }
    i += length(tag)
    val = ""
    for (j = i; j <= length($0); j++) {
      c = substr($0, j, 1)
      if (c == "\\") { val = val substr($0, j, 2); j++; continue }
      if (c == "\"") break
      val = val c
    }
    print val
  }'
}

# Send permission response via HTTP POST
# Args: $1 - sessionID, $2 - permissionID, $3 - response type (always/once/reject)
# Runs curl in background, logs warning on failure
_opencode_send_permission_response() {
  local _session_id="$1"
  local _permission_id="$2"
  local _response_type="$3"
  local _url="http://${OPENCODE_HTTP_HOST}:${OPENCODE_HTTP_PORT}/session/${_session_id}/permissions/${_permission_id}"
  local _body="{\"response\":\"${_response_type}\"}"

  (
    if ! curl -s -X POST \
      -H "Content-Type: application/json" \
      -d "$_body" \
      "$_url" >/dev/null 2>&1; then
      log_warning "opencode_permission: HTTP POST failed for ${_url}"
    fi
  ) &
}

# Handle a single permission.updated event
# Args: $1 - permission.updated JSON line
_opencode_handle_permission() {
  local _perm_line="$1"
  local _decision

  _decision=$(_permission_decide)

  # Extract fields from properties object
  local _permission_id _session_id _tool_type _title
  _permission_id=$(_opencode_extract_field "$_perm_line" "id")
  _session_id=$(_opencode_extract_field "$_perm_line" "sessionID")
  _tool_type=$(_opencode_extract_field "$_perm_line" "type")
  _title=$(_opencode_extract_field "$_perm_line" "title")

  # Fall back to environment session ID if not in event
  [ -z "$_session_id" ] && _session_id="${OPENCODE_SESSION_ID:-}"

  if [ -z "$_permission_id" ] || [ -z "$_session_id" ]; then
    log_warning "opencode_permission: missing permissionID or sessionID in event"
    return 1
  fi

  case "$_decision" in
    allow)
      log_verbose "opencode_permission: auto-approving permission request"
      _opencode_send_permission_response "$_session_id" "$_permission_id" "always"
      ;;
    interactive)
      local _tool_name="${_tool_type:-unknown}"
      local _reason="${_title:-Permission requested}"

      local _user_decision
      _user_decision=$(_permission_prompt_user "$_tool_name" "$_reason")

      if [ "$_user_decision" = "allow" ]; then
        _opencode_send_permission_response "$_session_id" "$_permission_id" "once"
      else
        _opencode_send_permission_response "$_session_id" "$_permission_id" "reject"
      fi
      ;;
    *)
      log_verbose "opencode_permission: auto-denying (non-interactive, SKIP_PERMISSIONS=false)"
      _opencode_send_permission_response "$_session_id" "$_permission_id" "reject"
      ;;
  esac
}

# Pipeline filter: reads OpenCode's stdout, intercepts permission.updated events,
# passes everything else downstream. Sends HTTP responses in background.
_opencode_permission_filter() {
  while IFS= read -r _pf_line; do
    case "$_pf_line" in
      *'"type":"permission.updated"'*)
        _opencode_handle_permission "$_pf_line"
        ;;
      *)
        printf '%s\n' "$_pf_line" 2>/dev/null || break
        ;;
    esac
  done
}
