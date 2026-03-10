# 28. Decoupled Refactor Lifecycle

**Date:** 2026-03-10
**Status:** Accepted

## Context

Auto-refactoring (introduced in ADR 0027) ran *before* marking a phase as completed. This caused several issues:

- If interrupted mid-refactor, the phase rolled back to "pending" and re-executed from scratch (wasting the successful phase work).
- Refactor state (`_PRE_REFACTOR_SHA`) was in-memory only — lost on SIGKILL.
- No check for uncommitted changes before refactoring (could corrupt git state).
- On restart, no way to resume interrupted refactors.

## Decision

Decouple refactoring from phase completion by treating it as a post-completion step with persistent state:

1. **Mark phase completed before refactoring.** `evaluate_phase_result()` now writes `completed` status + `REFACTOR_STATUS=pending` in a single `write_progress` call, then clears `CURRENT_PHASE` before calling `run_refactor_if_needed`. A crash before refactoring starts leaves the phase completed (no rework).

2. **Persist refactor state to PROGRESS.md.** Two new fields per phase:
   - `Refactor: pending|in_progress|completed` — refactor lifecycle state
   - `Refactor SHA: <sha>` — pre-refactor commit (only when `in_progress`)

3. **Resume on restart.** `resume_pending_refactors()` runs after progress initialization, before `main_loop`. It handles `in_progress` (rollback to SHA + retry) and `pending` (fresh refactor run). Gates on `REFACTOR_PHASES=true` — stale state is harmless without the flag.

4. **Dirty worktree check.** `refactor_phase()` checks `git status --porcelain` before starting. If dirty, marks `REFACTOR_STATUS=completed` (skip, don't retry forever).

5. **SHA validation.** Before rolling back on resume, validates the pre-refactor SHA with `git cat-file -t` (may be gc'd). If invalid, skips and marks completed.

6. **No normalization of REFACTOR_STATUS.** Unlike `STATUS` (where `in_progress` → `pending` on read), `REFACTOR_STATUS=in_progress` must survive reads because it signals "interrupted, needs rollback first."

7. **`_REFACTORING_PHASE` replaces `_PRE_REFACTOR_SHA`.** The interrupt handler no longer rolls back — it just logs a warning. State is already persisted in PROGRESS.md; `resume_pending_refactors` handles recovery.

8. **`detect_plan_changes` carries over refactor fields.** When phases are renumbered between runs, REFACTOR_STATUS and REFACTOR_SHA are preserved alongside other state.

## Consequences

**Positive:**
- Phase work is never lost due to refactor interruption
- Refactor state survives SIGKILL (persisted to disk)
- Interrupted refactors resume cleanly on restart
- Uncommitted changes are detected before refactoring

**Negative:**
- SIGKILL after successful refactor but before `write_progress` causes a rollback + retry on resume (wasteful but safe/idempotent)
- `--recover-progress` destroys refactor state (acceptable: explicit user action, refactor re-runs on next `--refactor`)
- Slightly more complex progress file format (two new optional fields per phase)
