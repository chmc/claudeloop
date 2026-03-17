#!/bin/sh

# Progress Tracking Library
# Manages PROGRESS.md file and tracks execution state

# Initialize progress tracking
# Args: $1 - progress file path
init_progress() {
  local progress_file="$1"

  # Initialize status for all phases as pending
  for _phase in $PHASE_NUMBERS; do
    reset_phase_full "$_phase"
  done

  # Read existing progress if file exists
  if [ -f "$progress_file" ]; then
    read_progress "$progress_file"
  fi
}

# Read progress from PROGRESS.md
read_progress() {
  local progress_file="$1"

  if [ ! -f "$progress_file" ]; then
    return 0
  fi

  # Parse PROGRESS.md to restore state
  local current_phase=""
  while IFS= read -r line || [ -n "$line" ]; do
    # Strip trailing whitespace (handles dirty PROGRESS.md from older versions)
    line="${line%"${line##*[![:space:]]}"}"
    # Match phase headers: ### ✅ Phase 1: Title or ### ✅ Phase 2.5: Title
    if is_progress_phase_header "$line"; then
      current_phase=$(extract_progress_phase_num "$line")
    elif [ -n "$current_phase" ]; then
      case "$line" in
        "Status: "*)
          local status_value
          status_value=$(printf '%s\n' "$line" | sed 's/^Status:[[:space:]]*//')
          # Normalize stale in_progress (e.g. from SIGKILL) so the phase retries
          [ "$status_value" = "in_progress" ] && status_value="pending"
          # Validate status enum
          case "$status_value" in
            pending|completed|failed) ;;
            *)
              log_verbose "Warning: invalid status '$status_value' for Phase $current_phase, resetting to pending"
              status_value="pending"
              ;;
          esac
          phase_set STATUS "$current_phase" "$status_value"
          ;;
        "Started: "*)
          local time_value
          time_value=$(printf '%s\n' "$line" | sed 's/^Started:[[:space:]]*//')
          phase_set START_TIME "$current_phase" "$time_value"
          ;;
        "Completed: "*)
          local time_value
          time_value=$(printf '%s\n' "$line" | sed 's/^Completed:[[:space:]]*//')
          phase_set END_TIME "$current_phase" "$time_value"
          ;;
        "Attempts: "*)
          local attempts_value
          attempts_value=$(printf '%s\n' "$line" | sed 's/^Attempts:[[:space:]]*//')
          printf '%s' "$attempts_value" | grep -qE '^[0-9]+$' || attempts_value=0
          phase_set ATTEMPTS "$current_phase" "$attempts_value"
          ;;
        "Attempt "[0-9]*)
          local _anum _atime
          _anum=$(printf '%s\n' "$line" | sed 's/^Attempt \([0-9]*\) Started:.*/\1/')
          _atime=$(printf '%s\n' "$line" | sed 's/^Attempt [0-9]* Started:[[:space:]]*//')
          phase_set ATTEMPT_TIME "$current_phase" "$_atime" "$_anum"
          ;;
        "Refactor: "*)
          local rv
          rv=$(printf '%s\n' "$line" | sed 's/^Refactor:[[:space:]]*//')
          phase_set REFACTOR_STATUS "$current_phase" "$rv"
          ;;
        "Refactor SHA: "*)
          local sv
          sv=$(printf '%s\n' "$line" | sed 's/^Refactor SHA:[[:space:]]*//')
          phase_set REFACTOR_SHA "$current_phase" "$sv"
          ;;
        "Refactor Attempts: "*)
          local ra
          ra=$(printf '%s\n' "$line" | sed 's/^Refactor Attempts:[[:space:]]*//')
          phase_set REFACTOR_ATTEMPTS "$current_phase" "$ra"
          ;;
      esac
    fi
  done < "$progress_file"

  return 0
}

# Write/update PROGRESS.md
# Args: $1 - progress file path, $2 - plan file path
write_progress() {
  local progress_file="$1"
  local plan_file="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  mkdir -p "$(dirname "$progress_file")"
  local temp_file="${progress_file}.tmp"

  cat > "$temp_file" << EOF
# Progress for $plan_file
Last updated: $timestamp

## Status Summary
$(generate_status_summary)

## Phase Details

$(generate_phase_details)
EOF

  # Atomic update
  mv "$temp_file" "$progress_file"

  # Generate flight recorder HTML (non-blocking, failure-tolerant)
  if command -v generate_flight_recorder >/dev/null 2>&1; then
    generate_flight_recorder "$(dirname "$progress_file")" 2>/dev/null || true
  fi
}

# Generate status summary section
generate_status_summary() {
  local total="$PHASE_COUNT"
  local completed=0
  local in_progress=0
  local pending=0
  local failed=0

  for _phase in $PHASE_NUMBERS; do
    local status
    status=$(get_phase_status "$_phase")
    case "$status" in
      completed)   completed=$((completed + 1)) ;;
      in_progress) in_progress=$((in_progress + 1)) ;;
      pending)     pending=$((pending + 1)) ;;
      failed)      failed=$((failed + 1)) ;;
    esac
  done

  echo "- Total phases: $total"
  echo "- Completed: $completed"
  echo "- In progress: $in_progress"
  echo "- Pending: $pending"
  echo "- Failed: $failed"
}

# Generate phase details section
generate_phase_details() {
  for _phase in $PHASE_NUMBERS; do
    local status
    status=$(get_phase_status "$_phase")
    local title
    title=$(get_phase_title "$_phase")
    local icon="⏳"

    case "$status" in
      completed)   icon="✅" ;;
      in_progress) icon="🔄" ;;
      failed)      icon="❌" ;;
      pending)     icon="⏳" ;;
    esac

    printf '### %s Phase %s: %s\n' "$icon" "$_phase" "$title"
    echo "Status: $status"

    local start_time
    start_time=$(get_phase_start_time "$_phase")
    if [ -n "$start_time" ]; then
      echo "Started: $start_time"
    fi

    local end_time
    end_time=$(get_phase_end_time "$_phase")
    if [ -n "$end_time" ] && { [ "$status" = "completed" ] || [ "$status" = "failed" ]; }; then
      echo "Completed: $end_time"
    fi

    local attempts
    attempts=$(get_phase_attempts "$_phase")
    if [ "$attempts" -gt 0 ]; then
      echo "Attempts: $attempts"
      if [ "$attempts" -gt 1 ]; then
        local _i=1
        while [ "$_i" -le "$attempts" ]; do
          local _at
          _at=$(get_phase_attempt_time "$_phase" "$_i")
          [ -n "$_at" ] && echo "Attempt $_i Started: $_at"
          _i=$((_i + 1))
        done
      fi
    fi

    local refactor_status
    refactor_status=$(get_phase_refactor_status "$_phase")
    if [ -n "$refactor_status" ]; then
      echo "Refactor: $refactor_status"
      case "$refactor_status" in
        "in_progress"*)
          local refactor_sha
          refactor_sha=$(get_phase_refactor_sha "$_phase")
          [ -n "$refactor_sha" ] && echo "Refactor SHA: $refactor_sha"
          local refactor_attempts
          refactor_attempts=$(get_phase_refactor_attempts "$_phase")
          [ -n "$refactor_attempts" ] && echo "Refactor Attempts: $refactor_attempts"
          ;;
      esac
    fi

    local deps
    deps=$(get_phase_dependencies "$_phase")
    if [ -n "$deps" ]; then
      printf 'Depends on:'
      for dep in $deps; do
        local dep_status
        dep_status=$(get_phase_status "$dep")
        local dep_icon="⏳"
        case "$dep_status" in
          completed) dep_icon="✅" ;;
          failed)    dep_icon="❌" ;;
        esac
        printf ' Phase %s %s' "$dep" "$dep_icon"
      done
      echo ""
    fi

    echo ""
  done
}

# Plan change detection, orphan detection, and recovery are in lib/plan_changes.sh

# Update phase status
# Args: $1 - phase number, $2 - new status
update_phase_status() {
  local phase_num="$1"
  local new_status="$2"

  phase_set STATUS "$phase_num" "$new_status"

  case "$new_status" in
    in_progress)
      local _now
      _now=$(date '+%Y-%m-%d %H:%M:%S')
      phase_set START_TIME "$phase_num" "$_now"
      phase_set END_TIME "$phase_num" ""
      local attempts
      attempts=$(get_phase_attempts "$phase_num")
      phase_set ATTEMPTS "$phase_num" "$((attempts + 1))"
      local _new_attempt=$((attempts + 1))
      phase_set ATTEMPT_TIME "$phase_num" "$_now" "$_new_attempt"
      ;;
    completed|failed)
      phase_set END_TIME "$phase_num" "$(date '+%Y-%m-%d %H:%M:%S')"
      ;;
  esac
}
