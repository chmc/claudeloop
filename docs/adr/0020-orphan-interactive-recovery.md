# 20. Wire orphan detection to intelligent recovery

**Date:** 2026-03-03
**Status:** Accepted

## Context

Two commits added complementary halves of orphan progress recovery:

- `40b8072` added `recover_progress_from_logs()` — the recovery engine — but only accessible via `--recover-progress` CLI flag (requires restart).
- `6892ee1` added `detect_orphan_logs()` — the detection mechanism — but its `[r]eset` option naively blanked all phases to pending instead of calling the recovery engine.

When `.claudeloop/ai-parsed-plan.md` exists, genuine recovery is possible by switching to that plan and reconstructing progress from execution logs. Without it, recovery is not feasible (AI parsing is non-deterministic, re-parsing won't reproduce the same plan).

## Decision

Wire detection to recovery with an ai-plan-required constraint:

1. `detect_orphan_logs()` sets `_ORPHAN_RECOVERY_ACTION` (a signal variable) instead of performing inline resets.
2. When `ai-parsed-plan.md` exists, the prompt offers `[r]ecover (recommended) / [c]ontinue / [a]bort`. Recovery sets `_ORPHAN_RECOVERY_ACTION=recover`.
3. When `ai-parsed-plan.md` does not exist, the prompt offers only `[c]ontinue / [a]bort` with a `--reset` hint. No recovery option.
4. `handle_orphan_recovery()` in the orchestrator checks the signal. On `recover`: switches `PLAN_FILE` to `ai-parsed-plan.md`, re-parses, backs up progress, and calls `recover_progress_from_logs()`.
5. YES_MODE and non-interactive mode default to `continue` (safe, no-op).

## Consequences

**Positive:**
- One-action recovery from plan mismatch corruption — no restart needed
- Recovery is only offered when it can actually work (ai-plan exists)
- Inline phase-reset loop removed — no more naive blanking

**Negative:**
- Recovery depends on `ai-parsed-plan.md` existing; manual-plan-only users must use `--reset` or `--recover-progress`
- `_ORPHAN_RECOVERY_ACTION` is another global signal variable (consistent with existing `_PLAN_HAD_CHANGES` pattern)
