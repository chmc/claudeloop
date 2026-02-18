#!/opt/homebrew/bin/bash

# Progress Tracking Library
# Manages PROGRESS.md file and tracks execution state

# Global associative array for phase status
declare -A PHASE_STATUS
declare -A PHASE_START_TIME
declare -A PHASE_END_TIME
declare -A PHASE_ATTEMPTS

# Initialize progress tracking
# Args: $1 - progress file path
init_progress() {
  local progress_file="$1"

  # Initialize status for all phases as pending
  local i
  for i in $(seq 1 "$PHASE_COUNT"); do
    PHASE_STATUS[$i]="pending"
    PHASE_ATTEMPTS[$i]=0
    PHASE_START_TIME[$i]=""
    PHASE_END_TIME[$i]=""
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
    if [[ "$line" =~ ^###\ +[^\ ]+\ +Phase\ +([0-9]+): ]]; then
      current_phase="${BASH_REMATCH[1]}"
    elif [ -n "$current_phase" ] && [[ "$line" =~ ^Status:\ +(.+) ]]; then
      PHASE_STATUS[$current_phase]="${BASH_REMATCH[1]}"
    elif [ -n "$current_phase" ] && [[ "$line" =~ ^Started:\ +(.+) ]]; then
      PHASE_START_TIME[$current_phase]="${BASH_REMATCH[1]}"
    elif [ -n "$current_phase" ] && [[ "$line" =~ ^Completed:\ +(.+) ]]; then
      PHASE_END_TIME[$current_phase]="${BASH_REMATCH[1]}"
    elif [ -n "$current_phase" ] && [[ "$line" =~ ^Attempts:\ +([0-9]+) ]]; then
      PHASE_ATTEMPTS[$current_phase]="${BASH_REMATCH[1]}"
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
  local total=$PHASE_COUNT
  local completed=0
  local in_progress=0
  local pending=0
  local failed=0

  local i
  for i in $(seq 1 "$PHASE_COUNT"); do
    case "${PHASE_STATUS[$i]}" in
      completed) completed=$((completed + 1)) ;;
      in_progress) in_progress=$((in_progress + 1)) ;;
      pending) pending=$((pending + 1)) ;;
      failed) failed=$((failed + 1)) ;;
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
  local i
  for i in $(seq 1 "$PHASE_COUNT"); do
    local status="${PHASE_STATUS[$i]}"
    local title="${PHASE_TITLES[$i]}"
    local icon="⏳"

    case "$status" in
      completed) icon="✅" ;;
      in_progress) icon="🔄" ;;
      failed) icon="❌" ;;
      pending) icon="⏳" ;;
    esac

    echo "### $icon Phase $i: $title"
    echo "Status: $status"

    if [ -n "${PHASE_START_TIME[$i]}" ]; then
      echo "Started: ${PHASE_START_TIME[$i]}"
    fi

    if [ -n "${PHASE_END_TIME[$i]}" ]; then
      echo "Completed: ${PHASE_END_TIME[$i]}"
    fi

    if [ "${PHASE_ATTEMPTS[$i]}" -gt 0 ]; then
      echo "Attempts: ${PHASE_ATTEMPTS[$i]}"
    fi

    local deps="${PHASE_DEPENDENCIES[$i]}"
    if [ -n "$deps" ]; then
      echo -n "Depends on:"
      for dep in $deps; do
        local dep_status="${PHASE_STATUS[$dep]}"
        local dep_icon="⏳"
        case "$dep_status" in
          completed) dep_icon="✅" ;;
          failed) dep_icon="❌" ;;
        esac
        echo -n " Phase $dep $dep_icon"
      done
      echo ""
    fi

    echo ""
  done
}

# Update phase status
# Args: $1 - phase number, $2 - new status
update_phase_status() {
  local phase_num="$1"
  local new_status="$2"

  PHASE_STATUS[$phase_num]="$new_status"

  case "$new_status" in
    in_progress)
      PHASE_START_TIME[$phase_num]="$(date '+%Y-%m-%d %H:%M:%S')"
      PHASE_ATTEMPTS[$phase_num]=$((${PHASE_ATTEMPTS[$phase_num]} + 1))
      ;;
    completed|failed)
      PHASE_END_TIME[$phase_num]="$(date '+%Y-%m-%d %H:%M:%S')"
      ;;
  esac
}
