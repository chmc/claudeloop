#!/bin/sh

# Recorder — run overview for Replay reports
# Extracts run-level overview data from metadata.txt or PROGRESS.md,
# and aggregates session metrics across all log files.
# Sourced by lib/recorder.sh.

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
  # Default empty aggregate fields (AWK crash or empty log directory)
  [ -z "$total_cost" ] && total_cost=0
  [ -z "$total_in" ] && total_in=0
  [ -z "$total_out" ] && total_out=0
  [ -z "$total_cr" ] && total_cr=0
  [ -z "$total_cw" ] && total_cw=0

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
  # Default empty aggregate fields (AWK crash or empty log directory)
  [ -z "$total_cost" ] && total_cost=0
  [ -z "$total_in" ] && total_in=0
  [ -z "$total_out" ] && total_out=0
  [ -z "$total_cr" ] && total_cr=0
  [ -z "$total_cw" ] && total_cw=0

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
  find "$logs_dir" \( -name 'phase-*.log' -o -name 'phase-*.attempt-*.log' \) \
    -not -name '*verify*' -not -name '*refactor*' -not -name '*formatted*' 2>/dev/null | sort | while IFS= read -r f; do
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
    /\[Session: model=/ {
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
