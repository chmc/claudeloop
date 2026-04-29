#!/bin/sh
# Claude CLI adapter

_claude_exec_args() {
  printf '%s' '--input-format stream-json --output-format stream-json --permission-prompt-tool stdio --verbose --include-partial-messages'
}

_claude_print_args() {
  printf '%s' '--print --output-format=stream-json --verbose --include-partial-messages'
}

_claude_write_tool_pattern() {
  printf '%s' 'Edit|Write|NotebookEdit|Agent'
}
