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
