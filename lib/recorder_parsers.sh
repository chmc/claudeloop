#!/bin/sh

# Flight Recorder — Extraction Parsers
# Individual extraction functions for log files and raw JSON artifacts.
# Sourced by lib/recorder.sh.

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

# Extract prompt text between === PROMPT === and === RESPONSE === markers.
# If prompt exceeds 200 lines, truncates to first 80 + last 80 with omission notice.
# Args: $1 - log file path
# Prints: JSON-escaped prompt text, or "null" if missing
rec_extract_prompt_text() {
  local log_file="$1"

  if [ ! -f "$log_file" ]; then
    echo "null"
    return 0
  fi

  # Extract lines between markers using awk
  local raw_text
  raw_text=$(awk '
    /^=== PROMPT ===/ { capture = 1; next }
    /^=== RESPONSE ===/ { capture = 0 }
    capture { print }
  ' "$log_file")

  if [ -z "$raw_text" ]; then
    echo "null"
    return 0
  fi

  # Count lines
  local line_count
  line_count=$(printf '%s\n' "$raw_text" | wc -l | tr -d ' ')

  if [ "$line_count" -gt 200 ]; then
    local head_part tail_part omitted
    omitted=$((line_count - 160))
    head_part=$(printf '%s\n' "$raw_text" | head -n 80)
    tail_part=$(printf '%s\n' "$raw_text" | tail -n 80)
    raw_text=$(printf '%s\n... %s lines omitted ...\n%s' "$head_part" "$omitted" "$tail_part")
  fi

  json_escape "$raw_text"
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
