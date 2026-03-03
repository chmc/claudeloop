# 19. Orphan log integrity check

**Date:** 2026-03-03
**Status:** Accepted

## Context

When a user runs with `--ai-parse` (producing e.g. 11 phases) and then re-runs without it (original 6-phase plan), a previous bug silently overwrote PROGRESS.md with 6 "completed" phases. The fix in `40b8072` prevents future corruption but cannot detect already-corrupted state. The `.claudeloop/logs/` directory retains phase-7 through phase-11 log files — orphan evidence of the mismatch.

Alternatives considered and rejected:
- **Plan source tracking** (header in PROGRESS.md): The buggy version already overwrote the header.
- **Plan content hash**: Same problem — the buggy run wrote everything for the new plan.
- **`recover_progress_from_logs` as interactive option**: Dangerous — logs are from the ai-parsed plan with narrower phases; recovery would incorrectly mark broad phases as "completed".

## Decision

Detect orphan log files in `.claudeloop/logs/` — log files for phase numbers not present in the current plan — as a retroactive corruption signal.

Implementation:
- `detect_orphan_logs()` in `lib/progress.sh` scans `phase-N.log` files, skipping auxiliary files (`.attempt-*.log`, `.verify.log`, `.raw.json`, `.formatted.log`).
- Only runs when `_PLAN_HAD_CHANGES` is false (set by `detect_plan_changes()`), avoiding false positives after legitimate plan changes.
- Interactive prompt offers: **reset** (clear all statuses to pending), **continue**, or **abort**.
- `YES_MODE` continues automatically; non-interactive mode warns but continues.

## Consequences

**Positive:**
- Catches corrupted progress that no other mechanism can detect retroactively.
- Minimal false positive risk via the `_PLAN_HAD_CHANGES` guard.
- Non-destructive by default — user chooses the action.

**Negative:**
- Adds one more check to the startup path (negligible cost — a single directory scan).
- `_ORPHAN_FORCE_TTY` test seam required for interactive testing in bats.
