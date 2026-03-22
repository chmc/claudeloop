#!/bin/sh

# Recorder library — generates Replay reports
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
        "Attempt "*" Strategy: "*)
          local _asn _asv
          _asn=$(printf '%s\n' "$line" | sed 's/^Attempt \([0-9]*\) Strategy:.*/\1/')
          _asv=$(printf '%s\n' "$line" | sed 's/^Attempt [0-9]* Strategy:[[:space:]]*//')
          eval "_REC_PHASE_ATTEMPT_STRATEGY_${pv}_${_asn}='$_asv'"
          ;;
        "Attempt "*" Fail Reason: "*)
          local _afn _afv
          _afn=$(printf '%s\n' "$line" | sed 's/^Attempt \([0-9]*\) Fail Reason:.*/\1/')
          _afv=$(printf '%s\n' "$line" | sed 's/^Attempt [0-9]* Fail Reason:[[:space:]]*//')
          eval "_REC_PHASE_ATTEMPT_FAIL_REASON_${pv}_${_afn}='$_afv'"
          ;;
        "Attempt "*" Started: "*)
          local _atn _atv
          _atn=$(printf '%s\n' "$line" | sed 's/^Attempt \([0-9]*\) Started:.*/\1/')
          _atv=$(printf '%s\n' "$line" | sed 's/^Attempt [0-9]* Started:[[:space:]]*//')
          eval "_REC_PHASE_ATTEMPT_TIME_${pv}_${_atn}='$_atv'"
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
# Args: $1 - field, $2 - phase number, $3 - (optional) attempt number
_rec_get() {
  local pv
  pv=$(phase_to_var "$2")
  if [ $# -ge 3 ]; then
    eval "printf '%s' \"\${_REC_PHASE_${1}_${pv}_${3}:-}\""
  else
    eval "printf '%s' \"\${_REC_PHASE_${1}_${pv}:-}\""
  fi
}

# Read template HTML, replace <!--JSON_DATA--> marker with JSON data, write output.
# Uses line-split approach (head/tail around marker line) to avoid awk string-length limits.
# Args: $1 - JSON file path, $2 - output HTML path
inject_and_write_html() {
  local json_file="$1"
  local output_path="$2"
  local template_dir="${SCRIPT_DIR:+$SCRIPT_DIR/assets}"
  template_dir="${template_dir:-${CLAUDELOOP_DIR:+$CLAUDELOOP_DIR/assets}}"
  template_dir="${template_dir:-assets}"
  local template="${template_dir}/replay-template.html"

  if [ ! -f "$template" ]; then
    return 1
  fi
  if [ ! -f "$json_file" ]; then
    return 1
  fi

  # Find the marker line number
  local marker_line
  marker_line=$(grep -n '<!--JSON_DATA-->' "$template" | head -1 | cut -d: -f1)
  if [ -z "$marker_line" ]; then
    return 1
  fi

  local temp_html="${output_path}.tmp"
  local before_line=$((marker_line - 1))
  local after_line=$((marker_line + 1))

  {
    # Lines before the marker
    if [ "$before_line" -ge 1 ]; then
      head -n "$before_line" "$template"
    fi
    # Inject: const DATA = <json>;
    printf 'const DATA = '
    sed 's/</\\u003c/g' "$json_file"
    printf ';\n'
    # Lines after the marker
    tail -n +"$after_line" "$template"
  } > "$temp_html"

  mv "$temp_html" "$output_path"
}

# Assemble JSON and inject into HTML template to produce replay.html.
# Silent on failure — must never break the execution loop.
# Args: $1 - run directory (e.g. ".claudeloop")
generate_replay() {
  local run_dir="$1"
  local json_tmp="${run_dir}/recorder.json.tmp"
  local output_html="${run_dir}/replay.html"
  local _verbose="${_RECORDER_VERBOSE:-false}"
  local _ts

  local _spin_pid=""
  local _start_s=""

  if [ "$_verbose" = "true" ]; then
    _ts=$(date '+%H:%M:%S')
    printf '[%s] Generating replay...\n' "$_ts" >&2

    # Load progress to count phases for status message
    rec_load_progress "$run_dir" 2>/dev/null
    local _phase_count=0
    for _ in $_REC_PHASE_NUMBERS; do _phase_count=$(( _phase_count + 1 )); done

    _start_s=$(date +%s)

    # Launch background elapsed-time updater if stderr is a terminal
    if [ -t 2 ]; then
      _parent_pid=$$
      (
        while kill -0 "$_parent_pid" 2>/dev/null; do
          _elapsed=$(( $(date +%s) - _start_s ))
          printf '\033[2K\r[%s]   Assembling data for %d phases... (%ds)' \
            "$(date '+%H:%M:%S')" "$_phase_count" "$_elapsed" >&2
          sleep 1
        done
      ) &
      _spin_pid=$!
    else
      _ts=$(date '+%H:%M:%S')
      printf '[%s]   Assembling data for %d phases...\n' "$_ts" "$_phase_count" >&2
    fi
  fi

  # Assemble JSON to temp file (redirect stderr for both shell and command errors)
  if ! ( assemble_recorder_json "$run_dir" > "$json_tmp" ) 2>/dev/null; then
    if [ -n "$_spin_pid" ]; then
      kill "$_spin_pid" 2>/dev/null; wait "$_spin_pid" 2>/dev/null || true
      _spin_pid=""
      printf '\033[2K\r' >&2
    fi
    rm -f "$json_tmp" 2>/dev/null
    return 0
  fi

  # Stop spinner and print final elapsed time
  if [ -n "$_spin_pid" ]; then
    kill "$_spin_pid" 2>/dev/null; wait "$_spin_pid" 2>/dev/null || true
    _spin_pid=""
  fi
  if [ "$_verbose" = "true" ]; then
    local _elapsed=0
    if [ -n "$_start_s" ]; then
      _elapsed=$(( $(date +%s) - _start_s ))
    fi
    printf '\033[2K\r[%s]   Assembled data for %d phases (%ds)\n' \
      "$(date '+%H:%M:%S')" "$_phase_count" "$_elapsed" >&2
    _ts=$(date '+%H:%M:%S')
    printf '[%s]   Writing HTML...\n' "$_ts" >&2
  fi

  # Inject into HTML template
  if ! inject_and_write_html "$json_tmp" "$output_html" 2>/dev/null; then
    rm -f "$json_tmp" 2>/dev/null
    return 0
  fi

  rm -f "$json_tmp" 2>/dev/null
  return 0
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

    # Bug 5: Use earliest attempt start time for phase started_at
    local first_attempt_start
    first_attempt_start=$(_rec_get ATTEMPT_TIME "$pn" 1)
    if [ -n "$first_attempt_start" ]; then
      if [ -z "$started" ] || [ "$first_attempt_start" \< "$started" ]; then
        started="$first_attempt_start"
      fi
    fi

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

      local exec_meta session tools files git_commits prompt_text
      exec_meta=$(rec_extract_exec_meta "$log_file")
      session=$(rec_extract_session "$log_file")
      prompt_text=$(rec_extract_prompt_text "$log_file")

      # Tools and files from per-attempt raw.json
      local raw_file
      raw_file="$run_dir/logs/phase-${pn}.attempt-${attempt_num}.raw.json"
      if [ ! -f "$raw_file" ] || [ ! -s "$raw_file" ]; then
        # Fallback for old archives or single-attempt phases
        if [ "$attempt_num" -eq "$total_attempts" ]; then
          raw_file="$run_dir/logs/phase-${pn}.raw.json"
        fi
      fi
      tools=$(rec_extract_tools "$raw_file")
      files=$(rec_extract_files "$raw_file")
      local tool_calls
      tool_calls=$(rec_extract_tool_calls "$raw_file")

      git_commits=$(rec_extract_git_commits "$pn")

      # Extract individual fields from exec_meta JSON using sed
      local a_started a_ended a_exit a_duration
      a_started=$(printf '%s' "$exec_meta" | sed -n 's/.*"started_at":\([^,}]*\).*/\1/p')
      a_ended=$(printf '%s' "$exec_meta" | sed -n 's/.*"ended_at":\([^,}]*\).*/\1/p')
      a_exit=$(printf '%s' "$exec_meta" | sed -n 's/.*"exit_code":\([^,}]*\).*/\1/p')
      a_duration=$(printf '%s' "$exec_meta" | sed -n 's/.*"duration_s":\([^,}]*\).*/\1/p')

      # Format prompt_text as JSON value (already escaped, wrap in quotes; or null)
      local prompt_json
      if [ "$prompt_text" = "null" ]; then
        prompt_json="null"
      else
        prompt_json="\"$prompt_text\""
      fi

      # Per-attempt strategy and fail_reason from PROGRESS.md (with defaults)
      local a_strategy a_fail_reason a_fail_json
      a_strategy=$(_rec_get ATTEMPT_STRATEGY "$pn" "$attempt_num")
      [ -z "$a_strategy" ] && a_strategy="standard"
      a_fail_reason=$(_rec_get ATTEMPT_FAIL_REASON "$pn" "$attempt_num")
      if [ -n "$a_fail_reason" ]; then
        a_fail_json="\"$a_fail_reason\""
      else
        a_fail_json="null"
      fi

      # Compute is_success: only last attempt of a completed phase is success
      local a_is_success="false"
      if [ "$status" = "completed" ] && [ "$attempt_num" -eq "$total_attempts" ]; then
        a_is_success="true"
      fi

      printf '{"number":%s,"started_at":%s,"ended_at":%s,"exit_code":%s,"duration_s":%s,"strategy":"%s","fail_reason":%s,"is_success":%s,"session":%s,"tools":%s,"files":%s,"tool_calls":%s,"git_commits":%s,"prompt_text":%s}' \
        "$attempt_num" "$a_started" "$a_ended" "$a_exit" "$a_duration" "$a_strategy" "$a_fail_json" "$a_is_success" "$session" "$tools" "$files" "$tool_calls" "$git_commits" "$prompt_json"

      attempt_num=$((attempt_num + 1))
    done

    printf ']}'
  done

  printf ']}'
}
