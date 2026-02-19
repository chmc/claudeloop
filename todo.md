# Plan: Replace stream_processor.py with inline awk

## Context

The previous plan introduced `lib/stream_processor.py` (Python3) to parse Claude's
`--output-format=stream-json` events. The project goal is a pure POSIX sh tool with no
Python dependency. This plan replaces the Python script with an inline awk implementation
inside `lib/stream_processor.sh`, then removes the python3 dependency check.

---

## Changes

### 1. `lib/stream_processor.sh` — rewrite as a dual-mode POSIX sh + awk file

Add `#!/bin/sh` shebang. The file must work both when sourced (defines the function) and
when executed directly as `sh lib/stream_processor.sh <log> <raw>` (for tests that capture
stderr via `2>&1 >/dev/null`).

**`process_stream_json()` function** — replaces the `python3` call with inline awk:

```sh
process_stream_json() {
  local log_file="$1"
  local raw_log="$2"
  awk -v log_file="$log_file" -v raw_log="$raw_log" '
  function extract(s, key,    tag, i, c, val, esc) { ... }
  function trunc(s, max,    i, c) { ... }
  { ... event routing ... }
  '
}
```

**`extract(json, key)` awk helper** — finds `"key":value`, returns:
- string value (handling `\"` `\n` `\t` escapes) for `"key":"..."`
- numeric/boolean raw text for `"key":123`
- `""` for object (`{`) or array (`[`) — signals non-scalar

**`trunc(s, max)` awk helper** — replaces newlines with spaces, truncates to `max` chars + `...`

**Event routing:**

| Event type | Action |
|------------|--------|
| non-JSON line (first char ≠ `{`) | `print` to stdout + `print >> log_file` |
| `assistant` | `extract(line,"text")` → `printf "%s", text` stdout + `printf "%s", text >> log_file`; then `fflush()` for real-time display |
| `tool_use` | extract `name`; `command`/`file_path`/`pattern` per tool → `printf "  [Tool: N] preview\n"` to `/dev/stderr` |
| `tool_result` | `extract(line,"content")`: if non-empty → `length()`; if empty (array) → split on `"text":"` + sum string lengths → `printf "  [Tool result: N chars]\n"` to `/dev/stderr` |
| `result` | extract `cost_usd`, `duration_ms`, `num_turns`, `input_tokens`, `output_tokens` → format `[Session: ...]` to `/dev/stderr` + `print summary >> log_file` |
| `system`, `user`, other | skip silently |
| every line | `print line >> raw_log` |

**Duration calculation** — use `sprintf("%.1f", (duration_ms_str+0)/1000)` with parentheses.
Without them, awk precedence (`/` before `+`) would evaluate as `duration_ms_str + 0` (wrong).

**Cost** — `sprintf("%.4f", cost+0)` (POSIX awk, no gawk extensions).

**Standalone main block** — at the bottom of the file, after the function definition:
```sh
_self="${0##*/}"
if [ "$_self" = "stream_processor.sh" ]; then
  [ "$#" -ne 2 ] && { printf 'Usage: stream_processor.sh <log_file> <raw_log>\n' >&2; exit 1; }
  process_stream_json "$1" "$2"
fi
```
When sourced, `$0` is the caller's name — condition is false, nothing runs.
When run directly as `sh lib/stream_processor.sh`, condition is true — acts as standalone.

### 2. Delete `lib/stream_processor.py`

### 3. `claudeloop` lines ~316-319 — remove python3 check

```sh
# Remove these 3 lines from validate_environment():
if ! command -v python3 > /dev/null 2>&1; then
  print_error "python3 not found. Please install Python 3."
  exit 1
fi
```

### 4. `tests/test_stream_processor.sh` — update header and `run_processor` helper

**Change PROCESSOR variable and setup (lines 1-20):**
```bash
STREAM_PROCESSOR_LIB="${BATS_TEST_DIRNAME}/../lib/stream_processor.sh"

setup() {
  _log="$(mktemp)"
  _raw="$(mktemp)"
  . "$STREAM_PROCESSOR_LIB"   # makes process_stream_json available
}

run_processor() {
  echo "$1" | process_stream_json "$_log" "$_raw"
}
```

**Replace 7 `python3 '$PROCESSOR'` occurrences** (lines 52, 60, 79, 88, 112, 119, 144)
with `sh '$STREAM_PROCESSOR_LIB'` — calls the standalone main block, no chmod needed:
```bash
# Before:
run bash -c "echo '$event' | python3 '$PROCESSOR' '$_log' '$_raw' 2>&1 >/dev/null"
# After:
run bash -c "echo '$event' | sh '$STREAM_PROCESSOR_LIB' '$_log' '$_raw' 2>&1 >/dev/null"
```

All 15 test assertions remain unchanged.

---

## Critical files

| File | Change |
|------|--------|
| `lib/stream_processor.sh` | Add `#!/bin/sh`; rewrite `process_stream_json()` with inline awk; add standalone main block |
| `lib/stream_processor.py` | Delete |
| `claudeloop` (~line 316) | Remove 3-line python3 check |
| `tests/test_stream_processor.sh` | Update lines 1-20 (header/setup); update 7 `python3` occurrences to `sh '$STREAM_PROCESSOR_LIB'` |

---

## Verification

```sh
bats tests/test_stream_processor.sh
./tests/run_all_tests.sh
shellcheck -s sh lib/stream_processor.sh
./claudeloop --plan examples/PLAN.md.example --dry-run
```
