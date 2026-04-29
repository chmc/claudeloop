#!/bin/sh
# Provider abstraction layer

# Source active adapter (SCRIPT_DIR is set by main claudeloop script)
. "$SCRIPT_DIR/lib/adapters/claude.sh"

# Detection - returns provider name
provider_detect() {
  printf 'claude\n'
}

# Return CLI binary name
provider_cli() {
  printf 'claude\n'
}

# Return execution mode flags (stream-json pipeline)
provider_exec_args() {
  _claude_exec_args
}

# Return print mode flags (AI parse)
provider_print_args() {
  _claude_print_args
}

# Return regex pattern for write-action tools
provider_write_tool_pattern() {
  _claude_write_tool_pattern
}

# Return keyword for verification pass verdict
provider_verdict_pass_keyword() {
  _claude_verdict_pass_keyword
}

# Return keyword for verification fail verdict
provider_verdict_fail_keyword() {
  _claude_verdict_fail_keyword
}

# Returns permission protocol: "stdio" (Claude FD7), "http" (OpenCode API), "none"
provider_permission_protocol() {
  _claude_permission_protocol
}
