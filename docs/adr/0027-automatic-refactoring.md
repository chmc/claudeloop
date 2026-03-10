# 27. Automatic Refactoring After Phase Completion

**Date:** 2026-03-10
**Status:** Accepted

## Context

AI models frequently create large monolithic files during implementation phases. Later phases struggle to read and operate on these large files, degrading model performance. An opt-in automatic refactoring step after each phase would improve code structure for subsequent phases.

## Decision

Add `--refactor` flag that enables automatic refactoring after each completed phase:

- **Every phase, no threshold**: When enabled, runs after every completed phase. Claude decides what (if anything) needs restructuring.
- **Non-fatal**: Refactoring failure never blocks the pipeline. Rollback and continue.
- **Git rollback**: Record SHA before refactoring. On failure: `git reset --hard $sha && git clean -fd`.
- **Built-in prompt only**: Single hardcoded refactoring prompt, not customizable via plan.
- **Separate `verify_refactor`**: Cannot reuse `verify_phase` because it gates on `VERIFY_PHASES`, has different prompts, and log paths would collide. Uses extracted `check_verdict` helper.
- **"Nothing to refactor" early exit**: If SHA unchanged after Claude runs, skip verification.
- **Up to 3 attempts**: On refactoring or verification failure, rollback and retry.

Implementation:
- `lib/refactor.sh`: `build_refactor_prompt`, `verify_refactor`, `refactor_phase`, `run_refactor_if_needed`
- `lib/verify.sh`: Extracted `check_verdict` helper from `verify_phase`
- Integrated at two points in `evaluate_phase_result` (exit-0 and successful-session paths)
- Interrupt handler rolls back incomplete refactoring via `_PRE_REFACTOR_SHA`

## Consequences

**Positive:**
- Keeps code well-structured across phases, improving later phase performance
- Non-fatal design means refactoring issues never block progress
- Git rollback ensures clean state on failure
- Early exit when nothing to refactor saves API calls

**Negative:**
- Up to 4 API calls per phase when both `--verify` and `--refactor` are enabled
- Later phases may reference pre-refactored file paths (mitigated by Claude's ability to find renamed/split code)
- `git clean -fd` on rollback removes all untracked unignored files
