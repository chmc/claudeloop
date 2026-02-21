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

# Write a line to the live log (no-op when LIVE_LOG is unset)
log_live() { [ -n "${LIVE_LOG:-}" ] && printf '%b\n' "$@" >> "$LIVE_LOG" || true; }

# Print startup logo (space ghost)
print_logo() {
  [ "$SIMPLE_MODE" = "true" ] && return 0
  printf '%b' "${COLOR_BLUE}"
  cat <<'EOF'
    *  ·  .  *  ·  .  *  ·  .

          .-""""""""-.
    .    /  ◉      ◉  \    .
     ·  |    .---.     |   ·
    .   |   /~~~~~\    |    .
     ·   \  `-----'   /   ·
    .     `.~~~~~~~~~.'     .
     ·   /  )       (  \   ·
    .   /  /  ) ( (  \  \   .
        ~~   ~~   ~~   ~~

EOF
  printf '%b' "${COLOR_RESET}"
  printf '        claudeloop%s\n\n' "${VERSION:+ v${VERSION}}"
}

# Print header
print_header() {
  local plan_file="$1"
  local completed=0
  local status

  for _phase in $PHASE_NUMBERS; do
    local _pv
    _pv=$(phase_to_var "$_phase")
    status=$(eval "echo \"\${PHASE_STATUS_${_pv}:-}\"")
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
  local phase_var
  phase_var=$(phase_to_var "$phase_num")
  local status
  status=$(eval "echo \"\$PHASE_STATUS_${phase_var}\"")
  status="${status:-pending}"
  local title
  title=$(eval "echo \"\$PHASE_TITLE_${phase_var}\"")
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
  for _phase in $PHASE_NUMBERS; do
    print_phase_status "$_phase"
  done
  echo ""
}

# Print phase execution header
print_phase_exec_header() {
  local phase_num="$1"
  local phase_var
  phase_var=$(phase_to_var "$phase_num")
  local title
  title=$(eval "echo \"\$PHASE_TITLE_${phase_var}\"")
  local attempt
  attempt=$(eval "echo \"\$PHASE_ATTEMPTS_${phase_var}\"")

  local timestamp
  timestamp=$(date "+%H:%M:%S")

  echo ""
  log_live ""
  echo "───────────────────────────────────────────────────────────"
  log_live "───────────────────────────────────────────────────────────"
  printf '%b\n' "${COLOR_BLUE}[$timestamp] ▶ Executing Phase $phase_num/$PHASE_COUNT: $title${COLOR_RESET}"
  log_live "[$timestamp] ▶ Executing Phase $phase_num/$PHASE_COUNT: $title"
  if [ "$attempt" -gt 1 ]; then
    printf '%b\n' "${COLOR_YELLOW}Attempt $attempt/$MAX_RETRIES${COLOR_RESET}"
    log_live "Attempt $attempt/$MAX_RETRIES"
  fi
  echo "───────────────────────────────────────────────────────────"
  log_live "───────────────────────────────────────────────────────────"
  echo ""
  log_live ""
}

# Print success message
print_success() {
  local message="$1"
  printf '%b\n' "${COLOR_GREEN}✓ $message${COLOR_RESET}"
  log_live "✓ $message"
}

# Print error message
print_error() {
  local message="$1"
  printf '%b\n' "${COLOR_RED}✗ $message${COLOR_RESET}" >&2
  log_live "✗ $message"
}

# Print warning message
print_warning() {
  local message="$1"
  printf '%b\n' "${COLOR_YELLOW}⚠ $message${COLOR_RESET}"
  log_live "⚠ $message"
}

# Print quota wait message
print_quota_wait() {
  local phase_num="$1"
  local wait_secs="$2"
  local wait_mins
  wait_mins=$(( wait_secs / 60 ))
  printf '%b\n' "${COLOR_YELLOW}⏸ Phase $phase_num: usage limit reached. Waiting ${wait_secs}s (${wait_mins}m) before retrying...${COLOR_RESET}"
  log_live "⏸ Phase $phase_num: usage limit reached. Waiting ${wait_secs}s (${wait_mins}m) before retrying..."
  printf '%b\n' "${COLOR_YELLOW}  Press Ctrl+C to stop and save state.${COLOR_RESET}"
  log_live "  Press Ctrl+C to stop and save state."
}
