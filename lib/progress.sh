#!/bin/sh

# Progress Tracking Library
# Manages PROGRESS.md file and tracks execution state

# Initialize progress tracking
# Args: $1 - progress file path
init_progress() {
  local progress_file="$1"

  # Initialize status for all phases as pending
  for _phase in $PHASE_NUMBERS; do
    local _pv
    _pv=$(phase_to_var "$_phase")
    eval "PHASE_STATUS_${_pv}=pending"
    eval "PHASE_ATTEMPTS_${_pv}=0"
    eval "PHASE_START_TIME_${_pv}=''"
    eval "PHASE_END_TIME_${_pv}=''"
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
    # Match phase headers: ### ✅ Phase 1: Title or ### ✅ Phase 2.5: Title
    if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+(\.[0-9]+)?:'; then
      current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\):.*/\1/p')
    elif [ -n "$current_phase" ]; then
      local _cv
      _cv=$(phase_to_var "$current_phase")
      case "$line" in
        "Status: "*)
          status_value=$(echo "$line" | sed 's/^Status:[[:space:]]*//')
          # Normalize stale in_progress (e.g. from SIGKILL) so the phase retries
          [ "$status_value" = "in_progress" ] && status_value="pending"
          eval "PHASE_STATUS_${_cv}='$status_value'"
          ;;
        "Started: "*)
          time_value=$(echo "$line" | sed 's/^Started:[[:space:]]*//')
          eval "PHASE_START_TIME_${_cv}='$time_value'"
          ;;
        "Completed: "*)
          time_value=$(echo "$line" | sed 's/^Completed:[[:space:]]*//')
          eval "PHASE_END_TIME_${_cv}='$time_value'"
          ;;
        "Attempts: "*)
          attempts_value=$(echo "$line" | sed 's/^Attempts:[[:space:]]*//')
          eval "PHASE_ATTEMPTS_${_cv}=$attempts_value"
          ;;
        "Attempt "[0-9]*)
          _anum=$(echo "$line" | sed 's/^Attempt \([0-9]*\) Started:.*/\1/')
          _atime=$(echo "$line" | sed 's/^Attempt [0-9]* Started:[[:space:]]*//')
          eval "PHASE_ATTEMPT_TIME_${_cv}_${_anum}='$_atime'"
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
}

# Generate status summary section
generate_status_summary() {
  local total="$PHASE_COUNT"
  local completed=0
  local in_progress=0
  local pending=0
  local failed=0

  for _phase in $PHASE_NUMBERS; do
    local _pv
    _pv=$(phase_to_var "$_phase")
    local status
    status=$(eval "echo \"\$PHASE_STATUS_${_pv}\"")
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
    local _pv
    _pv=$(phase_to_var "$_phase")
    local status
    status=$(eval "echo \"\$PHASE_STATUS_${_pv}\"")
    local title
    title=$(eval "echo \"\$PHASE_TITLE_${_pv}\"")
    local icon="⏳"

    case "$status" in
      completed)   icon="✅" ;;
      in_progress) icon="🔄" ;;
      failed)      icon="❌" ;;
      pending)     icon="⏳" ;;
    esac

    echo "### $icon Phase $_phase: $title"
    echo "Status: $status"

    local start_time
    start_time=$(eval "echo \"\$PHASE_START_TIME_${_pv}\"")
    if [ -n "$start_time" ]; then
      echo "Started: $start_time"
    fi

    local end_time
    end_time=$(eval "echo \"\$PHASE_END_TIME_${_pv}\"")
    if [ -n "$end_time" ]; then
      echo "Completed: $end_time"
    fi

    local attempts
    attempts=$(eval "echo \"\$PHASE_ATTEMPTS_${_pv}\"")
    if [ "$attempts" -gt 0 ]; then
      echo "Attempts: $attempts"
      if [ "$attempts" -gt 1 ]; then
        local _i=1
        while [ "$_i" -le "$attempts" ]; do
          local _at
          _at=$(eval "echo \"\${PHASE_ATTEMPT_TIME_${_pv}_${_i}:-}\"")
          [ -n "$_at" ] && echo "Attempt $_i Started: $_at"
          _i=$((_i + 1))
        done
      fi
    fi

    local deps
    deps=$(eval "echo \"\$PHASE_DEPENDENCIES_${_pv}\"")
    if [ -n "$deps" ]; then
      printf 'Depends on:'
      for dep in $deps; do
        local dep_var
        dep_var=$(phase_to_var "$dep")
        local dep_status
        dep_status=$(eval "echo \"\$PHASE_STATUS_${dep_var}\"")
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

# Parse PROGRESS.md into _OLD_PHASE_* variables without affecting live PHASE_* globals.
# Sets _OLD_PHASE_COUNT to 0 if file absent or empty.
# Also builds _OLD_PHASE_NUMBERS (space-separated ordered list).
# Args: $1 - progress file path
read_old_phase_list() {
  local progress_file="$1"
  _OLD_PHASE_COUNT=0
  _OLD_PHASE_NUMBERS=""

  if [ ! -f "$progress_file" ]; then
    return 0
  fi

  local current_phase=""
  while IFS= read -r line; do
    # Match phase headers: ### ✅ Phase 1: Title or ### ✅ Phase 2.5: Title
    if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+(\.[0-9]+)?:'; then
      current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\):.*/\1/p')
      local _ov
      _ov=$(phase_to_var "$current_phase")
      local title safe_title
      title=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}:[[:space:]]*\(.*\)/\2/p')
      safe_title=$(echo "$title" | sed "s/'/'\\''/g")
      eval "_OLD_PHASE_TITLE_${_ov}='${safe_title}'"
      eval "_OLD_PHASE_STATUS_${_ov}=pending"
      eval "_OLD_PHASE_ATTEMPTS_${_ov}=0"
      eval "_OLD_PHASE_START_TIME_${_ov}=''"
      eval "_OLD_PHASE_END_TIME_${_ov}=''"
      eval "_OLD_PHASE_DEPS_${_ov}=''"
      _OLD_PHASE_COUNT=$((_OLD_PHASE_COUNT + 1))
      _OLD_PHASE_NUMBERS="${_OLD_PHASE_NUMBERS:+$_OLD_PHASE_NUMBERS }$current_phase"
    elif [ -n "$current_phase" ]; then
      local _ov2
      _ov2=$(phase_to_var "$current_phase")
      case "$line" in
        "Status: "*)
          local sv
          sv=$(echo "$line" | sed 's/^Status:[[:space:]]*//')
          # Normalize stale in_progress (e.g. from SIGKILL) so the phase retries
          [ "$sv" = "in_progress" ] && sv="pending"
          eval "_OLD_PHASE_STATUS_${_ov2}='${sv}'"
          ;;
        "Started: "*)
          local tv
          tv=$(echo "$line" | sed 's/^Started:[[:space:]]*//')
          eval "_OLD_PHASE_START_TIME_${_ov2}='${tv}'"
          ;;
        "Completed: "*)
          local tv
          tv=$(echo "$line" | sed 's/^Completed:[[:space:]]*//')
          eval "_OLD_PHASE_END_TIME_${_ov2}='${tv}'"
          ;;
        "Attempts: "*)
          local av
          av=$(echo "$line" | sed 's/^Attempts:[[:space:]]*//')
          eval "_OLD_PHASE_ATTEMPTS_${_ov2}=${av}"
          ;;
        "Attempt "[0-9]*)
          _anum=$(echo "$line" | sed 's/^Attempt \([0-9]*\) Started:.*/\1/')
          _atime=$(echo "$line" | sed 's/^Attempt [0-9]* Started:[[:space:]]*//')
          eval "_OLD_PHASE_ATTEMPT_TIME_${_ov2}_${_anum}='$_atime'"
          ;;
        "Depends on:"*)
          local dv
          dv=$(echo "$line" | grep -oE '[0-9]+(\.[0-9]+)?' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
          eval "_OLD_PHASE_DEPS_${_ov2}='${dv}'"
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
  for new_i in $PHASE_NUMBERS; do
    local new_iv
    new_iv=$(phase_to_var "$new_i")
    local new_title
    new_title=$(eval "echo \"\$PHASE_TITLE_${new_iv}\"")

    # Linear scan through old phases to find title match (first unmatched match wins)
    local matched_old_num=""
    for old_j in $_OLD_PHASE_NUMBERS; do
      local old_jv
      old_jv=$(phase_to_var "$old_j")
      local old_title
      old_title=$(eval "echo \"\$_OLD_PHASE_TITLE_${old_jv}\"")
      if [ "$old_title" = "$new_title" ]; then
        if ! echo " $matched_old_phases " | grep -qF " $old_j "; then
          matched_old_num="$old_j"
          break
        fi
      fi
    done

    if [ -z "$matched_old_num" ]; then
      # Phase added — leave as pending
      had_changes=true
      printf 'Plan change: Phase added — "%s" (new Phase %s)\n' "$new_title" "$new_i"
    else
      matched_old_phases="$matched_old_phases $matched_old_num"
      local old_mnv
      old_mnv=$(phase_to_var "$matched_old_num")
      local old_status old_attempts old_start old_end
      old_status=$(eval "echo \"\$_OLD_PHASE_STATUS_${old_mnv}\"")
      old_attempts=$(eval "echo \"\$_OLD_PHASE_ATTEMPTS_${old_mnv}\"")
      old_start=$(eval "echo \"\$_OLD_PHASE_START_TIME_${old_mnv}\"")
      old_end=$(eval "echo \"\$_OLD_PHASE_END_TIME_${old_mnv}\"")

      eval "PHASE_STATUS_${new_iv}='${old_status}'"
      eval "PHASE_ATTEMPTS_${new_iv}=${old_attempts}"
      eval "PHASE_START_TIME_${new_iv}='${old_start}'"
      eval "PHASE_END_TIME_${new_iv}='${old_end}'"

      local _ti=1
      while [ "$_ti" -le "$old_attempts" ]; do
        local _old_at
        _old_at=$(eval "echo \"\${_OLD_PHASE_ATTEMPT_TIME_${old_mnv}_${_ti}:-}\"")
        eval "PHASE_ATTEMPT_TIME_${new_iv}_${_ti}='${_old_at}'"
        _ti=$((_ti + 1))
      done

      # Report renumbering (string comparison to support decimal numbers)
      if [ "$matched_old_num" != "$new_i" ]; then
        had_changes=true
        printf 'Plan change: Phase renumbered — "%s" was #%s, now #%s (status: %s)\n' \
          "$new_title" "$matched_old_num" "$new_i" "$old_status"
      fi

      # Check dependency changes — compare by title to avoid false positives from renumbering
      local old_dep_nums new_dep_nums
      old_dep_nums=$(eval "echo \"\$_OLD_PHASE_DEPS_${old_mnv}\"")
      new_dep_nums=$(eval "echo \"\$PHASE_DEPENDENCIES_${new_iv}\"")

      # Translate dep numbers to newline-separated title lists for sorting
      local old_dep_titles="" new_dep_titles="" old_dt new_dt
      for dep_num in $old_dep_nums; do
        local dep_ov
        dep_ov=$(phase_to_var "$dep_num")
        old_dt=$(eval "echo \"\$_OLD_PHASE_TITLE_${dep_ov}\"")
        [ -n "$old_dt" ] && old_dep_titles="${old_dep_titles}${old_dt}
"
      done
      for dep_num in $new_dep_nums; do
        local dep_nv
        dep_nv=$(phase_to_var "$dep_num")
        new_dt=$(eval "echo \"\$PHASE_TITLE_${dep_nv}\"")
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
  done

  # Check for removed phases (old phases not matched to any new phase)
  for old_k in $_OLD_PHASE_NUMBERS; do
    if ! echo " $matched_old_phases " | grep -qF " $old_k "; then
      local old_kv
      old_kv=$(phase_to_var "$old_k")
      local removed_title removed_status
      removed_title=$(eval "echo \"\$_OLD_PHASE_TITLE_${old_kv}\"")
      if [ -n "$removed_title" ]; then
        removed_status=$(eval "echo \"\$_OLD_PHASE_STATUS_${old_kv}\"")
        had_changes=true
        printf 'Plan change: Phase removed — "%s" (was Phase %s, status: %s)\n' \
          "$removed_title" "$old_k" "$removed_status"
      fi
    fi
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
  local phase_var
  phase_var=$(phase_to_var "$phase_num")

  eval "PHASE_STATUS_${phase_var}='$new_status'"

  case "$new_status" in
    in_progress)
      local _now
      _now=$(date '+%Y-%m-%d %H:%M:%S')
      eval "PHASE_START_TIME_${phase_var}='${_now}'"
      local attempts
      attempts=$(eval "echo \"\$PHASE_ATTEMPTS_${phase_var}\"")
      eval "PHASE_ATTEMPTS_${phase_var}=$((attempts + 1))"
      local _new_attempt=$((attempts + 1))
      eval "PHASE_ATTEMPT_TIME_${phase_var}_${_new_attempt}='${_now}'"
      ;;
    completed|failed)
      eval "PHASE_END_TIME_${phase_var}='$(date '+%Y-%m-%d %H:%M:%S')'"
      ;;
  esac
}
