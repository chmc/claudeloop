#!/bin/sh

# stream_processor.sh - Parse claude --output-format=stream-json events.
# Can be sourced (defines process_stream_json) or run standalone as:
#   sh lib/stream_processor.sh <log_file> <raw_log>

# process_stream_json: parse stream-json from stdin
# Args: $1 - log_file path, $2 - raw_log path, $3 - hooks_enabled (true|false, default false)
process_stream_json() {
  local log_file="$1"
  local raw_log="$2"
  local hooks_enabled="${3:-false}"
  local live_log="${4:-}"
  awk -v log_file="$log_file" -v raw_log="$raw_log" \
      -v trunc_len="${STREAM_TRUNCATE_LEN:-300}" \
      -v hooks_enabled="$hooks_enabled" \
      -v live_log="$live_log" '
  # extract(s, key) - return scalar value for "key":value in s
  # Returns: string value (unescape \n \t \"), numeric/bool raw text,
  #          or "" for object/array values (signals non-scalar)
  function extract(s, key,    tag, i, c, val, esc) {
    tag = "\"" key "\":"
    i = index(s, tag)
    if (i == 0) return ""
    i += length(tag)
    c = substr(s, i, 1)
    if (c == "\"") {
      val = ""
      esc = 0
      i++
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (esc) {
          if (c == "n") val = val "\n"
          else if (c == "t") val = val "\t"
          else val = val c
          esc = 0
        } else if (c == "\\") {
          esc = 1
        } else if (c == "\"") {
          break
        } else {
          val = val c
        }
        i++
      }
      return val
    } else if (c == "{" || c == "[") {
      return ""
    } else {
      val = ""
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (c == "," || c == "}" || c == "]" || c == " ") break
        val = val c
        i++
      }
      return val
    }
  }

  # trunc(s, max) - replace newlines with spaces, truncate to max chars + "..."
  function trunc(s, max,    i, c) {
    gsub(/\n/, " ", s)
    if (length(s) > max) return substr(s, 1, max) "..."
    return s
  }

  # get_time() - return current HH:MM:SS via shell date (POSIX awk)
  function get_time(    ts) {
    "date '+%H:%M:%S'" | getline ts
    close("date '+%H:%M:%S'")
    return ts
  }

  # get_epoch() - return current Unix timestamp in seconds
  function get_epoch(    ep) {
    "date +%s" | getline ep
    close("date +%s")
    return ep + 0
  }

  BEGIN {
    at_line_start = 1
    live_at_line_start = 1
    spinner = "|/-\\"
    spinner_idx = 0
    spinner_start = 0
    last_rate_limit_pct = 0
    prev_total_cost = 0
    printf "[%s]\n", get_time()
    if (live_log != "") { printf "[%s]\n", get_time() >> live_log }
    fflush()
  }

  {
    line = $0
    print line >> raw_log

    if (substr(line, 1, 1) != "{") {
      print line
      print line >> log_file
      if (live_log != "") { printf "[%s] %s\n", get_time(), line >> live_log; fflush(live_log) }
      next
    }

    etype = extract(line, "type")

    if (etype == "assistant") {
      text = extract(line, "text")
      if (text != "") {
        if (!at_line_start) {
          printf "\r%-12s\r\n", ""
          fflush()
          if (live_log != "" && !live_at_line_start) { printf "\n" >> live_log; fflush(live_log); live_at_line_start = 1 }
          at_line_start = 1
        }
        spinner_start = 0
        if (at_line_start) printf "[%s] ", get_time()
        if (live_log != "") {
          if (live_at_line_start) printf "[%s] ", get_time() >> live_log
          printf "%s", text >> live_log
          live_at_line_start = (substr(text, length(text), 1) == "\n")
          fflush(live_log)
        }
        printf "%s", text
        printf "%s", text >> log_file
        fflush()
        at_line_start = (substr(text, length(text), 1) == "\n")
      } else if (index(line, "\"type\":\"tool_use\"") > 0) {
        n_tools = split(line, tool_segs, "\"type\":\"tool_use\"")
        for (ti = 2; ti <= n_tools; ti++) {
          seg = tool_segs[ti]
          tool_id = extract(seg, "id")
          if (tool_id != "" && (tool_id in shown_tools)) continue
          if (tool_id != "") shown_tools[tool_id] = 1
          if (!at_line_start) { printf "\r%-12s\r\n", ""; fflush(); if (live_log != "" && !live_at_line_start) { printf "\n" >> live_log; fflush(live_log); live_at_line_start = 1 }; at_line_start = 1 }
          spinner_start = 0
          name = extract(seg, "name")
          cmd = ""; fp = ""; pat = ""; url = ""; query = ""; npath = ""; stype = ""
          if      (name == "Bash")                                      cmd   = extract(seg, "command")
          else if (name == "Read" || name == "Write" || name == "Edit") fp    = extract(seg, "file_path")
          else if (name == "Glob" || name == "Grep")                    pat   = extract(seg, "pattern")
          else if (name == "WebFetch")                                   url   = extract(seg, "url")
          else if (name == "WebSearch")                                  query = extract(seg, "query")
          else if (name == "NotebookEdit")                               npath = extract(seg, "notebook_path")
          else if (name == "Task")                                       stype = extract(seg, "subagent_type")
          desc = extract(seg, "description")
          if      (cmd   != "")  preview = trunc(cmd,   trunc_len)
          else if (fp    != "")  preview = trunc(fp,    trunc_len)
          else if (pat   != "")  preview = trunc(pat,   trunc_len)
          else if (url   != "")  preview = trunc(url,   trunc_len)
          else if (query != "")  preview = trunc(query, trunc_len)
          else if (npath != "")  preview = trunc(npath, trunc_len)
          else if (stype != "")  preview = stype
          else                   preview = ""
          if (desc != "" && preview != "") preview = preview " \342\200\224 " trunc(desc, 80)
          else if (desc != "")             preview = trunc(desc, 80)
          if (hooks_enabled != "true") {
            if (preview != "") {
              printf "  [Tool: %s] %s\n", name, preview > "/dev/stderr"
              if (live_log != "") printf "  [%s] [Tool: %s] %s\n", get_time(), name, preview >> live_log
            } else {
              printf "  [Tool: %s]\n", name > "/dev/stderr"
              if (live_log != "") printf "  [%s] [Tool: %s]\n", get_time(), name >> live_log
            }
          }
        }
        if (live_log != "") fflush(live_log)
      } else {
        now = get_epoch()
        if (spinner_start == 0) {
          spinner_start = now
          if (!at_line_start) printf "\n"
        }
        printf "\r%s %ds", substr(spinner, (spinner_idx % 4) + 1, 1), now - spinner_start
        fflush()
        at_line_start = 0
        spinner_idx++
      }
      stop = extract(line, "stop_reason")
      if (stop == "max_tokens") {
        if (!at_line_start) { printf "\r%-12s\r\n", ""; fflush(); at_line_start = 1 }
        printf "  [Warning: max_tokens \342\200\224 output was truncated]\n" > "/dev/stderr"
        if (live_log != "") { printf "  [%s] [Warning: max_tokens \342\200\224 output was truncated]\n", get_time() >> live_log; fflush(live_log) }
      }

    } else if (etype == "tool_use") {
      if (!at_line_start) {
        printf "\r%-12s\r\n", ""
        fflush()
        if (live_log != "" && !live_at_line_start) { printf "\n" >> live_log; fflush(live_log); live_at_line_start = 1 }
        at_line_start = 1
      }
      spinner_start = 0
      name = extract(line, "name")
      cmd = ""; fp = ""; pat = ""; url = ""; query = ""; npath = ""; stype = ""
      if      (name == "Bash")                                      cmd   = extract(line, "command")
      else if (name == "Read" || name == "Write" || name == "Edit") fp    = extract(line, "file_path")
      else if (name == "Glob" || name == "Grep")                    pat   = extract(line, "pattern")
      else if (name == "WebFetch")                                   url   = extract(line, "url")
      else if (name == "WebSearch")                                  query = extract(line, "query")
      else if (name == "NotebookEdit")                               npath = extract(line, "notebook_path")
      else if (name == "Task")                                       stype = extract(line, "subagent_type")
      if      (cmd   != "")  preview = trunc(cmd,   trunc_len)
      else if (fp    != "")  preview = trunc(fp,    trunc_len)
      else if (pat   != "")  preview = trunc(pat,   trunc_len)
      else if (url   != "")  preview = trunc(url,   trunc_len)
      else if (query != "")  preview = trunc(query, trunc_len)
      else if (npath != "")  preview = trunc(npath, trunc_len)
      else if (stype != "")  preview = stype
      else                   preview = ""
      if (hooks_enabled != "true") {
        if (preview != "") {
          printf "  [Tool: %s] %s\n", name, preview > "/dev/stderr"
          if (live_log != "") { printf "  [%s] [Tool: %s] %s\n", get_time(), name, preview >> live_log; fflush(live_log) }
        } else {
          printf "  [Tool: %s]\n", name > "/dev/stderr"
          if (live_log != "") { printf "  [%s] [Tool: %s]\n", get_time(), name >> live_log; fflush(live_log) }
        }
      }

    } else if (etype == "tool_result") {
      if (!at_line_start) {
        printf "\r%-12s\r\n", ""
        fflush()
        if (live_log != "" && !live_at_line_start) { printf "\n" >> live_log; fflush(live_log); live_at_line_start = 1 }
        at_line_start = 1
      }
      spinner_start = 0
      content = extract(line, "content")
      preview = ""
      if (content != "") {
        total = length(content)
        preview = substr(content, 1, 200)
      } else {
        total = 0
        n = split(line, parts, "\"text\":\"")
        for (j = 2; j <= n; j++) {
          k = 1
          while (k <= length(parts[j])) {
            c = substr(parts[j], k, 1)
            if (c == "\\") { k += 2; continue }
            if (c == "\"") break
            if (length(preview) < 200) preview = preview c
            total++
            k++
          }
        }
      }
      printf "  [Tool result: %d chars] %s\n", total, trunc(preview, 200) > "/dev/stderr"
      if (live_log != "") { printf "  [%s] [Tool result: %d chars] %s\n", get_time(), total, trunc(preview, 200) >> live_log; fflush(live_log) }

    } else if (etype == "user") {
      tool_result = extract(line, "tool_use_result")
      if (tool_result != "") {
        if (!at_line_start) { printf "\r%-12s\r\n", ""; fflush(); if (live_log != "" && !live_at_line_start) { printf "\n" >> live_log; fflush(live_log); live_at_line_start = 1 }; at_line_start = 1 }
        spinner_start = 0
        is_err = (index(line, "\"is_error\":true") > 0) ? " [error]" : ""
        printf "  [Result%s: %d chars] %s\n", is_err, length(tool_result), trunc(tool_result, 200) > "/dev/stderr"
        if (live_log != "") { printf "  [%s] [Result%s: %d chars] %s\n", get_time(), is_err, length(tool_result), trunc(tool_result, 200) >> live_log; fflush(live_log) }
      }

    } else if (etype == "result") {
      if (!at_line_start) {
        printf "\r%-12s\r\n", ""
        fflush()
        if (live_log != "" && !live_at_line_start) { printf "\n" >> live_log; fflush(live_log); live_at_line_start = 1 }
        at_line_start = 1
      }
      spinner_start = 0
      total_cost = extract(line, "total_cost_usd") + 0
      session_cost = total_cost - prev_total_cost
      prev_total_cost = total_cost
      duration_ms = extract(line, "duration_ms")
      num_turns = extract(line, "num_turns")
      input_tokens = extract(line, "input_tokens")
      output_tokens = extract(line, "output_tokens")
      model = ""
      mu_idx = index(line, "\"modelUsage\":{\"")
      if (mu_idx > 0) {
        rest = substr(line, mu_idx + length("\"modelUsage\":{\""))
        mend = index(rest, "\"")
        if (mend > 0) model = substr(rest, 1, mend - 1)
      }
      cache_read    = extract(line, "cache_read_input_tokens") + 0
      cache_created = extract(line, "cache_creation_input_tokens") + 0
      wsearch = extract(line, "web_search_requests") + 0
      wfetch  = extract(line, "web_fetch_requests") + 0
      pd_idx    = index(line, "\"permission_denials\":[")
      n_denials = 0
      if (pd_idx > 0) {
        pd_rest = substr(line, pd_idx + length("\"permission_denials\":["))
        pd_end  = index(pd_rest, "]")
        pd_arr  = substr(pd_rest, 1, pd_end - 1)
        gsub(/ /, "", pd_arr)
        if (pd_arr != "") n_denials = split(pd_arr, _pd, ",")
      }
      summary = "[Session:"
      if (model != "")         summary = summary " model=" model
      if (session_cost > 0)    summary = summary " cost=$" sprintf("%.4f", session_cost)
      if (duration_ms != "")   summary = summary " duration=" sprintf("%.1f", (duration_ms+0)/1000) "s"
      if (num_turns != "")     summary = summary " turns=" num_turns
      if (input_tokens != "" || output_tokens != "") {
        summary = summary " tokens=" input_tokens "in/" output_tokens "out"
      }
      if (cache_read > 0 || cache_created > 0)
        summary = summary " cache=" cache_read "r/" cache_created "w"
      if (wsearch > 0 || wfetch > 0)
        summary = summary " web=" wsearch "s/" wfetch "f"
      if (n_denials > 0) summary = summary " denials=" n_denials
      summary = summary "]"
      print summary > "/dev/stderr"
      print summary >> log_file
      if (live_log != "") { printf "[%s] %s\n", get_time(), summary >> live_log; fflush(live_log) }

    } else if (etype == "rate_limit_event") {
      util = extract(line, "utilization")
      if (util != "") {
        pct = int((util + 0) * 100)
        if (pct > last_rate_limit_pct) {
          if (!at_line_start) { printf "\r%-12s\r\n", ""; fflush(); if (live_log != "" && !live_at_line_start) { printf "\n" >> live_log; fflush(live_log); live_at_line_start = 1 }; at_line_start = 1 }
          printf "  [Rate limit: %d%% of 7-day quota used]\n", pct > "/dev/stderr"
          if (live_log != "") { printf "  [%s] [Rate limit: %d%% of 7-day quota used]\n", get_time(), pct >> live_log; fflush(live_log) }
          last_rate_limit_pct = pct
        }
      }

    } else if (etype == "system") {
      subtype_val = extract(line, "subtype")
      if (subtype_val == "init") {
        model_s = extract(line, "model")
        if (model_s != "") {
          printf "[%s] model=%s\n", get_time(), model_s > "/dev/stderr"
          printf "[%s] model=%s\n", get_time(), model_s >> log_file
        }
        if (model_s != "" && live_log != "") { printf "[%s] model=%s\n", get_time(), model_s >> live_log; fflush(live_log) }
      }

    } else {
      now = get_epoch()
      if (spinner_start == 0) {
        spinner_start = now
        if (!at_line_start) printf "\n"
      }
      printf "\r%s %ds", substr(spinner, (spinner_idx % 4) + 1, 1), now - spinner_start
      fflush()
      at_line_start = 0
      spinner_idx++
    }
  }
  '
}

_self="${0##*/}"
if [ "$_self" = "stream_processor.sh" ]; then
  [ "$#" -lt 2 ] && { printf 'Usage: stream_processor.sh <log_file> <raw_log> [hooks_enabled] [live_log]\n' >&2; exit 1; }
  process_stream_json "$1" "$2" "${3:-false}" "${4:-}"
fi
