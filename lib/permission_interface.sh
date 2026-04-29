#!/bin/sh
# Permission Interface - Provider-agnostic decision logic
# This module provides shared permission decision logic that can be used
# by any provider adapter (Claude, OpenCode, etc.)

# Decide permission action based on config and environment
# Returns: "allow", "deny", or "interactive" (stdout)
_permission_decide() {
  if [ "$SKIP_PERMISSIONS" = "true" ]; then
    printf 'allow\n'
    return
  fi
  if [ -t 0 ] 2>/dev/null || [ -e /dev/tty ]; then
    printf 'interactive\n'
    return
  fi
  printf 'deny\n'
}

# Prompt user for permission via TTY (provider-agnostic)
# Args: $1 - tool name, $2 - reason
# Returns: "allow" or "deny"
_permission_prompt_user() {
  local _tool_name="$1" _reason="${2:-Permission requested}"
  {
    printf '[%s] Permission requested: %s\n' "$(date '+%H:%M:%S')" "$_tool_name"
    printf '  Reason: %s\n' "$_reason"
    printf '  Allow? (y/n): '
  } > /dev/tty 2>/dev/null || true
  local _answer=""
  read -r _answer < /dev/tty 2>/dev/null || _answer="n"
  case "$_answer" in
    [Yy]|[Yy][Ee][Ss]) printf 'allow\n' ;;
    *) printf 'deny\n' ;;
  esac
}
