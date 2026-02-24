#!/bin/sh

# Retry Logic Library
# Handles retry attempts and exponential backoff

# Configuration
MAX_RETRIES="${MAX_RETRIES:-5}"
BASE_DELAY="${BASE_DELAY:-5}"
MAX_DELAY="${MAX_DELAY:-60}"
QUOTA_RETRY_INTERVAL="${QUOTA_RETRY_INTERVAL:-900}"

# Calculate integer power: base^exp
power() {
  local base="$1"
  local exp="$2"
  local result=1
  local i=0
  while [ "$i" -lt "$exp" ]; do
    # Overflow guard: if result > MAX_INT / base, stop early
    if [ "$base" -gt 0 ] && [ "$result" -gt $((9223372036854775807 / base)) ]; then
      echo "$result"
      return 0
    fi
    result=$((result * base))
    i=$((i + 1))
  done
  echo "$result"
}

# Get a random integer in [0, max)
get_random() {
  local max="$1"
  if [ "$max" -le 0 ]; then
    echo 0
    return 0
  fi
  if [ -r /dev/urandom ]; then
    local random_bytes
    random_bytes=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
    echo $((random_bytes % max))
  else
    local seed
    seed=$(($(date +%s) + $$))
    echo $((seed % max))
  fi
}

# Calculate backoff delay
# Args: $1 - attempt number
# Returns: delay in seconds (stdout)
calculate_backoff() {
  local attempt="$1"
  local exp_value
  exp_value=$(power 2 $((attempt - 1)))
  local delay=$((BASE_DELAY * exp_value))

  if [ "$delay" -lt 0 ] || [ "$delay" -gt "$MAX_DELAY" ]; then
    delay=$MAX_DELAY
  fi

  # Add jitter (0-25% of delay)
  local jitter
  jitter=$(get_random $((delay / 4 + 1)))
  echo $((delay + jitter))
}

# Check if a phase log contains quota/rate-limit error output
# Args: $1 - path to log file
# Returns: 0 if quota error detected, 1 otherwise
is_quota_error() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  grep -qiE "usage limit|quota|rate.?limit|too many requests|429|rate_limit_error|overloaded" "$log_file"
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

# Check if phase should be retried
# Args: $1 - phase number
# Returns: 0 if should retry, 1 if max retries exceeded
should_retry_phase() {
  local phase_num="$1"
  local attempts
  attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$(phase_to_var "$phase_num")\"")

  if [ "$attempts" -lt "$MAX_RETRIES" ]; then
    return 0
  else
    return 1
  fi
}
