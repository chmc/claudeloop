# 22. Smoke test and GUI verification skill

**Date:** 2026-03-07
**Status:** Accepted

## Context

After code changes, there was no quick way to verify claudeloop works as a complete application. Unit tests (bats) cover individual library functions, and integration tests cover execution with a stub claude, but neither validates the real terminal UI — spinners, colors, scrollback, and cursor control.

The Bash tool captures raw bytes, not rendered terminal output. To verify what users actually see, we need GUI-level screenshots of the running application in Terminal.app.

## Decision

1. **`tests/smoke.sh`** — A standalone POSIX shell script that runs four checks using a stub claude binary (same pattern as `tests/test_integration.sh`): dry-run valid plan, dry-run invalid plan, 2-phase stub execution, and 3-phase dependency ordering. Reports PASS/FAIL per check and exits 0 only if all pass.

2. **`/verify` skill** (`.claude/skills/verify/SKILL.md`) — A decision matrix mapping changed files to the appropriate verification level, plus protocols for:
   - GUI screenshots via `osascript` + `screencapture -l <windowId>` for UI verification
   - Stub execution from the Bash tool for logic verification
   - Live execution with real Claude for end-to-end validation

3. **Fixture plans** in `tests/fixtures/smoke-plans/` — minimal plans for smoke and verification use.

## Consequences

**Positive:**
- Quick feedback loop: `./tests/smoke.sh` catches regressions in seconds
- GUI screenshots let Claude Code verify terminal rendering that raw output cannot capture
- Decision matrix prevents over- or under-verification

**Negative:**
- GUI screenshots require macOS Screen Recording permission (one-time setup)
- Screenshot-based verification is inherently macOS-specific
- Stub tests don't exercise real Claude API behavior
