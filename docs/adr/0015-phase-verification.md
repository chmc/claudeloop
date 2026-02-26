# 15. Phase Verification

**Date:** 2026-02-26
**Status:** Accepted

## Context

ClaudeLoop marks a phase "completed" when the Claude CLI process exits successfully (exit code 0), with no independent check that the work was actually done correctly. A phase could exit cleanly without implementing anything, or with broken tests.

## Decision

Add an opt-in `--verify` flag that, after a phase completes, spawns a fresh read-only Claude instance to independently verify the work.

Key design choices:

- **Verify-only**: the verifier reads and tests, never writes. No git pollution or infinite regression.
- **Exit-code based**: claude exit 0 = pass, non-zero = fail. No magic-string grepping.
- **Anti-skip check**: run with `--verbose`, grep combined output for tool invocation evidence (e.g. `ToolUse`, `Bash`). Only checked when exit code is 0 to avoid misleading errors.
- **Single-tier retry**: verification failure = phase failure, entering the existing retry loop with the failure reason as context.
- **Process management**: verification runs backgrounded with `set -m` for killable process groups, same pattern as phase execution.
- **Timeout**: verification respects `MAX_PHASE_TIME`.
- **Always verify**: even doc-only phases. The prompt adapts — "run tests IF available, otherwise review diff."

Implementation: `lib/verify.sh` contains `verify_phase()`, called from `execute_phase()` on both success paths (clean exit 0 and successful-session detection).

## Consequences

**Positive:**
- Independent verification catches phases that exit cleanly but produce incorrect work
- Anti-skip check ensures the verifier actually runs commands rather than just claiming success
- Reuses existing retry infrastructure — no new failure handling needed
- Verification failure context is injected into retry prompts, giving the next attempt specific guidance

**Negative:**
- Doubles API calls per phase when enabled (one for execution, one for verification)
- Adds latency to each phase completion
- Anti-skip grep is heuristic — could produce false positives/negatives in edge cases
