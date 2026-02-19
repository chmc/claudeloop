#!/bin/sh

# stream_processor.sh - Parse claude --output-format=stream-json events.
# Can be sourced (defines process_stream_json) or run standalone as:
#   sh lib/stream_processor.sh <log_file> <raw_log>

# process_stream_json: parse stream-json from stdin
# Args: $1 - log_file path, $2 - raw_log path
process_stream_json() {
  local log_file="$1"
  local raw_log="$2"
  awk -v log_file="$log_file" -v raw_log="$raw_log" '
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

  BEGIN { at_line_start = 1; silent_dot_printed = 0 }

  {
    line = $0
    print line >> raw_log

    if (substr(line, 1, 1) != "{") {
      print line
      print line >> log_file
      next
    }

    etype = extract(line, "type")

    if (etype == "assistant") {
      text = extract(line, "text")
      if (text != "") {
        printf "%s", text
        printf "%s", text >> log_file
        fflush()
        at_line_start = (substr(text, length(text), 1) == "\n")
        silent_dot_printed = 0
      } else {
        if (!silent_dot_printed) {
          printf "."
          fflush()
          at_line_start = 0
          silent_dot_printed = 1
        }
      }

    } else if (etype == "tool_use") {
      if (!at_line_start) {
        printf "\n"
        fflush()
        at_line_start = 1
      }
      name = extract(line, "name")
      preview = ""
      if (name == "Bash") preview = extract(line, "command")
      else if (name == "Read" || name == "Write" || name == "Edit") preview = extract(line, "file_path")
      else if (name == "Glob" || name == "Grep") preview = extract(line, "pattern")
      if (preview != "") {
        printf "  [Tool: %s] %s\n", name, trunc(preview, 80) > "/dev/stderr"
      } else {
        printf "  [Tool: %s]\n", name > "/dev/stderr"
      }
      silent_dot_printed = 0

    } else if (etype == "tool_result") {
      content = extract(line, "content")
      if (content != "") {
        total = length(content)
      } else {
        total = 0
        n = split(line, parts, "\"text\":\"")
        for (j = 2; j <= n; j++) {
          k = 1
          while (k <= length(parts[j])) {
            c = substr(parts[j], k, 1)
            if (c == "\\") { k += 2; continue }
            if (c == "\"") break
            total++
            k++
          }
        }
      }
      printf "  [Tool result: %d chars]\n", total > "/dev/stderr"
      silent_dot_printed = 0

    } else if (etype == "result") {
      cost = extract(line, "cost_usd")
      duration_ms = extract(line, "duration_ms")
      num_turns = extract(line, "num_turns")
      input_tokens = extract(line, "input_tokens")
      output_tokens = extract(line, "output_tokens")
      summary = "[Session:"
      if (cost != "") summary = summary " cost=$" sprintf("%.4f", cost+0)
      if (duration_ms != "") summary = summary " duration=" sprintf("%.1f", (duration_ms+0)/1000) "s"
      if (num_turns != "") summary = summary " turns=" num_turns
      if (input_tokens != "" || output_tokens != "") {
        summary = summary " tokens=" input_tokens "in/" output_tokens "out"
      }
      summary = summary "]"
      print summary > "/dev/stderr"
      print summary >> log_file
      silent_dot_printed = 0

    } else {
      if (!silent_dot_printed) {
        printf "."
        fflush()
        at_line_start = 0
        silent_dot_printed = 1
      }
    }
  }
  '
}

_self="${0##*/}"
if [ "$_self" = "stream_processor.sh" ]; then
  [ "$#" -ne 2 ] && { printf 'Usage: stream_processor.sh <log_file> <raw_log>\n' >&2; exit 1; }
  process_stream_json "$1" "$2"
fi
