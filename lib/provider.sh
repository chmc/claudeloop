#!/bin/sh
# Provider abstraction layer

# Source active adapter (SCRIPT_DIR is set by main claudeloop script)
case "${PROVIDER:-claude}" in
  claude)   . "$SCRIPT_DIR/lib/adapters/claude.sh" ;;
  opencode) . "$SCRIPT_DIR/lib/adapters/opencode.sh" ;;
  *)        . "$SCRIPT_DIR/lib/adapters/claude.sh" ;;
esac

# Detection - returns provider name
# Respects PROVIDER env/config variable if set
provider_detect() {
  if [ -n "$PROVIDER" ]; then
    case "$PROVIDER" in
      claude)   printf 'claude\n' ;;
      opencode) printf 'opencode\n' ;;
      *)
        printf 'Error: provider "%s" not yet supported\n' "$PROVIDER" >&2
        return 1
        ;;
    esac
    return 0
  fi
  # Auto-detect (currently only Claude)
  printf 'claude\n'
}

# Return CLI binary name
# CLAUDELOOP_CLAUDE_BIN overrides PATH lookup — use for testing (e.g. fake_claude)
provider_cli() {
  if [ -n "${CLAUDELOOP_CLAUDE_BIN:-}" ]; then
    printf '%s\n' "$CLAUDELOOP_CLAUDE_BIN"
    return
  fi
  case "${PROVIDER:-claude}" in
    opencode) _opencode_cli ;;
    *)        printf 'claude\n' ;;
  esac
}

# Return execution mode flags (stream-json pipeline)
provider_exec_args() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_exec_args "$@" ;;
    *)        _claude_exec_args "$@" ;;
  esac
}

# Return print mode flags (AI parse)
provider_print_args() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_print_args ;;
    *)        _claude_print_args ;;
  esac
}

# Return regex pattern for write-action tools
provider_write_tool_pattern() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_write_tool_pattern ;;
    *)        _claude_write_tool_pattern ;;
  esac
}

# Return keyword for verification pass verdict
provider_verdict_pass_keyword() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_verdict_pass_keyword ;;
    *)        _claude_verdict_pass_keyword ;;
  esac
}

# Return keyword for verification fail verdict
provider_verdict_fail_keyword() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_verdict_fail_keyword ;;
    *)        _claude_verdict_fail_keyword ;;
  esac
}

# Returns permission protocol: "stdio" (Claude FD7), "http" (OpenCode API), "none"
provider_permission_protocol() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_permission_protocol ;;
    *)        _claude_permission_protocol ;;
  esac
}

# Normalize provider events to Claude stream-json format
provider_normalize_events() {
  case "${PROVIDER:-claude}" in
    opencode) _opencode_normalize_events ;;
    *)        cat ;;
  esac
}
