#!/bin/sh

# Flight Recorder Library
# Extracts execution data from .claudeloop/ artifacts and produces JSON.
# All functions use _REC_ prefix for their own variables to avoid polluting
# the global PHASE_* namespace used by the main orchestrator.

# Source sub-modules (co-located in the same directory)
# When sourced via `. path/to/lib/recorder.sh`, BASH_SOURCE or $0 may not
# point here, so we locate siblings relative to the sourcing path pattern.
# The caller uses either $SCRIPT_DIR/lib/ or $CLAUDELOOP_DIR/lib/.
_RECORDER_LIB_DIR="${SCRIPT_DIR:+$SCRIPT_DIR/lib}"
_RECORDER_LIB_DIR="${_RECORDER_LIB_DIR:-${CLAUDELOOP_DIR:+$CLAUDELOOP_DIR/lib}}"
_RECORDER_LIB_DIR="${_RECORDER_LIB_DIR:-$(cd "$(dirname "$0")/lib" 2>/dev/null && pwd)}"
. "${_RECORDER_LIB_DIR}/recorder_parsers.sh"
. "${_RECORDER_LIB_DIR}/recorder_overview.sh"

# Escape a string for JSON embedding via awk.
# Handles: \ → \\, " → \", newline → \n, tab → \t
# Args: $1 - string to escape
# Prints: escaped string
json_escape() {
  printf '%s' "$1" | awk '
    BEGIN { ORS="" }
    {
      if (NR > 1) printf "\\n"
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\\") printf "\\\\"
        else if (c == "\"") printf "\\\""
        else if (c == "\t") printf "\\t"
        else printf "%s", c
      }
    }'
}

# Parse PROGRESS.md into _REC_PHASE_* variables.
# Sets _REC_PHASE_COUNT, _REC_PHASE_NUMBERS, and per-phase:
#   _REC_PHASE_TITLE_N, _REC_PHASE_STATUS_N, _REC_PHASE_ATTEMPTS_N,
#   _REC_PHASE_START_TIME_N, _REC_PHASE_END_TIME_N, _REC_PHASE_DEPS_N,
#   _REC_PHASE_REFACTOR_STATUS_N, _REC_PHASE_DESCRIPTION_N
# Args: $1 - run directory
rec_load_progress() {
  local run_dir="$1"
  local progress_file="$run_dir/PROGRESS.md"
  _REC_PHASE_COUNT=0
  _REC_PHASE_NUMBERS=""

  if [ ! -f "$progress_file" ]; then
    return 0
  fi

  local current_phase=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%"${line##*[![:space:]]}"}"

    if is_progress_phase_header "$line"; then
      current_phase=$(extract_progress_phase_num "$line")
      local title
      title=$(extract_progress_phase_title "$line")
      local pv
      pv=$(phase_to_var "$current_phase")
      eval "_REC_PHASE_TITLE_${pv}='$(printf '%s' "$title" | sed "s/'/'\\\\''/g")'"
      eval "_REC_PHASE_STATUS_${pv}='pending'"
      eval "_REC_PHASE_ATTEMPTS_${pv}='0'"
      eval "_REC_PHASE_START_TIME_${pv}=''"
      eval "_REC_PHASE_END_TIME_${pv}=''"
      eval "_REC_PHASE_DEPS_${pv}=''"
      eval "_REC_PHASE_REFACTOR_STATUS_${pv}=''"
      eval "_REC_PHASE_DESCRIPTION_${pv}=''"
      _REC_PHASE_COUNT=$((_REC_PHASE_COUNT + 1))
      _REC_PHASE_NUMBERS="${_REC_PHASE_NUMBERS:+$_REC_PHASE_NUMBERS }$current_phase"
    elif [ -n "$current_phase" ]; then
      local pv
      pv=$(phase_to_var "$current_phase")
      case "$line" in
        "Status: "*)
          local sv
          sv=$(printf '%s\n' "$line" | sed 's/^Status:[[:space:]]*//')
          eval "_REC_PHASE_STATUS_${pv}='$sv'"
          ;;
        "Started: "*)
          local tv
          tv=$(printf '%s\n' "$line" | sed 's/^Started:[[:space:]]*//')
          eval "_REC_PHASE_START_TIME_${pv}='$tv'"
          ;;
        "Completed: "*)
          local tv
          tv=$(printf '%s\n' "$line" | sed 's/^Completed:[[:space:]]*//')
          eval "_REC_PHASE_END_TIME_${pv}='$tv'"
          ;;
        "Attempts: "*)
          local av
          av=$(printf '%s\n' "$line" | sed 's/^Attempts:[[:space:]]*//')
          printf '%s' "$av" | grep -qE '^[0-9]+$' || av=0
          eval "_REC_PHASE_ATTEMPTS_${pv}='$av'"
          ;;
        "Depends on:"*)
          local dv
          dv=$(printf '%s\n' "$line" | grep -oE '[0-9]+(\.[0-9]+)?' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
          eval "_REC_PHASE_DEPS_${pv}='$dv'"
          ;;
        "Refactor: "*)
          local rv
          rv=$(printf '%s\n' "$line" | sed 's/^Refactor:[[:space:]]*//')
          eval "_REC_PHASE_REFACTOR_STATUS_${pv}='$rv'"
          ;;
      esac
    fi
  done < "$progress_file"

  return 0
}

# Helper: get _REC_PHASE_* variable value
# Args: $1 - field, $2 - phase number
_rec_get() {
  local pv
  pv=$(phase_to_var "$2")
  eval "printf '%s' \"\${_REC_PHASE_${1}_${pv}:-}\""
}

# Orchestrate all extractors and output complete JSON to stdout.
# Args: $1 - run directory
assemble_recorder_json() {
  local run_dir="$1"

  rec_load_progress "$run_dir"

  local generated_at
  generated_at=$(date '+%Y-%m-%dT%H:%M:%S')

  local run_overview
  run_overview=$(rec_extract_run_overview "$run_dir")

  printf '{"version":1,"generated_at":"%s","run":%s,"phases":[' "$generated_at" "$run_overview"

  local first_phase=true
  for pn in $_REC_PHASE_NUMBERS; do
    if [ "$first_phase" = "true" ]; then
      first_phase=false
    else
      printf ','
    fi

    local title status deps started ended attempts refactor_status
    title=$(json_escape "$(_rec_get TITLE "$pn")")
    status=$(_rec_get STATUS "$pn")
    deps=$(_rec_get DEPS "$pn")
    started=$(_rec_get START_TIME "$pn")
    ended=$(_rec_get END_TIME "$pn")
    attempts=$(_rec_get ATTEMPTS "$pn")
    refactor_status=$(_rec_get REFACTOR_STATUS "$pn")
    [ -z "$attempts" ] && attempts=0

    # Signal no-changes
    local signal_no_changes="false"
    if [ -f "$run_dir/signals/phase-${pn}.md" ]; then
      signal_no_changes="true"
    fi

    # Verification verdict
    local verdict
    verdict=$(rec_verify_verdict "$run_dir" "$pn")

    # Dependencies as JSON array
    local deps_json="["
    local first_dep=true
    if [ -n "$deps" ]; then
      for d in $deps; do
        if [ "$first_dep" = "true" ]; then
          first_dep=false
        else
          deps_json="${deps_json},"
        fi
        deps_json="${deps_json}\"$d\""
      done
    fi
    deps_json="${deps_json}]"

    printf '{"number":"%s","title":"%s","status":"%s","dependencies":%s,"started_at":"%s","ended_at":"%s","signal_no_changes":%s,"refactor_status":"%s","verification_verdict":%s,"attempts":[' \
      "$pn" "$title" "$status" "$deps_json" "$started" "$ended" "$signal_no_changes" "$refactor_status" "$verdict"

    # Build attempts array
    local attempt_num=1
    local total_attempts="$attempts"
    [ "$total_attempts" -lt 1 ] 2>/dev/null && total_attempts=1

    while [ "$attempt_num" -le "$total_attempts" ]; do
      if [ "$attempt_num" -gt 1 ]; then
        printf ','
      fi

      local log_file
      if [ "$attempt_num" -lt "$total_attempts" ]; then
        log_file="$run_dir/logs/phase-${pn}.attempt-${attempt_num}.log"
      else
        log_file="$run_dir/logs/phase-${pn}.log"
      fi

      local exec_meta session tools files git_commits
      exec_meta=$(rec_extract_exec_meta "$log_file")
      session=$(rec_extract_session "$log_file")

      # Tools and files only from the last attempt's raw.json
      if [ "$attempt_num" -eq "$total_attempts" ]; then
        tools=$(rec_extract_tools "$run_dir/logs/phase-${pn}.raw.json")
        files=$(rec_extract_files "$run_dir/logs/phase-${pn}.raw.json")
      else
        tools="[]"
        files="[]"
      fi

      git_commits=$(rec_extract_git_commits "$pn")

      # Extract individual fields from exec_meta JSON using sed
      local a_started a_ended a_exit a_duration
      a_started=$(printf '%s' "$exec_meta" | sed -n 's/.*"started_at":\([^,}]*\).*/\1/p')
      a_ended=$(printf '%s' "$exec_meta" | sed -n 's/.*"ended_at":\([^,}]*\).*/\1/p')
      a_exit=$(printf '%s' "$exec_meta" | sed -n 's/.*"exit_code":\([^,}]*\).*/\1/p')
      a_duration=$(printf '%s' "$exec_meta" | sed -n 's/.*"duration_s":\([^,}]*\).*/\1/p')

      printf '{"number":%s,"started_at":%s,"ended_at":%s,"exit_code":%s,"duration_s":%s,"strategy":"standard","fail_reason":null,"session":%s,"tools":%s,"files":%s,"git_commits":%s}' \
        "$attempt_num" "$a_started" "$a_ended" "$a_exit" "$a_duration" "$session" "$tools" "$files" "$git_commits"

      attempt_num=$((attempt_num + 1))
    done

    printf ']}'
  done

  printf ']}'
}
