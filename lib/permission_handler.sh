#!/bin/sh

# Permission Handler Library
# Handles bidirectional stdio protocol for Claude Code permission requests.
# Provides permission_filter() pipeline stage and response builders.
#
# This module is a compatibility shim that sources the Claude adapter
# and re-exports functions under their original names.

# Source the Claude permission adapter
if [ -n "$SCRIPT_DIR" ]; then
  . "$SCRIPT_DIR/lib/adapters/permission_claude.sh"
fi

# Backwards-compatible FD variable
_PERMISSION_FD=${_CLAUDE_PERMISSION_FD:-7}

# Backwards-compatible function aliases
# These delegate to the Claude-prefixed implementations

_extract_field() {
  _claude_extract_field "$@"
}

_build_stream_message() {
  _claude_build_stream_message "$@"
}

_build_allow_response() {
  _claude_build_allow_response "$@"
}

_build_deny_response() {
  _claude_build_deny_response "$@"
}

_handle_control_request() {
  _claude_handle_control_request "$@"
}

permission_filter() {
  _claude_permission_filter "$@"
}
