# 15. Phase Verification

**Date:** 2026-02-26
**Status:** Accepted

## Context

ClaudeLoop marks a phase "completed" when the Claude CLI process exits successfully (exit code 0), with no independent check that the work was actually done correctly. A phase could exit cleanly without implementing anything, or with broken tests.

## Decision

Add an opt-in `--verify` flag that, after a phase completes, spawns a fresh read-only Claude instance to independently verify the work.

Key design choices:

- **Verify-only**: the verifier reads and tests, never writes. No git pollution or infinite regression.
- **Verdict-based**: the verifier must output `VERIFICATION_PASSED` or `VERIFICATION_FAILED` as its final word. `FAILED` takes priority if both appear. No verdict = failure (safe default for cut-off responses).
- **JSON-aware anti-skip check**: grep raw stream-json log for `"type":"tool_use"` events. Replaces the previous loose keyword grep (`Bash`, `Read`, etc.) which matched thinking text and error messages.
- **Stream processor integration**: verification output is piped through `process_stream_json` (same as phase execution), making tool calls and results visible in the terminal UI and `--monitor` live log.
- **Exit code guard**: empty or non-numeric exit codes (from killed subshells) default to `1` instead of causing `[: : integer expression expected` errors.
- **Single-tier retry**: verification failure = phase failure, entering the existing retry loop with the failure reason as context.
- **Process management**: verification runs backgrounded with `set -m` for killable process groups, same pattern as phase execution.
- **Timeout**: verification respects `MAX_PHASE_TIME`.
- **Always verify**: even doc-only phases. The prompt adapts — "run tests IF available, otherwise review diff."

Implementation: `lib/verify.sh` contains `verify_phase()`, called from `execute_phase()` on both success paths (clean exit 0 and successful-session detection).

## Consequences

**Positive:**
- Independent verification catches phases that exit cleanly but produce incorrect work
- Verdict keywords ensure the verifier explicitly states pass/fail rather than silently exiting
- JSON-aware anti-skip check ensures the verifier actually runs tool calls rather than just claiming success
- Verification output is now visible in the UI during execution (previously silent)
- Reuses existing retry infrastructure — no new failure handling needed
- Verification failure context is injected into retry prompts, giving the next attempt specific guidance

**Negative:**
- Doubles API calls per phase when enabled (one for execution, one for verification)
- Adds latency to each phase completion
- Verdict keywords are vanishingly unlikely to appear in tool output but theoretically possible (acceptable false positive risk)
