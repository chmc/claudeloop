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

# Parse PROGRESS.md into _OLD_PHASE_* variables without affecting live PHASE_* globals.
# Sets _OLD_PHASE_COUNT to 0 if file absent or empty.
# Args: $1 - progress file path
read_old_phase_list() {
  local progress_file="$1"
  _OLD_PHASE_COUNT=0

  if [ ! -f "$progress_file" ]; then
    return 0
  fi

  local current_phase=""
  while IFS= read -r line; do
    # Match phase headers: ### ✅ Phase 1: Title
    if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
      current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
      local title safe_title
      title=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*[0-9][0-9]*:[[:space:]]*\(.*\)/\1/p')
      safe_title=$(echo "$title" | sed "s/'/'\\''/g")
      eval "_OLD_PHASE_TITLE_${current_phase}='${safe_title}'"
      eval "_OLD_PHASE_STATUS_${current_phase}=pending"
      eval "_OLD_PHASE_ATTEMPTS_${current_phase}=0"
      eval "_OLD_PHASE_START_TIME_${current_phase}=''"
      eval "_OLD_PHASE_END_TIME_${current_phase}=''"
      eval "_OLD_PHASE_DEPS_${current_phase}=''"
      if [ "$current_phase" -gt "$_OLD_PHASE_COUNT" ]; then
        _OLD_PHASE_COUNT="$current_phase"
      fi
    elif [ -n "$current_phase" ]; then
      case "$line" in
        "Status: "*)
          local sv
          sv=$(echo "$line" | sed 's/^Status:[[:space:]]*//')
          eval "_OLD_PHASE_STATUS_${current_phase}='${sv}'"
          ;;
        "Started: "*)
          local tv
          tv=$(echo "$line" | sed 's/^Started:[[:space:]]*//')
          eval "_OLD_PHASE_START_TIME_${current_phase}='${tv}'"
          ;;
        "Completed: "*)
          local tv
          tv=$(echo "$line" | sed 's/^Completed:[[:space:]]*//')
          eval "_OLD_PHASE_END_TIME_${current_phase}='${tv}'"
          ;;
        "Attempts: "*)
          local av
          av=$(echo "$line" | sed 's/^Attempts:[[:space:]]*//')
          eval "_OLD_PHASE_ATTEMPTS_${current_phase}=${av}"
          ;;
        "Depends on:"*)
          local dv
          dv=$(echo "$line" | grep -oE 'Phase [0-9]+' | sed 's/Phase //' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
          eval "_OLD_PHASE_DEPS_${current_phase}='${dv}'"
          ;;
      esac
    fi
  done < "$progress_file"

  return 0
}

# Detect and reconcile plan changes between saved progress and current plan.
# Matches old phases to new phases by title; reports added/removed/renumbered/dep-changed phases.
# Carries forward status/attempts/timestamps for matched phases.
# Args: $1 - progress file path
detect_plan_changes() {
  local progress_file="$1"
  read_old_phase_list "$progress_file"

  # No-op if no saved progress
  if [ "$_OLD_PHASE_COUNT" -eq 0 ]; then
    return 0
  fi

  local had_changes=false
  local matched_old_phases=""

  # For each new phase, find matching old phase by title
  local new_i=1
  while [ "$new_i" -le "$PHASE_COUNT" ]; do
    local new_title
    new_title=$(eval "echo \"\$PHASE_TITLE_$new_i\"")

    # Linear scan through old phases to find title match (first unmatched match wins)
    local matched_old_num="" old_j
    old_j=1
    while [ "$old_j" -le "$_OLD_PHASE_COUNT" ]; do
      local old_title
      old_title=$(eval "echo \"\$_OLD_PHASE_TITLE_$old_j\"")
      if [ "$old_title" = "$new_title" ]; then
        if ! echo " $matched_old_phases " | grep -qF " $old_j "; then
          matched_old_num="$old_j"
          break
        fi
      fi
      old_j=$((old_j + 1))
    done

    if [ -z "$matched_old_num" ]; then
      # Phase added — leave as pending
      had_changes=true
      printf 'Plan change: Phase added — "%s" (new Phase %d)\n' "$new_title" "$new_i"
    else
      matched_old_phases="$matched_old_phases $matched_old_num"
      local old_status old_attempts old_start old_end
      old_status=$(eval "echo \"\$_OLD_PHASE_STATUS_$matched_old_num\"")
      old_attempts=$(eval "echo \"\$_OLD_PHASE_ATTEMPTS_$matched_old_num\"")
      old_start=$(eval "echo \"\$_OLD_PHASE_START_TIME_$matched_old_num\"")
      old_end=$(eval "echo \"\$_OLD_PHASE_END_TIME_$matched_old_num\"")

      eval "PHASE_STATUS_${new_i}='${old_status}'"
      eval "PHASE_ATTEMPTS_${new_i}=${old_attempts}"
      eval "PHASE_START_TIME_${new_i}='${old_start}'"
      eval "PHASE_END_TIME_${new_i}='${old_end}'"

      # Report renumbering
      if [ "$matched_old_num" -ne "$new_i" ]; then
        had_changes=true
        printf 'Plan change: Phase renumbered — "%s" was #%d, now #%d (status: %s)\n' \
          "$new_title" "$matched_old_num" "$new_i" "$old_status"
      fi

      # Check dependency changes — compare by title to avoid false positives from renumbering
      local old_dep_nums new_dep_nums
      old_dep_nums=$(eval "echo \"\$_OLD_PHASE_DEPS_$matched_old_num\"")
      new_dep_nums=$(eval "echo \"\$PHASE_DEPENDENCIES_$new_i\"")

      # Translate dep numbers to newline-separated title lists for sorting
      local old_dep_titles="" new_dep_titles="" old_dt new_dt
      for dep_num in $old_dep_nums; do
        old_dt=$(eval "echo \"\$_OLD_PHASE_TITLE_$dep_num\"")
        [ -n "$old_dt" ] && old_dep_titles="${old_dep_titles}${old_dt}
"
      done
      for dep_num in $new_dep_nums; do
        new_dt=$(eval "echo \"\$PHASE_TITLE_$dep_num\"")
        [ -n "$new_dt" ] && new_dep_titles="${new_dep_titles}${new_dt}
"
      done

      local old_sorted new_sorted
      old_sorted=$(printf '%s' "$old_dep_titles" | sort)
      new_sorted=$(printf '%s' "$new_dep_titles" | sort)

      if [ "$old_sorted" != "$new_sorted" ]; then
        had_changes=true
        local old_display new_display
        old_display=$(printf '%s' "$old_dep_titles" | grep -v '^$' | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
        new_display=$(printf '%s' "$new_dep_titles" | grep -v '^$' | sed 's/.*/"&"/' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
        printf 'Plan change: Dependencies changed for "%s" — was: [%s], now: [%s]\n' \
          "$new_title" "$old_display" "$new_display"
      fi
    fi

    new_i=$((new_i + 1))
  done

  # Check for removed phases (old phases not matched to any new phase)
  local old_k=1
  while [ "$old_k" -le "$_OLD_PHASE_COUNT" ]; do
    if ! echo " $matched_old_phases " | grep -qF " $old_k "; then
      local removed_title removed_status
      removed_title=$(eval "echo \"\$_OLD_PHASE_TITLE_$old_k\"")
      if [ -n "$removed_title" ]; then
        removed_status=$(eval "echo \"\$_OLD_PHASE_STATUS_$old_k\"")
        had_changes=true
        printf 'Plan change: Phase removed — "%s" (was Phase %d, status: %s)\n' \
          "$removed_title" "$old_k" "$removed_status"
      fi
    fi
    old_k=$((old_k + 1))
  done

  if $had_changes; then
    echo ""
    echo "Plan has changed since last run. Progress reconciled by title matching."
  fi

  return 0
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
