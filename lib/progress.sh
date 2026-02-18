#!/bin/sh

# Progress Tracking Library
# Manages PROGRESS.md file and tracks execution state

# Initialize progress tracking
# Args: $1 - progress file path
init_progress() {
  local progress_file="$1"

  # Initialize status for all phases as pending
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    eval "PHASE_STATUS_${i}=pending"
    eval "PHASE_ATTEMPTS_${i}=0"
    eval "PHASE_START_TIME_${i}=''"
    eval "PHASE_END_TIME_${i}=''"
    i=$((i + 1))
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
  while IFS= read -r line; do
    # Match phase headers: ### ✅ Phase 1: Title
    if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
      current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
    elif [ -n "$current_phase" ]; then
      case "$line" in
        "Status: "*)
          status_value=$(echo "$line" | sed 's/^Status:[[:space:]]*//')
          eval "PHASE_STATUS_${current_phase}='$status_value'"
          ;;
        "Started: "*)
          time_value=$(echo "$line" | sed 's/^Started:[[:space:]]*//')
          eval "PHASE_START_TIME_${current_phase}='$time_value'"
          ;;
        "Completed: "*)
          time_value=$(echo "$line" | sed 's/^Completed:[[:space:]]*//')
          eval "PHASE_END_TIME_${current_phase}='$time_value'"
          ;;
        "Attempts: "*)
          attempts_value=$(echo "$line" | sed 's/^Attempts:[[:space:]]*//')
          eval "PHASE_ATTEMPTS_${current_phase}=$attempts_value"
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
}

# Generate status summary section
generate_status_summary() {
  local total="$PHASE_COUNT"
  local completed=0
  local in_progress=0
  local pending=0
  local failed=0

  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    local status
    status=$(eval "echo \"\$PHASE_STATUS_$i\"")
    case "$status" in
      completed)   completed=$((completed + 1)) ;;
      in_progress) in_progress=$((in_progress + 1)) ;;
      pending)     pending=$((pending + 1)) ;;
      failed)      failed=$((failed + 1)) ;;
    esac
    i=$((i + 1))
  done

  echo "- Total phases: $total"
  echo "- Completed: $completed"
  echo "- In progress: $in_progress"
  echo "- Pending: $pending"
  echo "- Failed: $failed"
}

# Generate phase details section
generate_phase_details() {
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    local status
    status=$(eval "echo \"\$PHASE_STATUS_$i\"")
    local title
    title=$(eval "echo \"\$PHASE_TITLE_$i\"")
    local icon="⏳"

    case "$status" in
      completed)   icon="✅" ;;
      in_progress) icon="🔄" ;;
      failed)      icon="❌" ;;
      pending)     icon="⏳" ;;
    esac

    echo "### $icon Phase $i: $title"
    echo "Status: $status"

    local start_time
    start_time=$(eval "echo \"\$PHASE_START_TIME_$i\"")
    if [ -n "$start_time" ]; then
      echo "Started: $start_time"
    fi

    local end_time
    end_time=$(eval "echo \"\$PHASE_END_TIME_$i\"")
    if [ -n "$end_time" ]; then
      echo "Completed: $end_time"
    fi

    local attempts
    attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$i\"")
    if [ "$attempts" -gt 0 ]; then
      echo "Attempts: $attempts"
    fi

    local deps
    deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$i\"")
    if [ -n "$deps" ]; then
      printf 'Depends on:'
      for dep in $deps; do
        local dep_status
        dep_status=$(eval "echo \"\$PHASE_STATUS_$dep\"")
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
    i=$((i + 1))
  done
}

# Update phase status
# Args: $1 - phase number, $2 - new status
update_phase_status() {
  local phase_num="$1"
  local new_status="$2"

  eval "PHASE_STATUS_${phase_num}='$new_status'"

  case "$new_status" in
    in_progress)
      eval "PHASE_START_TIME_${phase_num}='$(date '+%Y-%m-%d %H:%M:%S')'"
      local attempts
      attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")
      eval "PHASE_ATTEMPTS_${phase_num}=$((attempts + 1))"
      ;;
    completed|failed)
      eval "PHASE_END_TIME_${phase_num}='$(date '+%Y-%m-%d %H:%M:%S')'"
      ;;
  esac
}
