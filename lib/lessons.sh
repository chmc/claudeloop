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

# Extract LESSONS_SUMMARY from a phase log file
# Args: $1 - log file path
# Returns: summary text on stdout (empty if not found)
extract_lessons_summary() {
  local _log_file="$1"
  [ -f "$_log_file" ] || return 0

  # Match LESSONS_SUMMARY: "..." or LESSONS_SUMMARY: '...' (last occurrence wins)
  # Use grep + sed for POSIX compatibility
  grep -o 'LESSONS_SUMMARY: *["'"'"'][^"'"'"']*["'"'"']' "$_log_file" 2>/dev/null | \
    tail -1 | \
    sed 's/^LESSONS_SUMMARY: *["'"'"']\(.*\)["'"'"']$/\1/'
}

# Write phase metrics to lessons file
# Args: $1 - phase number
#       $2 - phase title
#       $3 - duration in seconds
#       $4 - exit status ("success" or "error")
#       $5 - (optional) summary from Claude's LESSONS_SUMMARY marker
lessons_write_phase() {
  local _phase="$1" _title="$2" _duration="$3" _exit="$4" _summary="${5:-}"
  local _attempts _retries _fail_reason

  # Get attempts from phase state (defaults to 1 if not set)
  _attempts=$(get_phase_attempts "$_phase")
  case "$_attempts" in ''|*[!0-9]*) _attempts=1 ;; esac

  # Retries = attempts - 1 (first attempt is not a retry)
  _retries=$((_attempts - 1))
  [ "$_retries" -lt 0 ] && _retries=0

  # Get fail_reason if there were retries
  _fail_reason=""
  if [ "$_retries" -gt 0 ]; then
    _fail_reason=$(get_phase_fail_reason "$_phase")
  fi

  # Append to lessons file
  cat >> "$LESSONS_FILE" << EOF

## Phase $_phase: $_title
- retries: $_retries
- duration: ${_duration}s
- exit: $_exit
EOF

  # Add fail_reason line if present
  if [ -n "$_fail_reason" ]; then
    printf -- '- fail_reason: %s\n' "$_fail_reason" >> "$LESSONS_FILE"
  fi

  # Add summary line if present
  if [ -n "$_summary" ]; then
    printf -- '- summary: %s\n' "$_summary" >> "$LESSONS_FILE"
  fi
}

# Write final failure lesson for a phase (called when max retries exceeded)
# Args: $1 - phase number
#       $2 - total duration across all attempts (optional, defaults to 0)
lessons_write_final_failure() {
  local _phase="$1" _duration="${2:-0}"
  local _title _attempts _retries _fail_reason

  _title=$(get_phase_title "$_phase")
  _attempts=$(get_phase_attempts "$_phase")
  case "$_attempts" in ''|*[!0-9]*) _attempts=1 ;; esac
  _retries=$((_attempts - 1))
  [ "$_retries" -lt 0 ] && _retries=0
  _fail_reason=$(get_phase_fail_reason "$_phase")

  cat >> "$LESSONS_FILE" << EOF

## Phase $_phase: $_title
- retries: $_retries
- duration: ${_duration}s
- exit: error
EOF

  # Add fail_reason line if present
  if [ -n "$_fail_reason" ]; then
    printf -- '- fail_reason: %s\n' "$_fail_reason" >> "$LESSONS_FILE"
  fi
}
