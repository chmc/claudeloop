#!/bin/sh

# stream_processor.sh - Parse claude --output-format=stream-json events.
# Can be sourced (defines process_stream_json) or run standalone as:
#   sh lib/stream_processor.sh <log_file> <raw_log>

# process_stream_json: parse stream-json from stdin
# Args: $1 - log_file path, $2 - raw_log path, $3 - hooks_enabled (true|false, default false)
#       $4 - live_log path, $5 - simple_mode (true|false, default false)
process_stream_json() {
  local log_file="$1"
  local raw_log="$2"
  local hooks_enabled="${3:-false}"
  local live_log="${4:-}"
  local simple_mode="${5:-false}"
  awk -v log_file="$log_file" -v raw_log="$raw_log" \
      -v trunc_len="${STREAM_TRUNCATE_LEN:-300}" \
      -v hooks_enabled="$hooks_enabled" \
      -v live_log="$live_log" \
      -v simple_mode="$simple_mode" '
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

  function print_task_summary() {
    visible = task_count - task_deleted
    msg = "[Tasks: " task_completed "/" visible " done]"
    if (current_active_form != "") msg = msg " \342\226\270 \"" current_active_form "\""
    if (hooks_enabled != "true") {
      printf "  %s%s%s\n", C_GREEN, msg, C_RESET > "/dev/stderr"
    }
    if (live_log != "") { printf "  [%s] %s\n", get_time(), msg >> live_log; fflush(live_log) }
  }

  function print_task_completed(id,    subj) {
    subj = (id in task_subjects) ? task_subjects[id] : "Task " id
    msg = "[Task completed] \342\234\223 \"" subj "\""
    if (hooks_enabled != "true") {
      printf "  %s%s%s\n", C_GREEN, msg, C_RESET > "/dev/stderr"
    }
    if (live_log != "") { printf "  [%s] %s\n", get_time(), msg >> live_log; fflush(live_log) }
  }

  function handle_task_event(tname, src,    tid, tst, tsubj, taf, i) {
    if (tname == "TaskCreate") {
      task_count++
      tsubj = extract(src, "subject")
      taf = extract(src, "activeForm")
      task_subjects[task_count] = tsubj
      task_active_forms[task_count] = taf
      task_statuses[task_count] = "pending"
      if (taf != "") current_active_form = taf
      print_task_summary()
    } else if (tname == "TaskUpdate") {
      tid = extract(src, "taskId") + 0
      tst = extract(src, "status")
      tsubj = extract(src, "subject")
      taf = extract(src, "activeForm")
      if (tsubj != "" && tid > 0) task_subjects[tid] = tsubj
      if (taf != "" && tid > 0) task_active_forms[tid] = taf
      if (tst != "" && tid > 0) {
        old_st = (tid in task_statuses) ? task_statuses[tid] : ""
        if (tst == "completed" && old_st != "completed") {
          task_completed++
          print_task_completed(tid)
        } else if (tst == "deleted") {
          if (old_st == "completed") task_completed--
          task_deleted++
        }
        task_statuses[tid] = tst
      }
      # Find last in_progress active form
      current_active_form = ""
      for (i = task_count; i >= 1; i--) {
        if ((i in task_statuses) && task_statuses[i] == "in_progress" && (i in task_active_forms) && task_active_forms[i] != "") {
          current_active_form = task_active_forms[i]
          break
        }
      }
      print_task_summary()
    }
  }

  function print_todo_summary() {
    if (todo_count == 0) {
      msg = "[Todos: empty]"
    } else {
      msg = "[Todos: " todo_completed "/" todo_count " done]"
    }
    if (todo_active_form != "") msg = msg " \342\226\270 \"" todo_active_form "\""
    if (hooks_enabled != "true") {
      printf "  %s%s%s\n", C_GREEN, msg, C_RESET > "/dev/stderr"
    }
    if (live_log != "") { printf "  [%s] %s\n", get_time(), msg >> live_log; fflush(live_log) }
  }

  function handle_todo_event(src,    _nt, _nd, af, pos, chunk, p, i, c, nxt) {
    _nt = split(src, _tmp, "\"content\":\"") - 1
    _nd = split(src, _tmp, "\"status\":\"completed\"") - 1
    todo_count = _nt
    todo_completed = _nd
    todo_active_form = ""
    pos = index(src, "\"status\":\"in_progress\"")
    if (pos > 0) {
      chunk = substr(src, pos + length("\"status\":\"in_progress\""))
      nxt = index(chunk, "\"status\":\"")
      if (nxt > 0) chunk = substr(chunk, 1, nxt - 1)
      p = index(chunk, "\"activeForm\":\"")
      if (p > 0) {
        chunk = substr(chunk, p + length("\"activeForm\":\""))
        af = ""
        for (i = 1; i <= length(chunk); i++) {
          c = substr(chunk, i, 1)
          if (c == "\"") break
          af = af c
        }
        todo_active_form = af
      }
    }
    print_todo_summary()
  }

  function clear_line() {
    if (!at_line_start) {
      if (spinner_start > 0) {
        printf "\r%-12s\r", ""
      } else {
        printf "\n"
      }
      fflush()
      if (live_log != "" && !live_at_line_start) {
        printf "\n" >> live_log
        fflush(live_log)
        live_at_line_start = 1
      }
      at_line_start = 1
    }
  }

  BEGIN {
    if (simple_mode != "true") {
      C_CYAN = "\033[0;36m"; C_RED = "\033[0;31m"
      C_YELLOW = "\033[1;33m"; C_GREEN = "\033[0;32m"; C_RESET = "\033[0m"
    } else {
      C_CYAN = ""; C_RED = ""; C_YELLOW = ""; C_GREEN = ""; C_RESET = ""
    }
    task_count = 0
    task_completed = 0
    task_deleted = 0
    current_active_form = ""
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
        clear_line()
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
          clear_line()
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
          if (name == "TaskCreate") { preview = trunc(extract(seg, "subject"), trunc_len) }
          else if (name == "TaskUpdate") {
            _tu_prev_id = extract(seg, "taskId")
            _tu_prev_st = extract(seg, "status")
            preview = "#" _tu_prev_id
            if (_tu_prev_st != "") preview = preview " \342\206\222 " _tu_prev_st
          } else if (name == "TodoWrite") {
            _n = split(seg, _tmp, "\"content\":\"") - 1
            preview = _n " items"
          } else if (name == "TaskStop") {
            preview = extract(seg, "task_id")
          } else {
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
          }
          if (hooks_enabled != "true") {
            if (preview != "") {
              printf "  %s[Tool: %s] %s%s\n", C_CYAN, name, preview, C_RESET > "/dev/stderr"
              if (live_log != "") printf "  [%s] [Tool: %s] %s\n", get_time(), name, preview >> live_log
            } else {
              printf "  %s[Tool: %s]%s\n", C_CYAN, name, C_RESET > "/dev/stderr"
              if (live_log != "") printf "  [%s] [Tool: %s]\n", get_time(), name >> live_log
            }
          }
          if (name == "TaskCreate" || name == "TaskUpdate") handle_task_event(name, seg)
          else if (name == "TodoWrite") handle_todo_event(seg)
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
        clear_line()
        printf "  %s[Warning: max_tokens \342\200\224 output was truncated]%s\n", C_YELLOW, C_RESET > "/dev/stderr"
        if (live_log != "") { printf "  [%s] [Warning: max_tokens \342\200\224 output was truncated]\n", get_time() >> live_log; fflush(live_log) }
      }

    } else if (etype == "tool_use") {
      clear_line()
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
      if (name == "TaskCreate") { preview = trunc(extract(line, "subject"), trunc_len) }
      else if (name == "TaskUpdate") {
        _tu_prev_id = extract(line, "taskId")
        _tu_prev_st = extract(line, "status")
        preview = "#" _tu_prev_id
        if (_tu_prev_st != "") preview = preview " \342\206\222 " _tu_prev_st
      } else if (name == "TodoWrite") {
        _n = split(line, _tmp, "\"content\":\"") - 1
        preview = _n " items"
      } else if (name == "TaskStop") {
        preview = extract(line, "task_id")
      } else {
        if      (cmd   != "")  preview = trunc(cmd,   trunc_len)
        else if (fp    != "")  preview = trunc(fp,    trunc_len)
        else if (pat   != "")  preview = trunc(pat,   trunc_len)
        else if (url   != "")  preview = trunc(url,   trunc_len)
        else if (query != "")  preview = trunc(query, trunc_len)
        else if (npath != "")  preview = trunc(npath, trunc_len)
        else if (stype != "")  preview = stype
        else                   preview = ""
      }
      if (hooks_enabled != "true") {
        if (preview != "") {
          printf "  %s[Tool: %s] %s%s\n", C_CYAN, name, preview, C_RESET > "/dev/stderr"
          if (live_log != "") { printf "  [%s] [Tool: %s] %s\n", get_time(), name, preview >> live_log; fflush(live_log) }
        } else {
          printf "  %s[Tool: %s]%s\n", C_CYAN, name, C_RESET > "/dev/stderr"
          if (live_log != "") { printf "  [%s] [Tool: %s]\n", get_time(), name >> live_log; fflush(live_log) }
        }
      }
      if (name == "TaskCreate" || name == "TaskUpdate") handle_task_event(name, line)
      else if (name == "TodoWrite") handle_todo_event(line)

    } else if (etype == "tool_result") {
      clear_line()
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
      printf "  %s[Tool result: %d chars] %s%s\n", C_CYAN, total, trunc(preview, 200), C_RESET > "/dev/stderr"
      if (live_log != "") { printf "  [%s] [Tool result: %d chars] %s\n", get_time(), total, trunc(preview, 200) >> live_log; fflush(live_log) }

    } else if (etype == "user") {
      tool_result = extract(line, "tool_use_result")
      if (tool_result != "") {
        clear_line()
        spinner_start = 0
        is_err = (index(line, "\"is_error\":true") > 0) ? " [error]" : ""
        _c = (is_err != "") ? C_RED : C_CYAN
        printf "  %s[Result%s: %d chars] %s%s\n", _c, is_err, length(tool_result), trunc(tool_result, 200), C_RESET > "/dev/stderr"
        if (live_log != "") { printf "  [%s] [Result%s: %d chars] %s\n", get_time(), is_err, length(tool_result), trunc(tool_result, 200) >> live_log; fflush(live_log) }
      }

    } else if (etype == "result") {
      clear_line()
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
          clear_line()
          printf "  %s[Rate limit: %d%% of 7-day quota used]%s\n", C_YELLOW, pct, C_RESET > "/dev/stderr"
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
  [ "$#" -lt 2 ] && { printf 'Usage: stream_processor.sh <log_file> <raw_log> [hooks_enabled] [live_log] [simple_mode]\n' >&2; exit 1; }
  process_stream_json "$1" "$2" "${3:-false}" "${4:-}" "${5:-false}"
fi
