#!/bin/sh

# Retry Logic Library
# Handles retry attempts and fixed-delay retries

# Configuration
MAX_RETRIES="${MAX_RETRIES:-15}"
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

# Check if a phase log contains a rate-limit/quota error (not overloaded — see is_overload_error)
# Args: $1 - path to log file
# Returns: 0 if rate-limit error detected, 1 otherwise
is_rate_limit_error() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  grep -qiE "usage limit|quota|rate.?limit|too many requests|rate_limit_error" "$log_file"
}

# Backward-compatible alias
is_quota_error() { is_rate_limit_error "$@"; }

# Check if a phase log contains an overloaded/529 error
# Args: $1 - log file, $2 - raw JSON log (optional)
# Returns: 0 if overload error detected, 1 otherwise
is_overload_error() {
  local log_file="$1"
  local raw_file="${2:-}"
  local _olp="overloaded|overloaded_error|529"
  [ -f "$log_file" ] && grep -qiE "$_olp" "$log_file" && return 0
  [ -n "$raw_file" ] && [ -f "$raw_file" ] && grep -qiE "$_olp" "$raw_file" && return 0
  return 1
}

# Check if a phase log contains a server error (500/502/503/api_error)
# Args: $1 - log file, $2 - raw JSON log (optional)
# Returns: 0 if server error detected, 1 otherwise
is_server_error() {
  local log_file="$1"
  local raw_file="${2:-}"
  local _sep="api_error|internal_server_error|[Ss]erver error|HTTP 50[023]"
  [ -f "$log_file" ] && grep -qiE "$_sep" "$log_file" && return 0
  [ -n "$raw_file" ] && [ -f "$raw_file" ] && grep -qiE "$_sep" "$raw_file" && return 0
  return 1
}

# Check if a phase log contains a request timeout error (408)
# Args: $1 - log file
# Returns: 0 if timeout error detected, 1 otherwise
is_timeout_error() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  grep -qiE "request_timeout|HTTP 408|request timed out|\[tool timeout after |\[idle timeout after |\[dead connection timeout after " "$log_file"
}

# Check if a phase log contains an unanswered permission prompt from Claude
# Args: $1 - path to log file
# Returns: 0 if permission error detected, 1 otherwise
is_permission_error() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  grep -qiE "write permissions haven't been granted|approve the file write|approve.*write operation|permission to write|hasn't been granted" "$log_file"
}

# Check if a phase log contains network/connectivity error output
# Checks both the formatted log and the raw JSON log (errors may only appear in one).
# Args: $1 - path to log file
# Returns: 0 if network error detected, 1 otherwise
is_network_error() {
  local log_file="$1"
  local raw_file _net_pat
  _net_pat="connection (refused|reset|error|closed)|could not connect|network.*(unreachable|error|timeout)|dns.*(fail|error|resolv)|ssl.*(error|handshake)|socket (timeout|hang up)|ETIMEDOUT|ECONNREFUSED|ECONNRESET|ENETUNREACH|EPIPE|fetch failed"
  # Check formatted log
  [ -f "$log_file" ] && grep -qiE "$_net_pat" "$log_file" && return 0
  # Check raw JSON log (errors may only appear there)
  raw_file="$(dirname "$log_file")/raw-phase-$(basename "$log_file" .log | sed 's/^phase-//').json"
  [ -f "$raw_file" ] && grep -qiE "$_net_pat" "$raw_file" && return 0
  return 1
}

# Check if a phase log contains authentication/authorization error output
# Checks both the formatted log and the raw JSON log (errors may only appear in one).
# Args: $1 - path to log file
# Returns: 0 if auth error detected, 1 otherwise
is_auth_error() {
  local log_file="$1"
  local raw_file _auth_pat
  _auth_pat="authentication_error|invalid.*credentials|invalid.api.key|not_authorized|permission_error|not_found_error"
  [ -f "$log_file" ] && grep -qiE "$_auth_pat" "$log_file" && return 0
  raw_file="$(dirname "$log_file")/raw-phase-$(basename "$log_file" .log | sed 's/^phase-//').json"
  [ -f "$raw_file" ] && grep -qiE "$_auth_pat" "$raw_file" && return 0
  return 1
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
# with turns > 0 AND non-zero output tokens (real work was done). Scoped to the last
# execution block to avoid cross-attempt contamination in multi-attempt logs.
# Multiple [Session:] lines per phase are normal (background sub-invocations each emit one).
# Rejects API 500 errors where Claude CLI reports turns=1 but tokens=0in/0out.
# Args: $1 - path to log file
# Returns: 0 if successful session found in current attempt, 1 otherwise
has_successful_session() {
  local log_file="$1"
  [ -f "$log_file" ] || return 1
  awk 'BEGIN{in_response=1}
       /^=== EXECUTION START /{found=0; in_response=0; next}
       /^=== RESPONSE ===$/{in_response=1; next}
       /^=== EXECUTION END /{in_response=0; next}
       in_response && /\[Session:/ && /turns=[1-9]/ && /\/[1-9][0-9]*out/{found=1}
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

# Check if a no-changes signal file exists for a phase
# Written by Claude when a phase requires no code changes (verification-only)
# Args: $1 - phase number
# Returns: 0 if signal file exists, 1 otherwise
has_signal_file() {
  [ -f ".claudeloop/signals/phase-${1}.md" ]
}

# Check if the most recent execution block contains tool call patterns
# trapped inside thinking content (model formatting bug where tool calls
# are emitted as XML inside thinking instead of proper tool_use blocks).
# Matches assembled assistant messages only (not partial deltas).
# Args: $1 - path to raw JSON log file (.raw.json)
# Returns: 0 if trapped tool calls found, 1 otherwise
has_trapped_tool_calls() {
  local raw_log="$1"
  [ -f "$raw_log" ] || return 1
  awk '
    /^=== EXECUTION START /{found=0; next}
    /"type":"thinking","thinking":/ && /function=/ {found=1}
    /"type":"thinking","thinking":/ && /<tool_call>/ {found=1}
    END{exit (found ? 0 : 1)}
  ' "$raw_log"
}

# Map failure reason code to a human-readable hint for the retry prompt
# Args: $1 - failure reason code, $2 - consecutive count (optional, default 1)
# Returns: hint string (stdout), empty for unknown/empty codes
fail_reason_hint() {
  local _reason="$1"
  local _consec="${2:-1}"
  case "$_consec" in ''|*[!0-9]*) _consec=1 ;; esac

  case "$_reason" in
    no_write_actions)
      if [ "$_consec" -ge 3 ]; then
        echo "CRITICAL: You have failed to make any file changes $_consec consecutive times. You MUST use Edit or Write tools to modify files. Start with a single Read, then immediately Edit."
      else
        echo "You MUST use Edit or Write tools to modify files. Start by reading the most relevant file, then edit it."
      fi
      ;;
    trapped_tool_calls)
      if [ "$_consec" -ge 3 ]; then
        echo "CRITICAL: Your tool calls have been trapped in thinking blocks $_consec consecutive times. You MUST emit tool_use content blocks, not XML inside thinking. Start with a single, simple tool call."
      else
        echo "Your tool calls were trapped inside thinking blocks and never executed. Emit tool calls as top-level actions, not inside thinking."
      fi
      ;;
    empty_log)
      echo "You must actively use tools. Start with Read, then Edit." ;;
    no_session)
      echo "The previous attempt crashed or was killed before completing. Start fresh and work through the task methodically." ;;
    verification_failed)
      echo "Your previous changes failed verification. See the verification section below for details." ;;
    permission_denied)
      echo "Permission was denied for a file operation. Skip the denied file or use a different approach." ;;
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

# Escalate retry strategy for persistent model-behavior failures
# Never downgrades — if base strategy is already higher, keep it.
# Args: $1 - base strategy, $2 - fail reason, $3 - consecutive count
# Returns: escalated strategy (stdout)
escalate_strategy() {
  local _base="$1" _reason="$2" _consec="$3"
  case "$_consec" in ''|*[!0-9]*) _consec=0 ;; esac

  local _escalated="$_base"
  case "$_reason" in
    trapped_tool_calls|no_write_actions|permission_denied)
      if [ "$_consec" -ge 5 ]; then
        _escalated="targeted"
      elif [ "$_consec" -ge 3 ]; then
        # Only upgrade if base is lower
        case "$_base" in
          standard) _escalated="stripped" ;;
        esac
      fi
      ;;
  esac
  echo "$_escalated"
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
#        $7 - consecutive fail count (optional, default 1)
# Returns: formatted retry context section (stdout)
build_retry_context() {
  local strategy="$1" attempt="$2" max="$3" reason="$4" log_file="$5" verify_log="$6"
  local consec="${7:-1}"
  local prev_attempt=$((attempt - 1))
  local hint
  hint=$(fail_reason_hint "$reason" "$consec")

  # Model-behavior failures have no useful error context — skip extraction
  local _skip_ctx=false
  case "$reason" in trapped_tool_calls|no_write_actions|empty_log) _skip_ctx=true ;; esac

  case "$strategy" in
    standard)
      local error_ctx=""
      if [ "$_skip_ctx" = "false" ]; then
        error_ctx=$(extract_error_context "$log_file" 30)
      fi
      printf '## Previous Attempt Failed (attempt %s of %s)\n\n' "$prev_attempt" "$max"
      printf 'The previous attempt exited without completing the phase.\n'
      [ -n "$hint" ] && printf '%s\n' "$hint"
      if [ -n "$error_ctx" ]; then
        printf '\nHere is the relevant output from the previous attempt:\n\n```\n%s\n```\n' "$error_ctx"
      fi
      printf '\nAddress any errors shown before proceeding.\n'
      ;;
    stripped)
      local error_ctx=""
      if [ "$_skip_ctx" = "false" ]; then
        error_ctx=$(extract_error_context "$log_file" 15)
      fi
      printf '## Previous Attempt Failed (attempt %s of %s)\n\n' "$prev_attempt" "$max"
      [ -n "$hint" ] && printf '%s\n' "$hint"
      if [ -n "$error_ctx" ]; then
        printf '\n```\n%s\n```\n' "$error_ctx"
      fi
      ;;
    targeted)
      local ctx=""
      if [ "$_skip_ctx" = "false" ]; then
        if [ -n "$verify_log" ] && [ -f "$verify_log" ]; then
          ctx=$(extract_verify_error "$verify_log" 10)
        fi
        if [ -z "$ctx" ]; then
          ctx=$(extract_error_context "$log_file" 10)
        fi
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
