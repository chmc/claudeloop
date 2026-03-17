#!/bin/sh

# Archive Library
# Manages archiving, listing, and restoring old plan run state

# Check if all phases are completed
# Returns 0 (true) if PHASE_COUNT > 0 and every phase status is "completed"
is_run_complete() {
  [ "$PHASE_COUNT" -gt 0 ] 2>/dev/null || return 1

  for _phase_num in $PHASE_NUMBERS; do
    local _status
    _status=$(get_phase_status "$_phase_num")
    [ "$_status" = "completed" ] || return 1
  done
  return 0
}

# Generate metadata.txt in an archive directory
# Args: $1 - archive directory path
generate_archive_metadata() {
  local archive_dir="$1"
  local _completed=0 _failed=0 _pending=0

  for _phase_num in $PHASE_NUMBERS; do
    local _status
    _status=$(get_phase_status "$_phase_num")
    case "$_status" in
      completed) _completed=$((_completed + 1)) ;;
      failed)    _failed=$((_failed + 1)) ;;
      *)         _pending=$((_pending + 1)) ;;
    esac
  done

  cat > "${archive_dir}/metadata.txt" << EOF
plan_file=$PLAN_FILE
archived_at=$(date '+%Y-%m-%d %H:%M:%S')
phase_count=$PHASE_COUNT
completed=$_completed
failed=$_failed
pending=$_pending
EOF
}

# Archive current run state into .claudeloop/archive/{timestamp}/
# Args: --internal (optional) to skip lock check
archive_current_run() {
  local _internal=false
  if [ "${1:-}" = "--internal" ]; then
    _internal=true
  fi

  # Lock check (external mode only)
  if [ "$_internal" = false ] && [ -f "$LOCK_FILE" ]; then
    local _pid
    _pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
      print_error "Another instance is running (PID: $_pid). Stop it first or use --internal."
      return 1
    else
      # Stale lock — remove and continue
      rm -f "$LOCK_FILE"
    fi
  fi

  # Check there is something to archive
  local _has_state=false
  for _item in .claudeloop/PROGRESS.md .claudeloop/logs .claudeloop/state .claudeloop/signals .claudeloop/live.log; do
    if [ -e "$_item" ]; then
      _has_state=true
      break
    fi
  done
  if [ "$_has_state" = false ]; then
    print_warning "Nothing to archive — no run state found"
    return 0
  fi

  # Create timestamped archive directory
  local _timestamp _archive_dir
  _timestamp=$(date '+%Y%m%d-%H%M%S')
  _archive_dir=".claudeloop/archive/${_timestamp}"
  if ! mkdir -p "$_archive_dir"; then
    print_error "Failed to create archive directory: $_archive_dir"
    return 1
  fi

  # 1. Copy plan file first (before moves)
  if [ -n "${PLAN_FILE:-}" ] && [ -f "$PLAN_FILE" ]; then
    cp "$PLAN_FILE" "${_archive_dir}/plan.md"
  fi

  # 2. Copy config file (preserves original for next run)
  if [ -f ".claudeloop/.claudeloop.conf" ]; then
    cp ".claudeloop/.claudeloop.conf" "${_archive_dir}/.claudeloop.conf"
  fi

  # 3. Move run-state items (POSIX glob safety)
  for _item in \
    .claudeloop/PROGRESS.md \
    .claudeloop/PROGRESS.md.bak \
    .claudeloop/state \
    .claudeloop/logs \
    .claudeloop/signals \
    .claudeloop/live.log \
    .claudeloop/ai-verify-reason.txt; do
    [ -e "$_item" ] || continue
    mv "$_item" "$_archive_dir/" 2>/dev/null || true
  done

  # Move live-*.log files (POSIX safe iteration)
  for _f in .claudeloop/live-*.log; do
    [ -e "$_f" ] || continue
    mv "$_f" "$_archive_dir/" 2>/dev/null || true
  done

  # 4. Generate metadata
  generate_archive_metadata "$_archive_dir"

  # 5. Announce
  print_success "Run archived to ${_archive_dir}"
}

# List all archived runs
list_archives() {
  local _archive_base=".claudeloop/archive"

  if [ ! -d "$_archive_base" ]; then
    print_warning "No archived runs found"
    return 0
  fi

  local _found=false
  local _header_printed=false

  for _dir in "$_archive_base"/*/; do
    [ -d "$_dir" ] || continue
    _found=true

    if [ "$_header_printed" = false ]; then
      printf '%-20s %-30s %6s %6s %6s %6s\n' "Name" "Plan" "Phases" "Done" "Fail" "Pend"
      printf '%-20s %-30s %6s %6s %6s %6s\n' "----" "----" "------" "----" "----" "----"
      _header_printed=true
    fi

    local _name _plan _phases _completed _failed _pending
    _name=$(basename "$_dir")

    if [ -f "${_dir}metadata.txt" ]; then
      _plan=$(grep '^plan_file=' "${_dir}metadata.txt" 2>/dev/null | cut -d= -f2-)
      _phases=$(grep '^phase_count=' "${_dir}metadata.txt" 2>/dev/null | cut -d= -f2-)
      _completed=$(grep '^completed=' "${_dir}metadata.txt" 2>/dev/null | cut -d= -f2-)
      _failed=$(grep '^failed=' "${_dir}metadata.txt" 2>/dev/null | cut -d= -f2-)
      _pending=$(grep '^pending=' "${_dir}metadata.txt" 2>/dev/null | cut -d= -f2-)
    else
      _plan="unknown"
      _phases="?"
      _completed="?"
      _failed="?"
      _pending="?"
    fi

    printf '%-20s %-30s %6s %6s %6s %6s\n' \
      "$_name" "${_plan:-unknown}" "${_phases:-?}" "${_completed:-?}" "${_failed:-?}" "${_pending:-?}"
  done

  if [ "$_found" = false ]; then
    print_warning "No archived runs found"
  fi
}

# Restore an archived run back to active state
# Args: $1 - archive name (timestamp directory name)
restore_archive() {
  local _name="$1"
  local _archive_dir=".claudeloop/archive/${_name}"

  if [ ! -d "$_archive_dir" ]; then
    print_error "No archive found: $_name"
    return 1
  fi

  # Refuse if active state exists
  local _has_active=false
  for _item in .claudeloop/PROGRESS.md .claudeloop/logs .claudeloop/state; do
    if [ -e "$_item" ]; then
      _has_active=true
      break
    fi
  done
  if [ "$_has_active" = true ]; then
    print_error "Active state exists — run --archive or --reset first"
    return 1
  fi

  # Move contents back (skip plan.md and metadata.txt — those are archive-only)
  for _item in "$_archive_dir"/*; do
    [ -e "$_item" ] || continue
    local _basename
    _basename=$(basename "$_item")
    case "$_basename" in
      plan.md|metadata.txt|.claudeloop.conf) continue ;;
    esac
    mv "$_item" ".claudeloop/" 2>/dev/null || true
  done

  # Remove archive directory (only plan.md and metadata.txt remain)
  rm -rf "$_archive_dir" 2>/dev/null || true

  print_success "Restored archive: $_name"
}

# Prompt user to archive a completed previous run
# Called from main() when is_run_complete() is true
# Args: --internal (optional) passed through to archive_current_run
prompt_archive_completed_run() {
  local _internal_flag=""
  if [ "${1:-}" = "--internal" ]; then
    _internal_flag="--internal"
  fi

  _ARCHIVE_COMPLETED=false
  _ARCHIVE_DECLINED=false

  print_warning "Previous run is complete (all phases finished)"

  local _response="y"
  if [ "$YES_MODE" = "true" ]; then
    _response="y"
  elif [ -t 0 ] || [ "${_ARCHIVE_FORCE_INTERACTIVE:-0}" = "1" ]; then
    printf 'Archive completed run and start fresh? [Y/n] '
    read -r _response
  fi

  case "$_response" in
    [Nn])
      _ARCHIVE_DECLINED=true
      return 0
      ;;
  esac

  log_ts "Archiving completed run..."
  archive_current_run $_internal_flag

  # Re-initialize progress: reset all phases to pending (safety net if exec fails)
  for _phase_num in $PHASE_NUMBERS; do
    reset_phase_full "$_phase_num"
  done
  RESUME_MODE=false
  _ARCHIVE_COMPLETED=true
}
