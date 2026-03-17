#!/bin/sh

# Flight Recorder Library
# Extracts execution data from .claudeloop/ artifacts and produces JSON.
# All functions use _REC_ prefix for their own variables to avoid polluting
# the global PHASE_* namespace used by the main orchestrator.

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

# Extract session metrics from a log file's [Session:] line.
# Args: $1 - log file path
# Prints: JSON object or "null"
rec_extract_session() {
  local log_file="$1"

  if [ ! -f "$log_file" ]; then
    echo "null"
    return 0
  fi

  local session_line
  session_line=$(grep '^\[Session:' "$log_file" | tail -1)

  if [ -z "$session_line" ]; then
    echo "null"
    return 0
  fi

  # Extract fields via sed
  local model cost duration turns input_tokens output_tokens cache_read cache_write
  model=$(printf '%s' "$session_line" | sed -n 's/.*model=\([^ ]*\).*/\1/p')
  cost=$(printf '%s' "$session_line" | sed -n 's/.*cost=\$\([0-9.]*\).*/\1/p')
  duration=$(printf '%s' "$session_line" | sed -n 's/.*duration=\([0-9.]*\)s.*/\1/p')
  turns=$(printf '%s' "$session_line" | sed -n 's/.*turns=\([0-9]*\).*/\1/p')
  input_tokens=$(printf '%s' "$session_line" | sed -n 's/.*tokens=\([0-9]*\)in.*/\1/p')
  output_tokens=$(printf '%s' "$session_line" | sed -n 's/.*tokens=[0-9]*in\/\([0-9]*\)out.*/\1/p')

  # Cache fields are optional
  cache_read=$(printf '%s' "$session_line" | sed -n 's/.*cache=\([0-9]*\)r.*/\1/p')
  cache_write=$(printf '%s' "$session_line" | sed -n 's/.*cache=[0-9]*r\/\([0-9]*\)w.*/\1/p')
  [ -z "$cache_read" ] && cache_read=0
  [ -z "$cache_write" ] && cache_write=0

  printf '{"model":"%s","cost_usd":%s,"duration_s":%s,"turns":%s,"input_tokens":%s,"output_tokens":%s,"cache_read":%s,"cache_write":%s}' \
    "$model" "$cost" "$duration" "$turns" "$input_tokens" "$output_tokens" "$cache_read" "$cache_write"
}

# Extract execution start/end metadata from a log file.
# Args: $1 - log file path
# Prints: JSON object
rec_extract_exec_meta() {
  local log_file="$1"

  if [ ! -f "$log_file" ]; then
    printf '{"started_at":null,"ended_at":null,"exit_code":null,"duration_s":null}'
    return 0
  fi

  local start_line end_line
  start_line=$(grep '^=== EXECUTION START ' "$log_file" | tail -1)
  end_line=$(grep '^=== EXECUTION END ' "$log_file" | tail -1)

  local started_at="null"
  if [ -n "$start_line" ]; then
    local st
    st=$(printf '%s' "$start_line" | sed -n 's/.*time=\([^ ]*\) ===$/\1/p')
    [ -n "$st" ] && started_at="\"$st\""
  fi

  if [ -z "$end_line" ]; then
    printf '{"started_at":%s,"ended_at":null,"exit_code":null,"duration_s":null}' "$started_at"
    return 0
  fi

  local ended_at exit_code duration_s
  ended_at=$(printf '%s' "$end_line" | sed -n 's/.*time=\([^ ]*\) ===$/\1/p')
  exit_code=$(printf '%s' "$end_line" | sed -n 's/.*exit_code=\([0-9]*\).*/\1/p')
  duration_s=$(printf '%s' "$end_line" | sed -n 's/.*duration=\([0-9]*\)s.*/\1/p')

  printf '{"started_at":%s,"ended_at":"%s","exit_code":%s,"duration_s":%s}' \
    "$started_at" "$ended_at" "$exit_code" "$duration_s"
}

# Count tool_use events by tool name from a raw JSON log.
# Args: $1 - raw JSON file path
# Prints: JSON array sorted by name
rec_extract_tools() {
  local raw_file="$1"

  if [ ! -f "$raw_file" ] || [ ! -s "$raw_file" ]; then
    echo "[]"
    return 0
  fi

  awk '
    /"type":"tool_use"/ {
      # Extract tool name using index/substr (POSIX awk)
      idx = index($0, "\"name\":\"")
      if (idx > 0) {
        rest = substr($0, idx + 8)
        end = index(rest, "\"")
        if (end > 0) {
          name = substr(rest, 1, end - 1)
          counts[name]++
        }
      }
    }
    END {
      # Sort names: collect into array, simple insertion sort
      n = 0
      for (name in counts) {
        names[n++] = name
      }
      for (i = 1; i < n; i++) {
        key = names[i]
        j = i - 1
        while (j >= 0 && names[j] > key) {
          names[j+1] = names[j]
          j--
        }
        names[j+1] = key
      }
      printf "["
      for (i = 0; i < n; i++) {
        if (i > 0) printf ","
        printf "{\"name\":\"%s\",\"count\":%d}", names[i], counts[names[i]]
      }
      printf "]"
    }
  ' "$raw_file"
}

# Extract file paths and operations from raw JSON tool_use events.
# Args: $1 - raw JSON file path
# Prints: JSON array of {path, ops} sorted by path
rec_extract_files() {
  local raw_file="$1"

  if [ ! -f "$raw_file" ] || [ ! -s "$raw_file" ]; then
    echo "[]"
    return 0
  fi

  awk '
    /"type":"tool_use"/ {
      # Extract tool name (POSIX awk)
      idx = index($0, "\"name\":\"")
      tool = ""
      if (idx > 0) {
        rest = substr($0, idx + 8)
        end = index(rest, "\"")
        if (end > 0) tool = substr(rest, 1, end - 1)
      }
      if (tool == "Read" || tool == "Edit" || tool == "Write") {
        # Extract file_path
        idx2 = index($0, "\"file_path\":\"")
        if (idx2 > 0) {
          rest2 = substr($0, idx2 + 13)
          end2 = index(rest2, "\"")
          if (end2 > 0) {
            path = substr(rest2, 1, end2 - 1)
            key = path SUBSEP tool
            if (!(key in seen)) {
              seen[key] = 1
              if (!(path in paths)) {
                paths[path] = tool
                path_order[path_count++] = path
              } else {
                paths[path] = paths[path] " " tool
              }
            }
          }
        }
      }
    }
    END {
      # Sort paths: insertion sort
      for (i = 1; i < path_count; i++) {
        key = path_order[i]
        j = i - 1
        while (j >= 0 && path_order[j] > key) {
          path_order[j+1] = path_order[j]
          j--
        }
        path_order[j+1] = key
      }
      printf "["
      for (i = 0; i < path_count; i++) {
        if (i > 0) printf ","
        path = path_order[i]
        # Sort ops for this path
        split(paths[path], ops, " ")
        nops = 0
        for (k in ops) {
          sorted_ops[nops++] = ops[k]
        }
        for (a = 1; a < nops; a++) {
          tmp = sorted_ops[a]
          b = a - 1
          while (b >= 0 && sorted_ops[b] > tmp) {
            sorted_ops[b+1] = sorted_ops[b]
            b--
          }
          sorted_ops[b+1] = tmp
        }
        printf "{\"path\":\"%s\",\"ops\":[", path
        for (o = 0; o < nops; o++) {
          if (o > 0) printf ","
          printf "\"%s\"", sorted_ops[o]
        }
        printf "]}"
        delete sorted_ops
      }
      printf "]"
    }
  ' "$raw_file"
}

# Check verification verdict for a phase.
# Args: $1 - run directory, $2 - phase number
# Prints: "passed", "failed", or null (unquoted JSON)
rec_verify_verdict() {
  local run_dir="$1" phase_num="$2"
  local verify_log="$run_dir/logs/phase-${phase_num}.verify.log"

  if [ ! -f "$verify_log" ]; then
    echo "null"
    return 0
  fi

  if grep -q 'VERIFICATION_PASSED' "$verify_log"; then
    echo '"passed"'
  elif grep -q 'VERIFICATION_FAILED' "$verify_log"; then
    echo '"failed"'
  else
    echo "null"
  fi
}

# Extract git commits for a phase.
# Args: $1 - phase number
# Prints: JSON array of {sha, message}
rec_extract_git_commits() {
  local phase_num="$1"

  local commits
  commits=$(git log --oneline --grep="Phase ${phase_num}:" 2>/dev/null) || true

  if [ -z "$commits" ]; then
    echo "[]"
    return 0
  fi

  printf '['
  local first=true
  printf '%s\n' "$commits" | while IFS= read -r line; do
    local sha msg
    sha=$(printf '%s' "$line" | cut -d' ' -f1)
    msg=$(printf '%s' "$line" | cut -d' ' -f2-)
    msg=$(json_escape "$msg")
    if [ "$first" = "true" ]; then
      first=false
    else
      printf ','
    fi
    printf '{"sha":"%s","message":"%s"}' "$sha" "$msg"
  done
  printf ']'
}

# Parse metadata.txt or compute run overview from PROGRESS.md.
# Args: $1 - run directory
# Prints: JSON object for "run" key
rec_extract_run_overview() {
  local run_dir="$1"

  if [ -f "$run_dir/metadata.txt" ]; then
    _rec_overview_from_metadata "$run_dir"
  else
    _rec_overview_from_progress "$run_dir"
  fi
}

# Internal: build overview from metadata.txt
_rec_overview_from_metadata() {
  local run_dir="$1"
  local plan_file="" phase_count=0 completed=0 failed=0 pending=0

  while IFS='=' read -r key value; do
    case "$key" in
      plan_file) plan_file="$value" ;;
      phase_count) phase_count="$value" ;;
      completed) completed="$value" ;;
      failed) failed="$value" ;;
      pending) pending="$value" ;;
    esac
  done < "$run_dir/metadata.txt"

  # Aggregate session costs from all log files
  local totals
  totals=$(_rec_aggregate_sessions "$run_dir")

  local total_cost total_in total_out total_cr total_cw started_at ended_at
  total_cost=$(printf '%s' "$totals" | cut -d'|' -f1)
  total_in=$(printf '%s' "$totals" | cut -d'|' -f2)
  total_out=$(printf '%s' "$totals" | cut -d'|' -f3)
  total_cr=$(printf '%s' "$totals" | cut -d'|' -f4)
  total_cw=$(printf '%s' "$totals" | cut -d'|' -f5)
  started_at=$(printf '%s' "$totals" | cut -d'|' -f6)
  ended_at=$(printf '%s' "$totals" | cut -d'|' -f7)

  plan_file=$(json_escape "$plan_file")

  printf '{"plan_file":"%s","phase_count":%s,"completed":%s,"failed":%s,"pending":%s,"started_at":"%s","ended_at":"%s","total_cost_usd":%s,"total_input_tokens":%s,"total_output_tokens":%s,"total_cache_read":%s,"total_cache_write":%s}' \
    "$plan_file" "$phase_count" "$completed" "$failed" "$pending" \
    "$started_at" "$ended_at" "$total_cost" "$total_in" "$total_out" "$total_cr" "$total_cw"
}

# Internal: build overview from _REC_PHASE_* variables (must call rec_load_progress first)
_rec_overview_from_progress() {
  local run_dir="$1"

  # Ensure progress is loaded
  if [ "$_REC_PHASE_COUNT" = "0" ] || [ -z "$_REC_PHASE_COUNT" ]; then
    rec_load_progress "$run_dir"
  fi

  local completed=0 failed=0 pending=0
  for pn in $_REC_PHASE_NUMBERS; do
    local st
    st=$(_rec_get STATUS "$pn")
    case "$st" in
      completed) completed=$((completed + 1)) ;;
      failed) failed=$((failed + 1)) ;;
      *) pending=$((pending + 1)) ;;
    esac
  done

  # Aggregate session costs
  local totals
  totals=$(_rec_aggregate_sessions "$run_dir")

  local total_cost total_in total_out total_cr total_cw started_at ended_at
  total_cost=$(printf '%s' "$totals" | cut -d'|' -f1)
  total_in=$(printf '%s' "$totals" | cut -d'|' -f2)
  total_out=$(printf '%s' "$totals" | cut -d'|' -f3)
  total_cr=$(printf '%s' "$totals" | cut -d'|' -f4)
  total_cw=$(printf '%s' "$totals" | cut -d'|' -f5)
  started_at=$(printf '%s' "$totals" | cut -d'|' -f6)
  ended_at=$(printf '%s' "$totals" | cut -d'|' -f7)

  printf '{"plan_file":"","phase_count":%s,"completed":%s,"failed":%s,"pending":%s,"started_at":"%s","ended_at":"%s","total_cost_usd":%s,"total_input_tokens":%s,"total_output_tokens":%s,"total_cache_read":%s,"total_cache_write":%s}' \
    "$_REC_PHASE_COUNT" "$completed" "$failed" "$pending" \
    "$started_at" "$ended_at" "$total_cost" "$total_in" "$total_out" "$total_cr" "$total_cw"
}

# Internal: aggregate session metrics from all log files in a run.
# Prints: total_cost|total_in|total_out|total_cr|total_cw|earliest_start|latest_end
_rec_aggregate_sessions() {
  local run_dir="$1"
  local logs_dir="$run_dir/logs"

  if [ ! -d "$logs_dir" ]; then
    echo "0|0|0|0|0||"
    return 0
  fi

  # Use awk to aggregate all session lines across all log files
  find "$logs_dir" -name 'phase-*.log' -o -name 'phase-*.attempt-*.log' 2>/dev/null | sort | while IFS= read -r f; do
    [ -f "$f" ] && cat "$f"
  done | awk '
    function extract_after(s, prefix,    idx, rest, end) {
      idx = index(s, prefix)
      if (idx == 0) return ""
      rest = substr(s, idx + length(prefix))
      # Find end: space, ], or end of string
      end = match(rest, /[[:space:]\]]/)
      if (end > 0) return substr(rest, 1, end - 1)
      return rest
    }
    BEGIN {
      total_cost = 0; total_in = 0; total_out = 0; total_cr = 0; total_cw = 0
      earliest = ""; latest = ""
    }
    /^\[Session:/ {
      v = extract_after($0, "cost=$"); if (v != "") total_cost += v
      v = extract_after($0, "tokens="); if (v != "") { split(v, tk, "in"); total_in += tk[1] }
      v = extract_after($0, "tokens="); if (v != "") { split(v, tk2, "/"); gsub(/[^0-9]/, "", tk2[2]); total_out += tk2[2] }
      v = extract_after($0, "cache="); if (v != "") { split(v, ck, "r"); total_cr += ck[1] }
      v = extract_after($0, "cache="); if (v != "") { split(v, ck2, "/"); gsub(/[^0-9]/, "", ck2[2]); total_cw += ck2[2] }
    }
    /^=== EXECUTION START/ {
      v = extract_after($0, "time=")
      gsub(/ ===.*/, "", v)
      if (v != "" && (earliest == "" || v < earliest)) earliest = v
    }
    /^=== EXECUTION END/ {
      v = extract_after($0, "time=")
      gsub(/ ===.*/, "", v)
      if (v != "" && (latest == "" || v > latest)) latest = v
    }
    END {
      printf "%.4f|%d|%d|%d|%d|%s|%s", total_cost, total_in, total_out, total_cr, total_cw, earliest, latest
    }
  '
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
