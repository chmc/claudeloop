#!/opt/homebrew/bin/bash

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
  local i

  for i in $(seq 1 "$PHASE_COUNT"); do
    if [ "${PHASE_STATUS[$i]:-pending}" = "completed" ]; then
      completed=$((completed + 1))
    fi
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
  local status="${PHASE_STATUS[$phase_num]:-pending}"
  local title="${PHASE_TITLES[$phase_num]:-Unknown}"
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

  echo -e "${color}${icon} Phase $phase_num: $title${COLOR_RESET}"
}

# Print all phases
print_all_phases() {
  local i
  for i in $(seq 1 "$PHASE_COUNT"); do
    print_phase_status "$i"
  done
  echo ""
}

# Print phase execution header
print_phase_exec_header() {
  local phase_num="$1"
  local title="${PHASE_TITLES[$phase_num]}"
  local attempt="${PHASE_ATTEMPTS[$phase_num]}"

  echo ""
  echo "───────────────────────────────────────────────────────────"
  echo -e "${COLOR_BLUE}▶ Executing Phase $phase_num: $title${COLOR_RESET}"
  if [ "$attempt" -gt 1 ]; then
    echo -e "${COLOR_YELLOW}Attempt $attempt/$MAX_RETRIES${COLOR_RESET}"
  fi
  echo "───────────────────────────────────────────────────────────"
  echo ""
}

# Print success message
print_success() {
  local message="$1"
  echo -e "${COLOR_GREEN}✓ $message${COLOR_RESET}"
}

# Print error message
print_error() {
  local message="$1"
  echo -e "${COLOR_RED}✗ $message${COLOR_RESET}" >&2
}

# Print warning message
print_warning() {
  local message="$1"
  echo -e "${COLOR_YELLOW}⚠ $message${COLOR_RESET}"
}
