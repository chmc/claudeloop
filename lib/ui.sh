#!/bin/sh

# Terminal UI Library
# Handles terminal output and progress display

# Colors
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# Simple mode flag (no fancy UI)
SIMPLE_MODE="${SIMPLE_MODE:-false}"

# Print header
print_header() {
  local plan_file="$1"
  local completed=0
  local i=1
  local status

  while [ "$i" -le "$PHASE_COUNT" ]; do
    status=$(eval "echo \"\${PHASE_STATUS_$i:-}\"")
    status="${status:-pending}"
    if [ "$status" = "completed" ]; then
      completed=$((completed + 1))
    fi
    i=$((i + 1))
  done

  echo "═══════════════════════════════════════════════════════════"
  echo "ClaudeLoop - Phase-by-Phase Execution"
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
  status=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")
  status="${status:-pending}"
  local title
  title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
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

  printf '%b\n' "${color}${icon} Phase $phase_num: $title${COLOR_RESET}"
}

# Print all phases
print_all_phases() {
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    print_phase_status "$i"
    i=$((i + 1))
  done
  echo ""
}

# Print phase execution header
print_phase_exec_header() {
  local phase_num="$1"
  local title
  title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
  local attempt
  attempt=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")

  echo ""
  echo "───────────────────────────────────────────────────────────"
  printf '%b\n' "${COLOR_BLUE}▶ Executing Phase $phase_num: $title${COLOR_RESET}"
  if [ "$attempt" -gt 1 ]; then
    printf '%b\n' "${COLOR_YELLOW}Attempt $attempt/$MAX_RETRIES${COLOR_RESET}"
  fi
  echo "───────────────────────────────────────────────────────────"
  echo ""
}

# Print success message
print_success() {
  local message="$1"
  printf '%b\n' "${COLOR_GREEN}✓ $message${COLOR_RESET}"
}

# Print error message
print_error() {
  local message="$1"
  printf '%b\n' "${COLOR_RED}✗ $message${COLOR_RESET}" >&2
}

# Print warning message
print_warning() {
  local message="$1"
  printf '%b\n' "${COLOR_YELLOW}⚠ $message${COLOR_RESET}"
}

# Print quota wait message
print_quota_wait() {
  local phase_num="$1"
  local wait_secs="$2"
  local wait_mins
  wait_mins=$(( wait_secs / 60 ))
  printf '%b\n' "${COLOR_YELLOW}⏸ Phase $phase_num: usage limit reached. Waiting ${wait_secs}s (${wait_mins}m) before retrying...${COLOR_RESET}"
  printf '%b\n' "${COLOR_YELLOW}  Press Ctrl+C to stop and save state.${COLOR_RESET}"
}
