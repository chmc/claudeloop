#!/bin/sh
# State management: save/load/clear session state and lock files

# Save current state to state file
save_state() {
  mkdir -p "$(dirname "$STATE_FILE")"

  local _json_plan _json_progress _json_phase
  _json_plan=$(printf '%s' "$PLAN_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _json_progress=$(printf '%s' "$PROGRESS_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _json_phase=$(printf '%s' "$CURRENT_PHASE" | sed 's/\\/\\\\/g; s/"/\\"/g')

  cat > "$STATE_FILE" << EOF
{
  "plan_file": "$_json_plan",
  "progress_file": "$_json_progress",
  "current_phase": "$_json_phase",
  "interrupted": true,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Load state from state file
load_state() {
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi

  # Simple parsing of JSON (basic implementation)
  if grep -q '"interrupted": true' "$STATE_FILE"; then
    # Skip interrupted prompt if all phases already completed;
    # the archive flow in main() will handle this case
    _sc=$(grep -c "^Status: " "$PROGRESS_FILE" 2>/dev/null) || _sc=0
    if [ "$_sc" -gt 0 ] \
       && ! grep "^Status: " "$PROGRESS_FILE" | sed 's/[[:space:]]*$//' | grep -qv "^Status: completed$"; then
      return 1
    fi

    _phase=$(grep '"current_phase"' "$STATE_FILE" | sed 's/.*"current_phase": *"\([^"]*\)".*/\1/')

    print_warning "Found interrupted session"
    if [ -n "$_phase" ]; then
      _title=$(get_phase_title "$_phase")
      printf '  Phase %s: %s\n' "$_phase" "$_title"
    fi
    if ! [ -t 0 ] || [ "$YES_MODE" = "true" ]; then
      response="y"
    else
      printf 'Resume from last checkpoint? (Y/n) '
      read -r response
    fi
    case "$response" in
      [Nn])
        rm -f "$STATE_FILE"
        return 1
        ;;
    esac
    return 0
  fi

  return 1
}

# Clear state file
clear_state() {
  rm -f "$STATE_FILE"
}

# Create lock file
create_lock() {
  local lock_dir
  lock_dir="$(dirname "$LOCK_FILE")"
  mkdir -p "$lock_dir"

  if [ -f "$LOCK_FILE" ]; then
    local pid
    pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      if [ "$FORCE_MODE" = "true" ]; then
        print_warning "Killing existing instance (PID: $pid) — progress is preserved"
        kill "$pid" 2>/dev/null || true
        local _wait=0
        while [ "$_wait" -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
          sleep 1
          _wait=$((_wait + 1))
        done
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$LOCK_FILE"
        FORCE_KILLED=true
      else
        print_error "Another instance is running (PID: $pid). Use --force to kill it, or run 'kill $pid' to stop it manually."
        exit 1
      fi
    else
      print_warning "Removing stale lock file"
      rm -f "$LOCK_FILE"
    fi
  fi

  echo $$ > "$LOCK_FILE"
}

# Remove lock file
remove_lock() {
  rm -f "$LOCK_FILE"
}
