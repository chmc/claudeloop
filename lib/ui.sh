#!/bin/sh

# Terminal UI Library
# Handles terminal output and progress display

# Colors
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

# Simple mode flag (no fancy UI)
SIMPLE_MODE="${SIMPLE_MODE:-false}"

# Write a line to the live log (no-op when LIVE_LOG is unset)
# Empty string writes a bare newline; any other string gets a [HH:MM:SS] prefix.
log_live() {
  [ -n "${LIVE_LOG:-}" ] || return 0
  if [ -z "$1" ]; then
    printf '\n' >> "$LIVE_LOG"
  else
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$LIVE_LOG"
  fi
}

# Print a timestamped message to stdout and live log
# Args: $1 - message
log_ts() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1"
  log_live "$1"
}

# Print a timestamped message to stderr and live log
# Args: $1 - message
log_ts_err() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1" >&2
  log_live "$1"
}

# Print a sub-step header (verification, refactoring, etc.)
# Args: $1 - icon, $2 - message
print_substep_header() {
  if [ "$SIMPLE_MODE" = "true" ]; then
    log_ts "$2"
    return
  fi
  local timestamp
  timestamp=$(date "+%H:%M:%S")
  echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  printf '%b\n' "${COLOR_BLUE}[$timestamp] $1 $2${COLOR_RESET}"
  log_live "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  log_live "$1 $2"
}

# Print startup logo (block letters with gradient)
print_logo() {
  [ "$SIMPLE_MODE" = "true" ] && return 0
  printf '%b\n' ""
  printf '%b\n' "${COLOR_BLUE}   ██████╗ ██╗      █████╗ ██╗   ██╗██████╗ ███████╗"
  printf '%b\n' "${COLOR_BLUE}  ██╔════╝ ██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝"
  printf '%b\n' "${COLOR_BLUE}  ██║      ██║     ███████║██║   ██║██║  ██║█████╗"
  printf '%b\n' "${COLOR_CYAN}  ██║      ██║     ██╔══██║██║   ██║██║  ██║██╔══╝"
  printf '%b\n' "${COLOR_CYAN}  ╚██████╗ ███████╗██║  ██║╚██████╔╝██████╔╝███████╗"
  printf '%b\n' "${COLOR_CYAN}   ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝"
  printf '%b\n' "${COLOR_CYAN}       ██╗      ██████╗  ██████╗ ██████╗"
  printf '%b\n' "${COLOR_GREEN}       ██║     ██╔═══██╗██╔═══██╗██╔══██╗"
  printf '%b\n' "${COLOR_GREEN}       ██║     ██║   ██║██║   ██║██████╔╝"
  printf '%b\n' "${COLOR_GREEN}       ██║     ██║   ██║██║   ██║██╔═══╝"
  printf '%b\n' "${COLOR_GREEN}       ███████╗╚██████╔╝╚██████╔╝██║"
  printf '%b\n' "${COLOR_GREEN}       ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝${COLOR_RESET}"
  printf '%b\n' ""
  printf '        claudeloop%s\n\n' "${VERSION:+ v${VERSION}}"
}

# Print header
print_header() {
  local plan_file="$1"
  local completed=0
  local status

  for _phase in $PHASE_NUMBERS; do
    status=$(get_phase_status "$_phase")
    status="${status:-pending}"
    if [ "$status" = "completed" ]; then
      completed=$((completed + 1))
    fi
  done

  echo "═══════════════════════════════════════════════════════════"
  echo "ClaudeLoop${VERSION:+ v${VERSION}} - Phase-by-Phase Execution"
  echo "═══════════════════════════════════════════════════════════"
  echo "Plan: $plan_file"
  echo "Progress: $completed/$PHASE_COUNT phases completed"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
}

# Print phase status
print_phase_status() {
  local phase_num="$1"
  local status
  status=$(get_phase_status "$phase_num")
  status="${status:-pending}"
  local title
  title=$(get_phase_title "$phase_num")
  title="${title:-Unknown}"
  local icon="⏳"
  local color="$COLOR_RESET"

  case "$status" in
    completed)
      icon="✅"
      color="$COLOR_GREEN"
      ;;
    in_progress)
      icon="🔄"
      color="$COLOR_YELLOW"
      ;;
    failed)
      icon="❌"
      color="$COLOR_RED"
      ;;
    pending)
      icon="⏳"
      color="$COLOR_RESET"
      ;;
  esac

  printf '%b%s%b\n' "${color}${icon} Phase $phase_num: " "$title" "${COLOR_RESET}"
}

# Print all phases
print_all_phases() {
  for _phase in $PHASE_NUMBERS; do
    print_phase_status "$_phase"
  done
  echo ""
}

# Print rich completion summary after successful run
# Args: $1 = plan_file, $2 = replay_path (empty if unavailable)
print_completion_summary() {
  local plan_file="$1"
  local replay_path="$2"
  local completed=0
  local status

  for _phase in $PHASE_NUMBERS; do
    status=$(get_phase_status "$_phase")
    [ "${status:-pending}" = "completed" ] && completed=$((completed + 1))
  done

  echo "═══════════════════════════════════════════════════════════"
  echo "Run Summary — $completed/$PHASE_COUNT phases completed"
  echo "═══════════════════════════════════════════════════════════"
  printf 'Plan:   %s\n' "$plan_file"
  if [ -n "$replay_path" ]; then
    printf 'Report: %s\n' "$replay_path"
  fi
  echo ""
  for _phase in $PHASE_NUMBERS; do
    printf '  '
    print_phase_status "$_phase"
  done
  echo ""
  echo "═══════════════════════════════════════════════════════════"
}

# Print phase execution header
print_phase_exec_header() {
  local phase_num="$1"
  local title
  title=$(get_phase_title "$phase_num")
  local attempt
  attempt=$(get_phase_attempts "$phase_num")

  local timestamp
  timestamp=$(date "+%H:%M:%S")

  echo ""
  log_live ""
  echo "───────────────────────────────────────────────────────────"
  log_live "───────────────────────────────────────────────────────────"
  printf '%b%s%b\n' "${COLOR_BLUE}[$timestamp] ▶ Executing Phase $phase_num/$PHASE_COUNT: " "$title" "${COLOR_RESET}"
  log_live "▶ Executing Phase $phase_num/$PHASE_COUNT: $title"
  if [ "$attempt" -gt 1 ]; then
    printf '%b\n' "${COLOR_YELLOW}[$timestamp] Attempt $attempt/$MAX_RETRIES${COLOR_RESET}"
    log_live "Attempt $attempt/$MAX_RETRIES"
    local _pi=1
    while [ "$_pi" -lt "$attempt" ]; do
      local _pt
      _pt=$(get_phase_attempt_time "$phase_num" "$_pi")
      [ -n "$_pt" ] && printf '%b\n' "${COLOR_YELLOW}  Attempt $_pi started: $_pt${COLOR_RESET}"
      _pi=$((_pi + 1))
    done
  fi
  echo "───────────────────────────────────────────────────────────"
  log_live "───────────────────────────────────────────────────────────"
  echo ""
  log_live ""
}

# Print success message
print_success() {
  local message="$1"
  printf '%b\n' "[$(date '+%H:%M:%S')] ${COLOR_GREEN}✓ $message${COLOR_RESET}"
  log_live "✓ $message"
}

# Print error message
print_error() {
  local message="$1"
  printf '%b\n' "[$(date '+%H:%M:%S')] ${COLOR_RED}✗ $message${COLOR_RESET}" >&2
  log_live "✗ $message"
}

# Print warning message
print_warning() {
  local message="$1"
  printf '%b\n' "[$(date '+%H:%M:%S')] ${COLOR_YELLOW}⚠ $message${COLOR_RESET}"
  log_live "⚠ $message"
}

# Print quota wait message
print_quota_wait() {
  local phase_num="$1"
  local wait_secs="$2"
  local wait_mins
  wait_mins=$(( wait_secs / 60 ))
  printf '%b\n' "[$(date '+%H:%M:%S')] ${COLOR_YELLOW}⏸ Phase $phase_num: usage limit reached. Waiting ${wait_secs}s (${wait_mins}m) before retrying...${COLOR_RESET}"
  log_live "⏸ Phase $phase_num: usage limit reached. Waiting ${wait_secs}s (${wait_mins}m) before retrying..."
  printf '%b\n' "[$(date '+%H:%M:%S')] ${COLOR_YELLOW}  Press Ctrl+C to stop and save state.${COLOR_RESET}"
  log_live "  Press Ctrl+C to stop and save state."
}

# Print a message only when VERBOSE_MODE is true
log_verbose() {
  [ "$VERBOSE_MODE" = "true" ] && printf '[verbose] %s\n' "$*" >&2 || true
}
