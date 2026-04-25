#!/bin/sh

# Lessons Library
# Captures per-phase metrics for self-improvement mode.
# Writes token-free metrics to .claudeloop/lessons.md.

LESSONS_FILE=".claudeloop/lessons.md"

# Initialize lessons file (create or clear)
# Called at session start before any phase execution.
lessons_init() {
  mkdir -p "$(dirname "$LESSONS_FILE")"
  : > "$LESSONS_FILE"
}

# Write phase metrics to lessons file
# Args: $1 - phase number
#       $2 - phase title
#       $3 - duration in seconds
#       $4 - exit status ("success" or "error")
lessons_write_phase() {
  local _phase="$1" _title="$2" _duration="$3" _exit="$4"
  local _attempts _retries

  # Get attempts from phase state (defaults to 1 if not set)
  _attempts=$(get_phase_attempts "$_phase")
  case "$_attempts" in ''|*[!0-9]*) _attempts=1 ;; esac

  # Retries = attempts - 1 (first attempt is not a retry)
  _retries=$((_attempts - 1))
  [ "$_retries" -lt 0 ] && _retries=0

  # Append to lessons file
  cat >> "$LESSONS_FILE" << EOF

## Phase $_phase: $_title
- retries: $_retries
- duration: ${_duration}s
- exit: $_exit
EOF
}
