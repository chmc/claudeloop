#!/bin/sh

# Retry Logic Library
# Handles retry attempts and fixed-delay retries

# Configuration
MAX_RETRIES="${MAX_RETRIES:-10}"
BASE_DELAY="${BASE_DELAY:-3}"
QUOTA_RETRY_INTERVAL="${QUOTA_RETRY_INTERVAL:-900}"

# Calculate backoff delay (fixed delay between retries)
# Args: $1 - attempt number
# Returns: delay in seconds (stdout)
calculate_backoff() {
  local attempt="$1"
  case "$attempt" in ''|*[!0-9]*) ;; esac
  echo "$BASE_DELAY"
}

# Check if a phase log contains quota/rate-limit error output
# Args: $1 - path to log file
# Returns: 0 if quota error detected, 1 otherwise
is_quota_error() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  grep -qiE "usage limit|quota|rate.?limit|too many requests|rate_limit_error|overloaded" "$log_file"
}

# Check if a phase log contains an unanswered permission prompt from Claude
# Args: $1 - path to log file
# Returns: 0 if permission error detected, 1 otherwise
is_permission_error() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  grep -qiE "write permissions haven't been granted|approve the file write|approve.*write operation|permission to write|hasn't been granted" "$log_file"
}

# Check if a phase log is missing or empty (Claude produced no output)
# Args: $1 - path to log file
# Returns: 0 if empty/missing, 1 if non-empty
is_empty_log() {
  local log_file="$1"
  local has_response
  [ ! -f "$log_file" ] || [ ! -s "$log_file" ] && return 0
  # New-format logs: check if anything was written after the RESPONSE marker
  # and before the EXECUTION END marker
  if grep -q '^=== RESPONSE ===$' "$log_file"; then
    has_response=$(awk '
      /^=== RESPONSE ===$/{f=1; next}
      /^=== EXECUTION END /{exit}
      f && /[^[:space:]]/{print "yes"; exit}
    ' "$log_file")
    [ -z "$has_response" ] && return 0
    return 1
  fi
  # Old-format log (no marker): file is non-empty = not empty
  return 1
}

# Check if the most recent execution block in a phase log contains a [Session:] line
# with turns > 0 (real work was done). Scoped to the last execution block to avoid
# cross-attempt contamination in multi-attempt logs.
# Multiple [Session:] lines per phase are normal (background sub-invocations each emit one).
# Args: $1 - path to log file
# Returns: 0 if successful session found in current attempt, 1 otherwise
has_successful_session() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  awk '/^=== EXECUTION START /{found=0; next}
       /\[Session:/ && /turns=[1-9]/{found=1}
       END{exit (found ? 0 : 1)}' "$log_file"
}

# Check if the most recent execution block in a raw JSON log contains
# evidence of write actions (Edit, Write, NotebookEdit, or Agent tool calls).
# Args: $1 - path to raw JSON log file (.raw.json)
# Returns: 0 if write actions found, 1 otherwise
has_write_actions() {
  local raw_log="$1"
  [ -f "$raw_log" ] || return 1
  awk '
    /^=== EXECUTION START /{found=0; next}
    /"name":"Edit"/ || /"name":"Write"/ || /"name":"NotebookEdit"/ {found=1}
    /"name":"Agent"/ {found=1}
    END{exit (found ? 0 : 1)}
  ' "$raw_log"
}

# Map failure reason code to a human-readable hint for the retry prompt
# Args: $1 - failure reason code
# Returns: hint string (stdout), empty for unknown/empty codes
fail_reason_hint() {
  case "$1" in
    no_write_actions)
      echo "You MUST use Edit or Write tools to modify files. Start by reading the most relevant file, then edit it." ;;
    empty_log)
      echo "You must actively use tools. Start with Read, then Edit." ;;
    no_session)
      echo "The previous attempt crashed or was killed before completing. Start fresh and work through the task methodically." ;;
    verification_failed)
      echo "Your previous changes failed verification. See the verification section below for details." ;;
    *) ;;
  esac
}

# Check if attempt is past the midpoint of allowed retries.
# Args: $1 - current attempt, $2 - max retries
# Returns: 0 if past midpoint, 1 otherwise
past_retry_midpoint() {
  local attempt="$1"
  local max_retries="$2"
  [ "$max_retries" -gt 0 ] 2>/dev/null || return 1
  local half=$(( (max_retries + 1) / 2 ))
  [ "$attempt" -ge "$half" ]
}

# Determine retry strategy tier based on attempt number
# Args: $1 - current attempt, $2 - max retries
# Returns: "standard" (first 1/3), "stripped" (middle 1/3), or "targeted" (final 1/3)
retry_strategy() {
  local attempt="$1" max="$2"
  local third=$(( (max + 2) / 3 ))
  if [ "$attempt" -le "$third" ]; then
    echo "standard"
  elif [ "$attempt" -le $((third * 2)) ]; then
    echo "stripped"
  else
    echo "targeted"
  fi
}

# Determine verification mode based on attempt number
# Args: $1 - current attempt, $2 - max retries
# Returns: "full" (first 1/3), "quick" (middle 1/3), or "skip" (final 1/3)
verify_mode() {
  local attempt="$1" max="$2"
  local third=$(( (max + 2) / 3 ))
  if [ "$attempt" -le "$third" ]; then
    echo "full"
  elif [ "$attempt" -le $((third * 2)) ]; then
    echo "quick"
  else
    echo "skip"
  fi
}

# Extract error-relevant lines from a phase log's response section
# Searches for error patterns (error:, FAIL, SyntaxError, exit code, etc.)
# Falls back to tail of response section when no patterns match
# Args: $1 - path to log file, $2 - max lines to return
# Returns: focused error snippet (stdout), empty for missing/empty logs
extract_error_context() {
  local log_file="$1" max_lines="$2"
  [ -f "$log_file" ] && [ -s "$log_file" ] || return 0

  # Extract response section
  local response
  response=$(awk '
    /^=== RESPONSE ===$/ { found=1; next }
    /^=== EXECUTION END/ { exit }
    found { print }
  ' "$log_file")
  [ -n "$response" ] || return 0

  # Search for error patterns with surrounding context
  local errors
  errors=$(printf '%s\n' "$response" | grep -n -i -E \
    'error:|Error:|ERROR|FAIL|SyntaxError|TypeError|RuntimeError|exit code|not ok|assertion|traceback|panic' \
    2>/dev/null | head -n "$max_lines")

  if [ -n "$errors" ]; then
    # Get lines around the first error match
    local first_line
    first_line=$(printf '%s\n' "$errors" | head -1 | cut -d: -f1)
    local start=$((first_line - 3))
    [ "$start" -lt 1 ] && start=1
    printf '%s\n' "$response" | sed -n "${start},$((first_line + max_lines - 1))p" | head -n "$max_lines"
  else
    # No error patterns found — return tail of response
    printf '%s\n' "$response" | tail -n "$max_lines"
  fi
}

# Extract failure-relevant portion from a verification log
# Looks for VERIFICATION_FAILED marker and surrounding context
# Falls back to tail of log when no marker found
# Args: $1 - path to verify log file, $2 - max lines to return
# Returns: verification error snippet (stdout), empty for missing logs
extract_verify_error() {
  local log_file="$1" max_lines="$2"
  [ -f "$log_file" ] && [ -s "$log_file" ] || return 0

  # Search for VERIFICATION_FAILED marker
  local marker_line
  marker_line=$(grep -n 'VERIFICATION_FAILED' "$log_file" 2>/dev/null | head -1 | cut -d: -f1)

  if [ -n "$marker_line" ]; then
    local start=$((marker_line - max_lines / 2))
    [ "$start" -lt 1 ] && start=1
    sed -n "${start},$((marker_line + max_lines / 2))p" "$log_file" | head -n "$max_lines"
  else
    tail -n "$max_lines" "$log_file"
  fi
}

# Build strategy-aware retry context text for injection into prompts
# Args: $1 - strategy (standard|stripped|targeted)
#        $2 - current attempt, $3 - max retries
#        $4 - fail reason code, $5 - phase log path, $6 - verify log path
# Returns: formatted retry context section (stdout)
build_retry_context() {
  local strategy="$1" attempt="$2" max="$3" reason="$4" log_file="$5" verify_log="$6"
  local prev_attempt=$((attempt - 1))
  local hint
  hint=$(fail_reason_hint "$reason")

  case "$strategy" in
    standard)
      local error_ctx
      error_ctx=$(extract_error_context "$log_file" 30)
      printf '## Previous Attempt Failed (attempt %s of %s)\n\n' "$prev_attempt" "$max"
      printf 'The previous attempt exited without completing the phase.\n'
      [ -n "$hint" ] && printf '%s\n' "$hint"
      if [ -n "$error_ctx" ]; then
        printf '\nHere is the relevant output from the previous attempt:\n\n```\n%s\n```\n' "$error_ctx"
      fi
      printf '\nAddress any errors shown before proceeding.\n'
      ;;
    stripped)
      local error_ctx
      error_ctx=$(extract_error_context "$log_file" 15)
      printf '## Previous Attempt Failed (attempt %s of %s)\n\n' "$prev_attempt" "$max"
      [ -n "$hint" ] && printf '%s\n' "$hint"
      if [ -n "$error_ctx" ]; then
        printf '\n```\n%s\n```\n' "$error_ctx"
      fi
      ;;
    targeted)
      local ctx=""
      if [ -n "$verify_log" ] && [ -f "$verify_log" ]; then
        ctx=$(extract_verify_error "$verify_log" 10)
      fi
      if [ -z "$ctx" ]; then
        ctx=$(extract_error_context "$log_file" 10)
      fi
      printf '## Fix This Error (attempt %s of %s)\n\n' "$prev_attempt" "$max"
      if [ -n "$ctx" ]; then
        printf '```\n%s\n```\n' "$ctx"
      fi
      printf '\nFix the error. Test. Commit.\n'
      ;;
  esac
}

# Check if phase should be retried
# Args: $1 - phase number
# Returns: 0 if should retry, 1 if max retries exceeded
should_retry_phase() {
  local phase_num="$1"
  local attempts
  attempts=$(get_phase_attempts "$phase_num")

  # Guard against non-numeric attempts or MAX_RETRIES
  case "$attempts" in ''|*[!0-9]*) return 1 ;; esac
  case "$MAX_RETRIES" in ''|*[!0-9]*) return 1 ;; esac

  if [ "$attempts" -lt "$MAX_RETRIES" ]; then
    return 0
  else
    return 1
  fi
}
