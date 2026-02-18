#!/opt/homebrew/bin/bash

# Retry Logic Library
# Handles retry attempts and exponential backoff

# Configuration
MAX_RETRIES="${MAX_RETRIES:-3}"
BASE_DELAY="${BASE_DELAY:-5}"
MAX_DELAY="${MAX_DELAY:-60}"

# Calculate backoff delay
# Args: $1 - attempt number
# Returns: delay in seconds (stdout)
calculate_backoff() {
  local attempt="$1"
  local delay=$((BASE_DELAY * (2 ** (attempt - 1))))

  if [ "$delay" -gt "$MAX_DELAY" ]; then
    delay=$MAX_DELAY
  fi

  # Add jitter (0-25% of delay)
  local jitter=$((RANDOM % (delay / 4 + 1)))
  echo $((delay + jitter))
}

# Check if phase should be retried
# Args: $1 - phase number
# Returns: 0 if should retry, 1 if max retries exceeded
should_retry_phase() {
  local phase_num="$1"
  local attempts="${PHASE_ATTEMPTS[$phase_num]}"

  if [ "$attempts" -lt "$MAX_RETRIES" ]; then
    return 0
  else
    return 1
  fi
}
