# Plan: Phase B — Richer stream-json extraction

## Context

Phase A+ made tool calls and results visible. Phase B adds five remaining gaps:

1. **More tool previews** — WebFetch/WebSearch/Task/NotebookEdit show no preview today; they fall
   through to `[Tool: WebFetch]` with no URL/query.
2. **Deduplication via tool ID** — With `--include-partial-messages`, each partial assistant message
   re-emits all accumulated tool_use blocks. A two-tool turn currently shows the first tool twice
   (once per partial). IDs let us skip already-shown tool calls and also surface the second tool.
3. **`stop_reason: max_tokens` warning** — When the model is cut off, `"stop_reason":"max_tokens"`
   appears in the assistant event but is silently ignored. Users need to know output was truncated.
4. **Model in session summary** — The `result` event carries `"model":"claude-sonnet-4-6"` which
   is currently ignored.
5. **`system` init event** — The first stream event is `{"type":"system","subtype":"init",...}`.
   It carries the model name and tools list. Showing it gives users an early "session started"
   confirmation with context.

---

## Changes to `lib/stream_processor.sh`

### 1. More tool previews

The new field extraction (inside the iteration loop in §2 for the assistant-nested handler;
also applied to the flat dead-code `tool_use` handler at ~line 157 for consistency):

```awk
# Note: use `seg` in the loop (assistant handler) or `line` in the flat handler
cmd = ""; fp = ""; pat = ""; url = ""; query = ""; npath = ""; stype = ""
if      (name == "Bash")                                       cmd   = extract(seg, "command")
else if (name == "Read" || name == "Write" || name == "Edit")  fp    = extract(seg, "file_path")
else if (name == "Glob" || name == "Grep")                     pat   = extract(seg, "pattern")
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
```

`desc` fallback is unchanged — fires for any tool with only a `description` argument.

### 2. Iteration + ID deduplication (replace single-extract with split loop)

**Why**: (a) `extract(line, "id")` finds the message-level `"id":"msg_xxx"` BEFORE the tool-use
`"id":"toolu_xxx"` — wrong key. (b) Single-extraction misses second/third tools in the same event.

Replace the entire `else if (index(line, "\"type\":\"tool_use\"") > 0)` block with a loop:

```awk
} else if (index(line, "\"type\":\"tool_use\"") > 0) {
  n_tools = split(line, tool_segs, "\"type\":\"tool_use\"")
  for (ti = 2; ti <= n_tools; ti++) {
    seg = tool_segs[ti]
    tool_id = extract(seg, "id")          # segment starts after the delimiter so
    # "id" here is the tool-use id (toolu_…), not the outer message id (msg_…)
    if (tool_id != "" && (tool_id in shown_tools)) continue
    if (tool_id != "") shown_tools[tool_id] = 1
    if (!at_line_start) { printf "\r%-12s\r\n", ""; fflush(); at_line_start = 1 }
    spinner_start = 0
    name = extract(seg, "name")
    cmd = ""; fp = ""; pat = ""; url = ""; query = ""; npath = ""; stype = ""
    if      (name == "Bash")                                       cmd   = extract(seg, "command")
    else if (name == "Read" || name == "Write" || name == "Edit")   fp    = extract(seg, "file_path")
    else if (name == "Glob" || name == "Grep")                      pat   = extract(seg, "pattern")
    else if (name == "WebFetch")                                     url   = extract(seg, "url")
    else if (name == "WebSearch")                                    query = extract(seg, "query")
    else if (name == "NotebookEdit")                                 npath = extract(seg, "notebook_path")
    else if (name == "Task")                                         stype = extract(seg, "subagent_type")
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
      if (preview != "") printf "  [Tool: %s] %s\n", name, preview > "/dev/stderr"
      else               printf "  [Tool: %s]\n",    name         > "/dev/stderr"
    }
  }
}
```

The split on `"type":"tool_use"` puts message-level fields (including the outer `msg_xxx` ID) in
`segs[1]`, so `extract(segs[2], "id")` only sees tool-use-level fields. Each `segs[ti]`
(ti ≥ 2) contains the fields of one tool_use block.

Handles: (a) partial message re-emission of same tool → same `toolu_xxx` ID → `continue`,
(b) two different tool calls in one event → different IDs → both shown.

### 3. `stop_reason: max_tokens` warning (assistant handler)

After the `if text / else if tool_use / else spinner` chain, add an independent check:

```awk
stop = extract(line, "stop_reason")
if (stop == "max_tokens") {
  if (!at_line_start) { printf "\r%-12s\r\n", ""; fflush(); at_line_start = 1 }
  printf "  [Warning: max_tokens \342\200\224 output was truncated]\n" > "/dev/stderr"
}
```

Placed after the chain so it fires regardless of whether the message had text, tool_use, or
neither.

### 4. Model in session summary (`result` handler, ~line 213)

```awk
model = extract(line, "model")
summary = "[Session:"
if (model != "")      summary = summary " model=" model
if (cost != "")       summary = summary " cost=$" sprintf("%.4f", cost+0)
...
```

### 5. `system` init event handler (new else-if before final `else`)

```awk
} else if (etype == "system") {
  sub = extract(line, "subtype")
  if (sub == "init") {
    model_s = extract(line, "model")
    if (model_s != "") printf "[%s] model=%s\n", get_time(), model_s > "/dev/stderr"
  }
```

**Note**: the exact system event shape is inferred from the Anthropic stream format. If `model` or
`subtype` field names differ in real output, the handler silently does nothing (safe fallback).
The test event used will be `{"type":"system","subtype":"init","model":"claude-sonnet-4-6"}`.
If real output doesn't match, the system handler test will reveal it and we adjust.

---

## TDD workflow (mandatory per CLAUDE.md)

Write 12 tests first, verify `not ok`, then implement. Total: 43 + 12 = 55.

```
# More tool previews (§1)
assistant event with WebFetch: url shown in preview
assistant event with WebSearch: query shown in preview
assistant event with Task: subagent_type shown in preview
assistant event with NotebookEdit: notebook_path shown in preview

# Iteration + ID deduplication (§2)
assistant event with two tool_use blocks: both shown
assistant event with tool_use: same toolu_ id shown only once across two events

# stop_reason (§3)
assistant event with stop_reason max_tokens: warning shown
assistant event with stop_reason end_turn: no warning

# model in session summary (§4)
result event with model: model shown in summary

# system init event (§5)
system init event with model: model shown to stderr
system init event with non-init subtype: no output
system init event without model field: no output
```

---

## Critical files

- `lib/stream_processor.sh`:
  - assistant handler tool_use branch ~line 117 (extend fields + ID dedup)
  - assistant handler after if/else chain ~line 147 (add stop_reason check)
  - flat `tool_use` handler ~line 157 (extend fields for consistency)
  - `result` handler ~line 213 (add model)
  - new `system` handler before final `else` ~line 240
- `tests/test_stream_processor.sh`: append 12 new tests

---

## Verification

```sh
bats tests/test_stream_processor.sh   # 55 tests pass
./tests/run_all_tests.sh              # no regressions
shellcheck -s sh lib/stream_processor.sh
```

Real test: run `./claudeloop --plan examples/PLAN.md.example` and confirm:
- WebFetch/WebSearch/Task calls show URL/query/subagent_type
- Same tool_use ID does not appear twice in output
- Session summary shows model name
- System init line appears at the top of execution output
