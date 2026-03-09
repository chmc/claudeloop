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
    # Match phase headers: ### ✅ Phase 1: Title or ### ✅ Phase 2.5: Title
    if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+(\.[0-9]+)?:'; then
      current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\):.*/\1/p')
    elif [ -n "$current_phase" ]; then
      case "$line" in
        "Status: "*)
          local status_value
          status_value=$(echo "$line" | sed 's/^Status:[[:space:]]*//')
          # Normalize stale in_progress (e.g. from SIGKILL) so the phase retries
          [ "$status_value" = "in_progress" ] && status_value="pending"
          phase_set STATUS "$current_phase" "$status_value"
          ;;
        "Started: "*)
          local time_value
          time_value=$(echo "$line" | sed 's/^Started:[[:space:]]*//')
          phase_set START_TIME "$current_phase" "$time_value"
          ;;
        "Completed: "*)
          local time_value
          time_value=$(echo "$line" | sed 's/^Completed:[[:space:]]*//')
          phase_set END_TIME "$current_phase" "$time_value"
          ;;
        "Attempts: "*)
          local attempts_value
          attempts_value=$(echo "$line" | sed 's/^Attempts:[[:space:]]*//')
          printf '%s' "$attempts_value" | grep -qE '^[0-9]+$' || attempts_value=0
          phase_set ATTEMPTS "$current_phase" "$attempts_value"
          ;;
        "Attempt "[0-9]*)
          local _anum _atime
          _anum=$(echo "$line" | sed 's/^Attempt \([0-9]*\) Started:.*/\1/')
          _atime=$(echo "$line" | sed 's/^Attempt [0-9]* Started:[[:space:]]*//')
          phase_set ATTEMPT_TIME "$current_phase" "$_atime" "$_anum"
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

    echo "### $icon Phase $_phase: $title"
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
  while IFS= read -r line || [ -n "$line" ]; do
    # Match phase headers: ### ✅ Phase 1: Title or ### ✅ Phase 2.5: Title
    if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+(\.[0-9]+)?:'; then
      current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\):.*/\1/p')
      local title
      title=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}:[[:space:]]*\(.*\)/\2/p')
      old_phase_set TITLE "$current_phase" "$title"
      old_phase_set STATUS "$current_phase" "pending"
      old_phase_set ATTEMPTS "$current_phase" "0"
      old_phase_set START_TIME "$current_phase" ""
      old_phase_set END_TIME "$current_phase" ""
      old_phase_set DEPS "$current_phase" ""
      _OLD_PHASE_COUNT=$((_OLD_PHASE_COUNT + 1))
      _OLD_PHASE_NUMBERS="${_OLD_PHASE_NUMBERS:+$_OLD_PHASE_NUMBERS }$current_phase"
    elif [ -n "$current_phase" ]; then
      case "$line" in
        "Status: "*)
          local sv
          sv=$(echo "$line" | sed 's/^Status:[[:space:]]*//')
          # Normalize stale in_progress (e.g. from SIGKILL) so the phase retries
          [ "$sv" = "in_progress" ] && sv="pending"
          old_phase_set STATUS "$current_phase" "$sv"
          ;;
        "Started: "*)
          local tv
          tv=$(echo "$line" | sed 's/^Started:[[:space:]]*//')
          old_phase_set START_TIME "$current_phase" "$tv"
          ;;
        "Completed: "*)
          local tv
          tv=$(echo "$line" | sed 's/^Completed:[[:space:]]*//')
          old_phase_set END_TIME "$current_phase" "$tv"
          ;;
        "Attempts: "*)
          local av
          av=$(echo "$line" | sed 's/^Attempts:[[:space:]]*//')
          printf '%s' "$av" | grep -qE '^[0-9]+$' || av=0
          old_phase_set ATTEMPTS "$current_phase" "$av"
          ;;
        "Attempt "[0-9]*)
          local _anum _atime
          _anum=$(echo "$line" | sed 's/^Attempt \([0-9]*\) Started:.*/\1/')
          _atime=$(echo "$line" | sed 's/^Attempt [0-9]* Started:[[:space:]]*//')
          old_phase_set ATTEMPT_TIME "$current_phase" "$_atime" "$_anum"
          ;;
        "Depends on:"*)
          local dv
          dv=$(echo "$line" | grep -oE '[0-9]+(\.[0-9]+)?' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
          old_phase_set DEPS "$current_phase" "$dv"
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
  _PLAN_HAD_CHANGES=false
  read_old_phase_list "$progress_file"

  # No-op if no saved progress
  if [ "$_OLD_PHASE_COUNT" -eq 0 ]; then
    return 0
  fi

  local had_changes=false
  local matched_old_phases=""

  # For each new phase, find matching old phase by title
  for new_i in $PHASE_NUMBERS; do
    local new_title
    new_title=$(get_phase_title "$new_i")

    # Linear scan through old phases to find title match (first unmatched match wins)
    local matched_old_num=""
    for old_j in $_OLD_PHASE_NUMBERS; do
      local old_title
      old_title=$(old_phase_get TITLE "$old_j")
      if [ "$old_title" = "$new_title" ]; then
        if ! echo " $matched_old_phases " | grep -qF " $old_j "; then
          matched_old_num="$old_j"
          break
        fi
      fi
    done

    if [ -z "$matched_old_num" ]; then
      # Phase added — explicitly reset to defaults (init_progress may have loaded stale
      # status from PROGRESS.md by phase number before detect_plan_changes ran)
      had_changes=true
      reset_phase_full "$new_i"
      printf '[%s] Plan change: Phase added — "%s" (new Phase %s)\n' "$(date '+%H:%M:%S')" "$new_title" "$new_i"
    else
      matched_old_phases="$matched_old_phases $matched_old_num"
      local old_status old_attempts old_start old_end
      old_status=$(old_phase_get STATUS "$matched_old_num")
      old_attempts=$(old_phase_get ATTEMPTS "$matched_old_num")
      old_start=$(old_phase_get START_TIME "$matched_old_num")
      old_end=$(old_phase_get END_TIME "$matched_old_num")

      printf '%s' "$old_attempts" | grep -qE '^[0-9]+$' || old_attempts=0
      phase_set STATUS "$new_i" "$old_status"
      phase_set ATTEMPTS "$new_i" "$old_attempts"
      phase_set START_TIME "$new_i" "$old_start"
      phase_set END_TIME "$new_i" "$old_end"

      local _ti=1
      while [ "$_ti" -le "$old_attempts" ]; do
        local _old_at
        _old_at=$(old_phase_get ATTEMPT_TIME "$matched_old_num" "$_ti")
        phase_set ATTEMPT_TIME "$new_i" "$_old_at" "$_ti"
        _ti=$((_ti + 1))
      done

      # Report renumbering (string comparison to support decimal numbers)
      if [ "$matched_old_num" != "$new_i" ]; then
        had_changes=true
        printf '[%s] Plan change: Phase renumbered — "%s" was #%s, now #%s (status: %s)\n' \
          "$(date '+%H:%M:%S')" "$new_title" "$matched_old_num" "$new_i" "$old_status"
      fi

      # Check dependency changes — compare by title to avoid false positives from renumbering
      local old_dep_nums new_dep_nums
      old_dep_nums=$(old_phase_get DEPS "$matched_old_num")
      new_dep_nums=$(get_phase_dependencies "$new_i")

      # Translate dep numbers to newline-separated title lists for sorting
      local old_dep_titles="" new_dep_titles="" old_dt new_dt
      for dep_num in $old_dep_nums; do
        old_dt=$(old_phase_get TITLE "$dep_num")
        [ -n "$old_dt" ] && old_dep_titles="${old_dep_titles}${old_dt}
"
      done
      for dep_num in $new_dep_nums; do
        new_dt=$(get_phase_title "$dep_num")
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
        printf '[%s] Plan change: Dependencies changed for "%s" — was: [%s], now: [%s]\n' \
          "$(date '+%H:%M:%S')" "$new_title" "$old_display" "$new_display"
      fi
    fi
  done

  # Check for removed phases (old phases not matched to any new phase)
  for old_k in $_OLD_PHASE_NUMBERS; do
    if ! echo " $matched_old_phases " | grep -qF " $old_k "; then
      local removed_title removed_status
      removed_title=$(old_phase_get TITLE "$old_k")
      if [ -n "$removed_title" ]; then
        removed_status=$(old_phase_get STATUS "$old_k")
        had_changes=true
        printf '[%s] Plan change: Phase removed — "%s" (was Phase %s, status: %s)\n' \
          "$(date '+%H:%M:%S')" "$removed_title" "$old_k" "$removed_status"
      fi
    fi
  done

  if $had_changes; then
    _PLAN_HAD_CHANGES=true
    # Backup before any further writes might overwrite the old progress
    cp "$progress_file" "${progress_file}.bak"

    # Count removed phases
    local removed_count=0
    for old_k in $_OLD_PHASE_NUMBERS; do
      if ! echo " $matched_old_phases " | grep -qF " $old_k "; then
        local _rtitle
        _rtitle=$(old_phase_get TITLE "$old_k")
        [ -n "$_rtitle" ] && removed_count=$((removed_count + 1))
      fi
    done

    # Drastic change guard: >50% removed and old count > 4
    if [ "$_OLD_PHASE_COUNT" -gt 4 ] && [ "$removed_count" -gt 0 ]; then
      local _pct=$(( (removed_count * 100) / _OLD_PHASE_COUNT ))
      if [ "$_pct" -gt 50 ]; then
        printf '\n[%s] ⚠ Drastic plan change: %s of %s old phases removed (%s%%).\n' \
          "$(date '+%H:%M:%S')" "$removed_count" "$_OLD_PHASE_COUNT" "$_pct"
        if [ -f ".claudeloop/ai-parsed-plan.md" ]; then
          printf '[%s]   Hint: use --plan .claudeloop/ai-parsed-plan.md if you meant the AI-parsed plan.\n' "$(date '+%H:%M:%S')"
        fi
        if [ -d ".claudeloop/logs" ] && ls .claudeloop/logs/phase-*.log >/dev/null 2>&1; then
          printf '[%s]   Hint: use --recover-progress to reconstruct progress from logs.\n' "$(date '+%H:%M:%S')"
        fi
        printf '[%s]   Backup saved to %s\n' "$(date '+%H:%M:%S')" "${progress_file}.bak"

        if [ "$YES_MODE" = "true" ]; then
          printf '[%s]   YES_MODE active — proceeding automatically.\n' "$(date '+%H:%M:%S')"
        elif [ -t 0 ]; then
          printf 'Continue? (y/N) '
          read -r _ans
          case "$_ans" in
            [yY]*) ;;
            *) log_ts "Aborted."; return 1 ;;
          esac
        else
          log_ts "Non-interactive mode — aborting to prevent data loss."
          return 1
        fi
      fi
    fi

    echo ""
    log_ts "Plan has changed since last run. Progress reconciled by title matching."
  fi

  return 0
}

# Detect orphan log files — logs for phases not in the current plan.
# This catches corrupted progress from a previous buggy run (e.g. --ai-parse with
# more phases, then re-run without it). Orphan logs are the only retroactive signal.
# Args: $1 - project dir (e.g. .claudeloop)
# Sets: _ORPHAN_LOG_PHASES (space-separated list of orphan phase numbers)
# Returns: 0 on continue/reset, 1 on abort
detect_orphan_logs() {
  local project_dir="$1"
  local logs_dir="$project_dir/logs"
  _ORPHAN_LOG_PHASES=""
  _ORPHAN_RECOVERY_ACTION=""

  # No logs dir → nothing to check
  if [ ! -d "$logs_dir" ]; then
    return 0
  fi

  # Scan for phase-N.log files not matching any current plan phase
  for _lf in "$logs_dir"/phase-*.log; do
    [ -f "$_lf" ] || continue
    # Skip auxiliary files
    case "$_lf" in
      *.attempt-*.log|*.verify.log|*.raw.json|*.formatted.log) continue ;;
    esac
    local _lnum
    _lnum=$(printf '%s' "$_lf" | sed -n 's|.*/phase-\([0-9][0-9]*\(\.[0-9][0-9]*\)*\)\.log$|\1|p')
    [ -z "$_lnum" ] && continue
    local _found=false
    for _p in $PHASE_NUMBERS; do
      if [ "$_p" = "$_lnum" ]; then
        _found=true
        break
      fi
    done
    if ! $_found; then
      _ORPHAN_LOG_PHASES="${_ORPHAN_LOG_PHASES:+$_ORPHAN_LOG_PHASES }$_lnum"
    fi
  done

  # No orphans → all clear
  if [ -z "$_ORPHAN_LOG_PHASES" ]; then
    return 0
  fi

  _ORPHAN_RECOVERY_ACTION=""
  local _has_ai_plan=false
  if [ -f "$project_dir/ai-parsed-plan.md" ]; then
    _has_ai_plan=true
  fi

  printf '\n[%s] ⚠ Orphan log files detected for phases not in the current plan: %s\n' \
    "$(date '+%H:%M:%S')" "$_ORPHAN_LOG_PHASES"
  printf '[%s]   This may indicate corrupted progress from a previous run with a different plan.\n' \
    "$(date '+%H:%M:%S')"
  if $_has_ai_plan; then
    printf '[%s]   → Will switch to ai-parsed-plan.md and recover progress from logs.\n' \
      "$(date '+%H:%M:%S')"
  else
    printf '[%s]   Hint: use --reset to start fresh.\n' "$(date '+%H:%M:%S')"
  fi

  if [ "$YES_MODE" = "true" ]; then
    printf '[%s]   YES_MODE active — continuing automatically.\n' "$(date '+%H:%M:%S')"
    _ORPHAN_RECOVERY_ACTION=continue
    return 0
  elif [ -t 0 ] || [ "${_ORPHAN_FORCE_TTY:-}" = "true" ]; then
    if $_has_ai_plan; then
      printf '[r]ecover (recommended) / [c]ontinue / [a]bort? '
      read -r _ans
      case "$_ans" in
        [rR]*)
          _ORPHAN_RECOVERY_ACTION=recover
          return 0
          ;;
        [cC]*)
          log_ts "Continuing with current progress."
          _ORPHAN_RECOVERY_ACTION=continue
          return 0
          ;;
        *)
          log_ts "Aborted."
          return 1
          ;;
      esac
    else
      printf '[c]ontinue / [a]bort? '
      read -r _ans
      case "$_ans" in
        [cC]*)
          log_ts "Continuing with current progress."
          _ORPHAN_RECOVERY_ACTION=continue
          return 0
          ;;
        *)
          log_ts "Aborted."
          return 1
          ;;
      esac
    fi
  else
    log_ts "Non-interactive mode — continuing (use --reset to start fresh)."
    _ORPHAN_RECOVERY_ACTION=continue
    return 0
  fi
}

# Recover progress from log files in .claudeloop/logs/
# Reconstructs PHASE_STATUS/ATTEMPTS/START_TIME/END_TIME from ground truth in log files.
# Args: $1 - project dir (e.g. .claudeloop), $2 - progress file path, $3 - plan file path
recover_progress_from_logs() {
  local project_dir="$1"
  local progress_file="$2"
  local plan_file="$3"
  local logs_dir="$project_dir/logs"

  # Initialize all phases to defaults
  for _phase in $PHASE_NUMBERS; do
    reset_phase_full "$_phase"
  done

  # Process each phase
  for _phase in $PHASE_NUMBERS; do
    local log_file="$logs_dir/phase-${_phase}.log"

    if [ ! -f "$log_file" ]; then
      # No log file — phase never started
      continue
    fi

    # Count attempts: archived attempt files + 1 for current log
    local attempt_count=0
    for _af in "$logs_dir"/phase-"${_phase}".attempt-*.log; do
      [ -f "$_af" ] && attempt_count=$((attempt_count + 1))
    done
    attempt_count=$((attempt_count + 1))
    phase_set ATTEMPTS "$_phase" "$attempt_count"

    # Extract start time from EXECUTION START line
    local start_time
    start_time=$(sed -n 's/^=== EXECUTION START .* time=\([^ ]*\) ===$/\1/p' "$log_file" | tail -1)
    if [ -n "$start_time" ]; then
      start_time=$(printf '%s' "$start_time" | sed 's/T/ /')
      phase_set START_TIME "$_phase" "$start_time"
    fi

    # Check for EXECUTION END
    local end_line
    end_line=$(grep '^=== EXECUTION END ' "$log_file" | tail -1)
    if [ -z "$end_line" ]; then
      # No end marker — interrupted, leave as pending
      continue
    fi

    # Extract exit code and end time
    local exit_code end_time
    exit_code=$(printf '%s' "$end_line" | sed -n 's/.*exit_code=\([0-9]*\).*/\1/p')
    end_time=$(printf '%s' "$end_line" | sed -n 's/.* time=\([^ ]*\) ===$/\1/p')
    if [ -n "$end_time" ]; then
      end_time=$(printf '%s' "$end_time" | sed 's/T/ /')
      phase_set END_TIME "$_phase" "$end_time"
    fi

    # Determine status
    local phase_ok=false
    if [ "$exit_code" = "0" ]; then
      phase_ok=true
    elif has_successful_session "$log_file" 2>/dev/null; then
      phase_ok=true
    fi

    if $phase_ok; then
      # Check verify.log if it exists
      local verify_log="$logs_dir/phase-${_phase}.verify.log"
      if [ -f "$verify_log" ]; then
        if grep -q 'VERIFICATION_PASSED' "$verify_log"; then
          phase_set STATUS "$_phase" "completed"
        else
          phase_set STATUS "$_phase" "failed"
        fi
      else
        phase_set STATUS "$_phase" "completed"
      fi
    else
      phase_set STATUS "$_phase" "failed"
    fi
  done

  # Warn about unknown phase logs
  if [ -d "$logs_dir" ]; then
    for _lf in "$logs_dir"/phase-*.log; do
      [ -f "$_lf" ] || continue
      # Skip attempt and verify logs
      case "$_lf" in
        *.attempt-*.log|*.verify.log|*.raw.json) continue ;;
      esac
      local _lnum
      _lnum=$(printf '%s' "$_lf" | sed -n 's|.*/phase-\([0-9][0-9]*\(\.[0-9][0-9]*\)*\)\.log$|\1|p')
      [ -z "$_lnum" ] && continue
      local _found=false
      for _p in $PHASE_NUMBERS; do
        if [ "$_p" = "$_lnum" ]; then
          _found=true
          break
        fi
      done
      if ! $_found; then
        printf '[%s] Warning: Log file for phase %s not in current plan — possible wrong plan file.\n' \
          "$(date '+%H:%M:%S')" "$_lnum"
      fi
    done
  fi

  # Write the recovered progress
  write_progress "$progress_file" "$plan_file"
  printf '[%s] Progress recovered from logs → %s\n' "$(date '+%H:%M:%S')" "$progress_file"
}

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
