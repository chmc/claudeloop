#!/bin/sh
# Claude Permission Adapter - FD7/FIFO bidirectional protocol
# Handles Claude Code's permission requests via stdio stream-json protocol.

# Load shared permission interface for decision logic
if [ -n "$SCRIPT_DIR" ]; then
  . "$SCRIPT_DIR/lib/permission_interface.sh"
fi

# FD used for writing control_responses back to claude's stdin via FIFO.
# Default FD 7 (avoids conflict with bats FD 3 and shell FDs 0-2).
# Callers open this FD before starting the pipeline:
#   exec 7<>"$_fifo"; ... | _claude_permission_filter | ...
_CLAUDE_PERMISSION_FD=${_CLAUDE_PERMISSION_FD:-7}

# Extract a simple string field value from JSON using awk
# Args: $1 - JSON string, $2 - field name
# Returns: field value (stdout), empty string if not found
_claude_extract_field() {
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

# Build a stream-json user message from plain text prompt
# Args: $1 - prompt content (plain text)
# Returns: JSON message (stdout)
_claude_build_stream_message() {
  local _content="$1"
  local _encoded
  _encoded=$(printf '%s' "$_content" | awk '{
    gsub(/\\/, "\\\\")
    gsub(/"/, "\\\"")
    gsub(/\t/, "\\t")
    if (NR > 1) printf "\\n"
    printf "%s", $0
  }')
  printf '{"type":"user","message":{"role":"user","content":"%s"},"parent_tool_use_id":null,"session_id":"default"}' "$_encoded"
}

# Build an allow response for a control_request (requires node.js)
# Uses node for reliable JSON parsing — ~50ms per call, acceptable for infrequent permissions
# Args: $1 - control_request JSON line
# Returns: control_response JSON (stdout)
_claude_build_allow_response() {
  printf '%s' "$1" | node -e "
    const j=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    console.log(JSON.stringify({
      type:'control_response',
      response:{subtype:'success',request_id:j.request_id,
        response:{behavior:'allow',updatedInput:j.request.input}}
    }));
  "
}

# Build a deny response for a control_request (awk-based, no node needed)
# Args: $1 - control_request JSON line
# Returns: control_response JSON (stdout)
_claude_build_deny_response() {
  local _req_id
  _req_id=$(_claude_extract_field "$1" "request_id")
  printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":{"behavior":"deny","message":"User denied"}}}\n' "$_req_id"
}

# Handle a single control_request event
# Writes response to stdout (caller redirects to FD 7 → claude's stdin)
# Args: $1 - control_request JSON line
_claude_handle_control_request() {
  local _cr_line="$1"
  local _decision

  _decision=$(_permission_decide)

  case "$_decision" in
    allow)
      log_verbose "permission_filter: auto-approving permission request"
      _claude_build_allow_response "$_cr_line"
      ;;
    interactive)
      local _tool_name _reason
      _tool_name=$(_claude_extract_field "$_cr_line" "tool_name")
      _reason=$(_claude_extract_field "$_cr_line" "message")
      [ -z "$_reason" ] && _reason="Permission requested"

      local _user_decision
      _user_decision=$(_permission_prompt_user "$_tool_name" "$_reason")

      if [ "$_user_decision" = "allow" ]; then
        _claude_build_allow_response "$_cr_line"
      else
        _claude_build_deny_response "$_cr_line"
      fi
      ;;
    *)
      log_verbose "permission_filter: auto-denying (non-interactive, SKIP_PERMISSIONS=false)"
      _claude_build_deny_response "$_cr_line"
      ;;
  esac
}

# Pipeline filter: reads claude's stdout, intercepts control_requests,
# passes everything else downstream. Writes responses to the permission FD
# (default FD 7 = claude's stdin via FIFO).
# Must be called with FD $_CLAUDE_PERMISSION_FD open to the FIFO.
_claude_permission_filter() {
  while IFS= read -r _pf_line; do
    case "$_pf_line" in
      *'"type":"control_request"'*)
        _claude_handle_control_request "$_pf_line" >&"$_CLAUDE_PERMISSION_FD"
        ;;
      *'"type":"keep_alive"'*)
        : # Ignore keep-alive events
        ;;
      *'"type":"control_cancel_request"'*)
        : # Ignore cancel requests (we respond immediately, nothing to cancel)
        ;;
      *)
        printf '%s\n' "$_pf_line" 2>/dev/null || break
        ;;
    esac
  done
}
