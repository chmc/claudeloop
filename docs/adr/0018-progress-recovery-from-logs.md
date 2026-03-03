# 18. Progress Recovery from Logs

**Date:** 2026-03-03
**Status:** Accepted

## Context

When claudeloop restarts with a different plan file than the one PROGRESS.md was tracking, all phases can be incorrectly marked "completed" due to phase-number collision in `init_progress` / `detect_plan_changes`. The old progress is permanently overwritten. Users need a way to recover from this corruption.

The root cause is that `init_progress` loads status by phase number from PROGRESS.md before `detect_plan_changes` patches by title. When phase numbers collide but titles differ, stale "completed" statuses leak through.

## Decision

Three changes address this:

1. **Fix the collision bug:** `detect_plan_changes` now explicitly resets PHASE_STATUS/ATTEMPTS/START_TIME/END_TIME to defaults for unmatched (added) phases, clearing any stale state loaded by `init_progress`.

2. **Add safety guards:** When changes are detected, PROGRESS.md is backed up to `.bak`. When >50% of old phases are removed (and old count > 4), a drastic-change warning prompts confirmation (aborts in non-interactive mode).

3. **Add `--recover-progress` flag:** A new `recover_progress_from_logs()` function reconstructs PROGRESS.md from `.claudeloop/logs/` ground truth (execution headers/footers, verify logs, attempt archives). This serves as a recovery mechanism when progress has already been corrupted.

Log-based status determination:
- No log file → pending
- Log exists but no EXECUTION END → pending (interrupted)
- exit_code=0 (or has_successful_session): verify.log has VERIFICATION_PASSED → completed; verify.log exists without PASSED → failed; no verify.log → completed
- exit_code!=0 and no successful session → failed

## Consequences

**Positive:**
- The collision bug is fixed with a minimal 4-line change
- Backup + drastic-change guard prevent silent data loss
- `--recover-progress` provides a recovery path from any progress corruption
- Recovery is conservative: attempt counts may be slightly higher, failed phases are retried

**Negative:**
- Renamed phases ("Setup DB" → "DB Setup") are treated as new and reset — safer than falsely inheriting status
- Recovery cannot distinguish stale verify.log from current in edge cases — defaults to conservative (failed → retry)
- The root architectural issue (init_progress loading by number before detect_plan_changes patches by title) remains; a future refactor could make detect_plan_changes the sole state restoration path
