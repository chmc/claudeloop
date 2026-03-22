# Replay Specification

Single source of truth for the replay report feature. All phases reference this document for data formats, JSON schema, and edge case handling.

## Overview

The replay report reconstructs execution data from existing `.claudeloop/` artifacts into a self-contained HTML report at `.claudeloop/replay.html`. No new recording infrastructure — all data already exists.

## Data Sources

| Field | Source file | Extraction method |
|-------|------------|-------------------|
| Phase titles, descriptions, deps | `PROGRESS.md` | Parse `### ✅ Phase N: Title` headers |
| Phase status, attempts, timestamps | `PROGRESS.md` | Parse `Status:`, `Attempts:`, `Started:`, `Completed:` lines |
| Session metrics (cost, tokens, model) | `logs/phase-N.log` | Parse `[Session: ...]` line |
| Execution timing, exit codes | `logs/phase-N.log` | Parse `=== EXECUTION START/END ===` markers |
| Previous attempt metrics | `logs/phase-N.attempt-M.log` | Same as above; M = 1-based attempt number |
| Tool usage counts | `logs/phase-N.raw.json` | Count `tool_use` events by tool name |
| Files touched | `logs/phase-N.raw.json` | Extract `file_path` from Edit/Write/Read tool_use inputs |
| Verification verdicts | `logs/phase-N.verify.log` | Grep for `VERIFICATION_PASSED` / `VERIFICATION_FAILED` |
| Run metadata (archived) | `metadata.txt` | Key=value pairs: plan_file, archived_at, phase_count, etc. |
| Refactor status | `PROGRESS.md` | Parse `Refactor:`, `Refactor SHA:`, `Refactor Attempts:` |
| No-changes signal | `signals/phase-N.md` | File existence check |
| Git commits | git history | `git log --oneline --grep="Phase N:"` |

## Log Formats

### Execution markers

```
=== EXECUTION START phase=N attempt=M time=2026-03-01T10:00:00 ===
=== PROMPT ===
{prompt text}
=== RESPONSE ===
{response text - may be truncated by log rotation}
=== EXECUTION END exit_code=E duration=Ns time=2026-03-01T10:01:00 ===
```

Fields in EXECUTION START: `phase` (decimal, e.g. `2.5`), `attempt` (integer), `time` (ISO 8601 without timezone).

Fields in EXECUTION END: `exit_code` (integer), `duration` (integer seconds, with `s` suffix), `time` (ISO 8601).

**Edge case:** Missing `EXECUTION END` indicates an interrupted run (SIGKILL, crash). Treat as incomplete — no duration or exit code available.

### Session line

Emitted by the AWK stream processor at session end:

```
[Session: model=claude-sonnet-4-20250514 cost=$0.0523 duration=45.2s turns=12 tokens=5000in/2000out cache=1200r/800w web=0s/0f denials=0]
```

All fields after `model=` are optional and order-stable:
- `model=` — model identifier string
- `cost=$` — USD with 4 decimal places
- `duration=` — seconds with 1 decimal, `s` suffix
- `turns=` — integer
- `tokens=` — `{in}in/{out}out` format
- `cache=` — `{read}r/{write}w` format (omitted if both zero)
- `web=` — `{search}s/{fetch}f` format (omitted if both zero)
- `denials=` — integer (omitted if zero)

### Attempt log naming

Current attempt always at: `logs/phase-N.log`

When a retry occurs, previous attempt is archived to: `logs/phase-N.attempt-M.log` where M is the 1-based attempt number.

Example for a phase with 3 attempts:
- `logs/phase-2.attempt-1.log` — first attempt (failed)
- `logs/phase-2.attempt-2.log` — second attempt (failed)
- `logs/phase-2.log` — third/current attempt (may be in-progress or completed)

Total attempts = count of `attempt-*.log` files + 1 (for current log).

### Raw JSON log

`logs/phase-N.raw.json` contains newline-delimited JSON events from the Claude CLI streaming output. Each line is a JSON object with at minimum a `type` field. Tool use events have:

```json
{"type":"tool_use","name":"Edit","input":{"file_path":"src/foo.ts",...}}
```

Tool names of interest: `Read`, `Edit`, `Write`, `Bash`, `Grep`, `Glob`.

## JSON Schema

The complete JSON blob embedded in `replay.html`:

```json
{
  "version": 1,
  "generated_at": "2026-03-01T10:30:00",
  "run": {
    "plan_file": "PLAN.md",
    "phase_count": 5,
    "completed": 3,
    "failed": 1,
    "pending": 1,
    "started_at": "2026-03-01 10:00:00",
    "ended_at": "2026-03-01 10:30:00",
    "total_cost_usd": 1.2345,
    "total_input_tokens": 50000,
    "total_output_tokens": 20000,
    "total_cache_read": 12000,
    "total_cache_write": 8000
  },
  "phases": [
    {
      "number": "1",
      "title": "Setup project structure",
      "description": "Create initial files and directories",
      "status": "completed",
      "dependencies": [],
      "started_at": "2026-03-01 10:00:00",
      "ended_at": "2026-03-01 10:05:00",
      "signal_no_changes": false,
      "refactor_status": "",
      "verification_verdict": "passed",
      "attempts": [
        {
          "number": 1,
          "started_at": "2026-03-01T10:00:00",
          "ended_at": "2026-03-01T10:05:00",
          "exit_code": 0,
          "duration_s": 300,
          "strategy": "standard",
          "fail_reason": null,
          "session": {
            "model": "claude-sonnet-4-20250514",
            "cost_usd": 0.0523,
            "duration_s": 45.2,
            "turns": 12,
            "input_tokens": 5000,
            "output_tokens": 2000,
            "cache_read": 1200,
            "cache_write": 800
          },
          "tools": [
            {"name": "Edit", "count": 5},
            {"name": "Read", "count": 8}
          ],
          "files": [
            {"path": "src/foo.ts", "ops": ["Read", "Edit"]},
            {"path": "src/bar.ts", "ops": ["Write"]}
          ],
          "tool_calls": [
            {"seq": 1, "name": "Read", "preview": "src/foo.ts"},
            {"seq": 2, "name": "Edit", "preview": "src/foo.ts"},
            {"seq": 3, "name": "Bash", "preview": "npm test"}
          ],
          "git_commits": [
            {"sha": "abc1234", "message": "Phase 1: setup project structure"}
          ]
        }
      ]
    }
  ]
}
```

### Field notes

- `phases[].number` — string, may be decimal (e.g. `"2.5"`)
- `phases[].attempts[]` — ordered by attempt number; last entry is the current/final attempt
- `phases[].attempts[].strategy` — one of: `standard`, `stripped`, `targeted`, `escalated`
- `phases[].attempts[].fail_reason` — null on success, string on failure (e.g. `"exit_code_1"`, `"no_session_line"`, `"verification_failed"`)
- `phases[].attempts[].session` — null if no `[Session:]` line found (e.g. crash before completion)
- `phases[].attempts[].tool_calls[]` — individual tool calls in execution order; `seq` is 1-based, `name` is the tool name, `preview` is a truncated input preview (file_path for Read/Edit/Write, command for Bash, pattern for Grep/Glob, etc.); capped at 200 entries; no error status in v1
- `phases[].verification_verdict` — `"passed"`, `"failed"`, or `null` (not verified)
- `phases[].signal_no_changes` — true if `signals/phase-N.md` exists
- Token fields default to 0 when absent

## Edge Cases

1. **Interrupted run (no EXECUTION END):** Attempt has `ended_at: null`, `exit_code: null`, `duration_s: null`. Display as "interrupted" in UI.
2. **No Session line:** `session: null`. Show "No session data" in UI. Common for crashes or permission denials.
3. **Decimal phase numbers:** Phase `2.5` maps to var `PHASE_TITLE_2_5`. Log files use literal decimal: `phase-2.5.log`.
4. **Missing raw.json:** `tools: []`, `files: []`. Tool/file data is best-effort.
5. **Log rotation:** Response section may be truncated to 500 lines. Prompt section is preserved.
6. **Archived runs:** `metadata.txt` provides summary; logs and PROGRESS.md are in the archive directory.
7. **Active run:** No `metadata.txt`. Compute summary from live PROGRESS.md globals.
8. **Single attempt:** No `.attempt-*.log` files exist. Only `phase-N.log`.
9. **Zero-cost session:** `cost=$0.0000` is valid (e.g. cached responses).
10. **Refactor phases:** May have `refactor_status` of `completed`, `failed`, or `in_progress`.
