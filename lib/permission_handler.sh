#!/bin/sh

# Permission Handler Library
# Handles bidirectional stdio protocol for Claude Code permission requests.
# Provides permission_filter() pipeline stage and response builders.

# Extract a simple string field value from JSON using awk
# Args: $1 - JSON string, $2 - field name
# Returns: field value (stdout), empty string if not found
_extract_field() {
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
_build_stream_message() {
  local _content="$1"
  # JSON-encode the content (escape \, ", newlines, tabs)
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
_build_allow_response() {
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
_build_deny_response() {
  local _req_id
  _req_id=$(_extract_field "$1" "request_id")
  printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":{"behavior":"deny","message":"User denied"}}}\n' "$_req_id"
}

# Handle a single control_request event
# Writes response to stdout (caller redirects to FD 3 → claude's stdin)
# Args: $1 - control_request JSON line
_handle_control_request() {
  local _cr_line="$1"

  if [ "$SKIP_PERMISSIONS" = "true" ]; then
    # Auto-approve mode
    log_verbose "permission_filter: auto-approving permission request"
    _build_allow_response "$_cr_line"
    return
  fi

  # Interactive mode: check for TTY
  if [ -t 0 ] 2>/dev/null || [ -e /dev/tty ]; then
    local _tool_name _reason
    _tool_name=$(_extract_field "$_cr_line" "tool_name")
    _reason=$(_extract_field "$_cr_line" "message")
    [ -z "$_reason" ] && _reason="Permission requested"

    # Display on /dev/tty (not stdout, which is the pipeline)
    {
      printf '[%s] Permission requested: %s\n' "$(date '+%H:%M:%S')" "$_tool_name"
      printf '  Reason: %s\n' "$_reason"
      printf '  Allow? (y/n): '
    } > /dev/tty 2>/dev/null || true

    local _answer=""
    read -r _answer < /dev/tty 2>/dev/null || _answer="n"
    case "$_answer" in
      [Yy]|[Yy][Ee][Ss])
        _build_allow_response "$_cr_line"
        ;;
      *)
        _build_deny_response "$_cr_line"
        ;;
    esac
    return
  fi

  # Non-interactive, no skip: auto-deny
  log_verbose "permission_filter: auto-denying (non-interactive, SKIP_PERMISSIONS=false)"
  _build_deny_response "$_cr_line"
}

# FD used for writing control_responses back to claude's stdin via FIFO.
# Default FD 7 (avoids conflict with bats FD 3 and shell FDs 0-2).
# Callers open this FD before starting the pipeline:
#   exec 7<>"$_fifo"; ... | permission_filter | ...
_PERMISSION_FD=${_PERMISSION_FD:-7}

# Pipeline filter: reads claude's stdout, intercepts control_requests,
# passes everything else downstream. Writes responses to the permission FD
# (default FD 7 = claude's stdin via FIFO).
# Must be called with FD $_PERMISSION_FD open to the FIFO.
permission_filter() {
  while IFS= read -r _pf_line; do
    case "$_pf_line" in
      *'"type":"control_request"'*)
        _handle_control_request "$_pf_line" >&"$_PERMISSION_FD"
        ;;
      *'"type":"keep_alive"'*)
        : # Ignore keep-alive events
        ;;
      *'"type":"control_cancel_request"'*)
        : # Ignore cancel requests (we respond immediately, nothing to cancel)
        ;;
      *)
        printf '%s\n' "$_pf_line"  # Pass through to downstream
        ;;
    esac
  done
}
