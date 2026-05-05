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

# Provider-aware function wrappers
# Delegate to provider-specific implementations

_extract_field() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_extract_field "$@" ;;
    *)        _claude_extract_field "$@" ;;
  esac
}

_build_stream_message() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_build_stream_message "$@" ;;
    *)        _claude_build_stream_message "$@" ;;
  esac
}

_build_allow_response() {
  case "${PROVIDER:-claude}" in
    opencode) : ;; # OpenCode uses HTTP, no stream response needed
    *)        _claude_build_allow_response "$@" ;;
  esac
}

_build_deny_response() {
  case "${PROVIDER:-claude}" in
    opencode) : ;; # OpenCode uses HTTP, no stream response needed
    *)        _claude_build_deny_response "$@" ;;
  esac
}

_handle_control_request() {
  case "${PROVIDER:-claude}" in
    opencode) : ;; # OpenCode uses HTTP protocol, handled differently
    *)        _claude_handle_control_request "$@" ;;
  esac
}

# Route to provider-specific permission filter
permission_filter() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_permission_filter "$@" ;;
    *)        _claude_permission_filter "$@" ;;
  esac
}
