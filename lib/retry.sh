#!/bin/sh

# Retry Logic Library
# Handles retry attempts and exponential backoff

# Configuration
MAX_RETRIES="${MAX_RETRIES:-3}"
BASE_DELAY="${BASE_DELAY:-5}"
MAX_DELAY="${MAX_DELAY:-60}"
QUOTA_RETRY_INTERVAL="${QUOTA_RETRY_INTERVAL:-900}"

# Calculate integer power: base^exp
power() {
  base="$1"
  exp="$2"
  result=1
  i=0
  while [ "$i" -lt "$exp" ]; do
    result=$((result * base))
    i=$((i + 1))
  done
  echo "$result"
}

# Get a random integer in [0, max)
get_random() {
  max="$1"
  if [ -r /dev/urandom ]; then
    random_bytes=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
    echo $((random_bytes % max))
  else
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

  if [ "$delay" -gt "$MAX_DELAY" ]; then
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
  [ ! -s "$log_file" ]
}

# Check if phase should be retried
# Args: $1 - phase number
# Returns: 0 if should retry, 1 if max retries exceeded
should_retry_phase() {
  local phase_num="$1"
  local attempts
  attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")

  if [ "$attempts" -lt "$MAX_RETRIES" ]; then
    return 0
  else
    return 1
  fi
}
