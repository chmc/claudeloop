#!/bin/sh
# Provider abstraction layer

SCRIPT_DIR_PROVIDER="${SCRIPT_DIR_PROVIDER:-$(cd "$(dirname "$0")" && pwd)}"

# Source active adapter
. "$SCRIPT_DIR_PROVIDER/adapters/claude.sh"

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
