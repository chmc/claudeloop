# 35. Recorder JSON Safety — Defense in Depth

**Date:** 2026-03-23
**Status:** Accepted

## Context

A replay.html from v0.22.1-beta.1 contained a JavaScript SyntaxError caused by `"tool_calls":,` — an empty value where a JSON array should be. The root cause was an AWK crash (likely line buffer overflow on a large raw.json) during `rec_extract_tool_calls`. When AWK crashes, its END block never executes, so the function's internal guard (`echo "[]"`) is bypassed. The command substitution captures empty string, which gets interpolated into `assemble_recorder_json`'s printf, producing invalid JSON. The single `<script>` block in the HTML template meant the entire replay page went blank with no diagnostics.

This class of bug affects any shell variable interpolated into JSON via printf `%s` — not just `tool_calls`.

## Decision

Implement four defense layers, each catching failures the previous layer might miss:

1. **Field-level defaults** — `[ -z "$var" ] && var="default"` after every scalar extraction (sed/cut). Catches empty strings from failed pattern matches.

2. **Shape-checking wrappers** — `safe_json_array()` validates output starts with `[` and ends with `]`; `safe_json_object()` validates `{`…`}`. Falls back to `[]`/`null`. Catches both empty AND truncated AWK output (e.g., `[{"name":"Bash"` from a mid-stream crash).

3. **Runtime JSON validation** — `validate_json()` uses node or python3 (best-effort, warn-only) to validate the assembled JSON file before HTML injection. Does NOT block replay generation on failure — the HTML safety net handles it.

4. **HTML template split** — The `<script>` block is split into two: Block 1 contains only `var DATA; DATA = ...;`. Block 2 contains all application code wrapped in `if (typeof DATA === 'undefined') { show error } else { app }`. A syntax error in Block 1 doesn't prevent Block 2 from executing, so the user sees a diagnostic message instead of a blank page.

All helpers (`safe_json_array`, `safe_json_object`, `validate_json`) live in `lib/recorder.sh`. The convention is documented in a comment block at the top of that file.

## Consequences

**Positive:**
- Invalid JSON can no longer reach the user as a blank page — at minimum, an error message is shown
- The `safe_json_*` wrappers are a mechanical pattern: wrap every extraction call, no judgment needed
- Round-trip JSON validation test (`python3 json.loads` on `assemble_recorder_json` output) catches regressions for any new field
- No new hard runtime dependencies — validation degrades gracefully when node/python3 are absent

**Negative:**
- `safe_json_array`'s prefix+suffix check (`'['*']'`) is a heuristic, not a full JSON validator — it catches empty/truncated output but not all forms of malformed JSON
- Runtime validation is non-deterministic: behavior differs based on whether node/python3 is installed
- The HTML template split adds ~10 lines and one level of indentation to all app code
- Future recorder changes must remember to wrap new fields with `safe_json_*` — enforced by the round-trip test and the comment block convention
