#!/bin/sh

# Permission Handler Library
# Routes permission handling to provider-specific implementations.
# Provides permission_filter() pipeline stage.
#
# Permission protocols differ by provider:
# - Claude: FD7/FIFO bidirectional stdio protocol
# - OpenCode: HTTP POST to session endpoint

# Source the appropriate permission adapter based on provider
if [ -n "$SCRIPT_DIR" ]; then
  case "${PROVIDER:-claude}" in
    claude)   . "$SCRIPT_DIR/lib/adapters/permission_claude.sh" ;;
    opencode) . "$SCRIPT_DIR/lib/adapters/permission_opencode.sh" ;;
    *)        . "$SCRIPT_DIR/lib/adapters/permission_claude.sh" ;;
  esac
fi

# Backwards-compatible FD variable (Claude only - ignored by OpenCode)
_PERMISSION_FD=${_CLAUDE_PERMISSION_FD:-7}

# Backwards-compatible function aliases
# These delegate to Claude-prefixed implementations (Claude adapter only)
# OpenCode adapter has its own implementations with _opencode_ prefix

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

# Route to provider-specific permission filter
permission_filter() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_permission_filter "$@" ;;
    *)        _claude_permission_filter "$@" ;;
  esac
}
