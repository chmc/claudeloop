#!/bin/sh
# Claude CLI adapter

_claude_exec_args() {
  local _model="$MODEL"
  [ "${1:-}" = "verify" ] && [ -n "$MODEL_VERIFY" ] && _model="$MODEL_VERIFY"
  printf '%s' "--input-format stream-json --output-format stream-json --permission-prompt-tool stdio --verbose --include-partial-messages --effort $EFFORT_LEVEL${_model:+ --model $_model}"
}

_claude_print_args() {
  printf '%s' "--print --output-format=stream-json --verbose --include-partial-messages --model opus --effort $EFFORT_LEVEL"
}

_claude_write_tool_pattern() {
  printf '%s' 'Edit|Write|NotebookEdit|Agent'
}

_claude_verdict_pass_keyword() {
  printf '%s' 'VERIFICATION_PASSED'
}

_claude_verdict_fail_keyword() {
  printf '%s' 'VERIFICATION_FAILED'
}

# Returns permission protocol: "stdio" (FD7/FIFO), "http", or "none"
_claude_permission_protocol() {
  printf '%s' 'stdio'
}
