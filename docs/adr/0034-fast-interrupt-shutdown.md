# 34. Fast Interrupt Shutdown

**Date:** 2026-03-20
**Status:** Accepted

## Context

When the user presses Ctrl+C during claudeloop execution, `handle_interrupt()` calls `write_progress()` which synchronously runs `generate_flight_recorder()`. The flight recorder parses all session logs and assembles HTML, taking 40+ seconds on large runs. This makes the interrupt feel unresponsive.

## Decision

Skip the synchronous flight recorder inside `write_progress()` during interrupt by passing `skip_recorder` as a third argument (backward-compatible — all existing callers pass 2 args). Then fork `generate_flight_recorder` as a detached background process with SIGHUP protection (`trap '' HUP` in subshell) and full fd isolation (`</dev/null >/dev/null 2>&1 &`).

The background process reads everything from disk (PROGRESS.md, session logs, HTML template), so it sees correct state after `write_progress` persists it. No spinner is needed — without the recorder, the save path is sub-millisecond.

## Consequences

**Positive:**
- Interrupt shutdown drops from 40+ seconds to < 200ms
- Flight recorder is still generated (in background), so replay.html stays up-to-date
- No changes to normal (non-interrupt) code path

**Negative:**
- If the background recorder is killed (SIGKILL, OOM), replay.html is stale until the next normal `write_progress` call — acceptable since it's regenerated every phase completion
- replay.html is a pure output artifact never read during execution, so a brief race with `--continue` is harmless
