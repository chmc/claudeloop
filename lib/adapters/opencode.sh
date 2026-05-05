#!/bin/sh
# OpenCode CLI adapter

_opencode_cli() {
  printf '%s' 'opencode'
}

_opencode_exec_args() {
  printf '%s' '--format json --stream'
}

_opencode_print_args() {
  printf '%s' '--format json'
}

_opencode_write_tool_pattern() {
  printf '%s' 'Edit|Write|NotebookEdit|Agent'
}

_opencode_raw_write_tool_pattern() {
  printf '%s' 'edit|write|file\.edit|file\.write|apply_patch'
}

_opencode_verdict_pass_keyword() {
  printf '%s' 'VERIFICATION_PASSED'
}

_opencode_verdict_fail_keyword() {
  printf '%s' 'VERIFICATION_FAILED'
}

_opencode_permission_protocol() {
  printf '%s' 'http'
}

# Build a stream message for OpenCode stdin (plain text, no JSON wrapper needed)
# OpenCode accepts prompts directly on stdin without JSON encoding
_opencode_build_stream_message() {
  printf '%s' "$1"
}

# Normalize OpenCode JSON events to Claude stream-json format
# Reads NDJSON from stdin, emits normalized events to stdout
# Malformed JSON lines go to stderr with warning
_opencode_normalize_events() {
  awk '
  # extract(s, key) - return scalar value for "key":value in s
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

  # json_escape(s) - escape string for JSON output
  function json_escape(s,    out, i, c) {
    out = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c == "\\") out = out "\\\\"
      else if (c == "\"") out = out "\\\""
      else if (c == "\n") out = out "\\n"
      else if (c == "\t") out = out "\\t"
      else if (c == "\r") out = out "\\r"
      else out = out c
    }
    return out
  }

  BEGIN {
    tool_id_counter = 0
  }

  {
    line = $0

    # Validate JSON: must start with {
    if (substr(line, 1, 1) != "{") {
      printf "opencode_normalizer: malformed input (not JSON): %s\n", substr(line, 1, 80) > "/dev/stderr"
      next
    }

    # Extract event type
    etype = extract(line, "type")
    if (etype == "") {
      printf "opencode_normalizer: malformed JSON (no type): %s\n", substr(line, 1, 80) > "/dev/stderr"
      next
    }

    # Handle session.created -> system init
    if (etype == "session.created") {
      model = extract(line, "model")
      if (model == "") model = "opencode"
      printf "{\"type\":\"system\",\"subtype\":\"init\",\"model\":\"%s\"}\n", model
      next
    }

    # Handle session.idle -> result
    if (etype == "session.idle") {
      printf "{\"type\":\"result\"}\n"
      next
    }

    # Handle file.edited -> tool_use (Edit)
    if (etype == "file.edited") {
      tool_id_counter++
      file_path = extract(line, "path")
      if (file_path == "") file_path = extract(line, "file")
      printf "{\"type\":\"tool_use\",\"id\":\"edit_%d\",\"name\":\"Edit\",\"file_path\":\"%s\"}\n", tool_id_counter, json_escape(file_path)
      next
    }

    # Handle message.part.updated
    if (etype == "message.part.updated") {
      # Check if this is a tool event by looking for callID
      call_id = extract(line, "callID")
      if (call_id == "") call_id = extract(line, "call_id")
      if (call_id == "") call_id = extract(line, "toolCallId")

      if (call_id != "") {
        # Tool event - check state
        state = extract(line, "state")
        if (state == "") state = extract(line, "status")

        # Get tool name
        tool_name = extract(line, "name")
        if (tool_name == "") tool_name = extract(line, "toolName")
        if (tool_name == "") tool_name = extract(line, "tool")
        if (tool_name == "") tool_name = "Unknown"

        # Emit tool_use only once per callID
        if (!(call_id in tool_emitted)) {
          tool_emitted[call_id] = 1
          tool_names[call_id] = tool_name
          printf "{\"type\":\"tool_use\",\"id\":\"%s\",\"name\":\"%s\"}\n", call_id, json_escape(tool_name)
        }

        # Emit tool_result on completed or error
        if (state == "completed" || state == "error" || state == "done" || state == "failed") {
          if (!(call_id in tool_result_emitted)) {
            tool_result_emitted[call_id] = 1
            is_error = (state == "error" || state == "failed") ? "true" : "false"
            content = extract(line, "output")
            if (content == "") content = extract(line, "result")
            if (content == "") content = extract(line, "content")
            printf "{\"type\":\"tool_result\",\"tool_use_id\":\"%s\",\"is_error\":%s,\"content\":\"%s\"}\n", call_id, is_error, json_escape(content)
          }
        }
        next
      }

      # Text content event (no callID) -> assistant
      text = extract(line, "text")
      if (text == "") text = extract(line, "content")
      if (text != "") {
        printf "{\"type\":\"assistant\",\"text\":\"%s\"}\n", json_escape(text)
      }
      next
    }

    # Pass through unknown events as-is (allows extension)
    print line
  }
  '
}
