# 29. Refactor retry improvements

**Date:** 2026-03-11
**Status:** Accepted

## Context

The auto-refactoring system (`--refactor`) had several issues with its retry behavior:

1. **Wasted work between retries**: After every failed attempt (both Claude crashes and verification failures), `git reset --hard` discarded all changes. The next attempt started from scratch instead of building on previous work.
2. **Low retry count**: Max retries was hardcoded to 3, which was insufficient for complex refactoring tasks.
3. **Misleading status**: Failed refactors were marked as "completed", making them indistinguishable from successful ones.
4. **No resume persistence**: The attempt count wasn't persisted, so interrupting and resuming could exceed the intended max attempts.
5. **Error context extraction bug**: The refactor log was cleared *before* extracting error context for the retry prompt, so retries never received feedback about what went wrong.
6. **Narrow verify diff scope**: `verify_refactor` used `git diff HEAD~1`, which only showed the last commit. With accumulated commits across retries, the verifier missed issues in earlier commits.

## Decision

### Preserve work between retries

- **Verification failure**: Changes are already committed. The next attempt sees them and can fix what failed. After verify failure, `auto_commit_changes` catches any linter/test artifacts.
- **Crash (non-zero exit)**: May leave uncommitted partial work. `auto_commit_changes` preserves it before the next attempt.
- **Final exhaustion only**: `git reset --hard` to the original pre-refactor SHA happens only after all attempts are exhausted ("discard" point).

### Configurable max attempts (default: 20)

Complex refactoring often needs iterative refinement. The default of 20 attempts provides enough room for models to converge, and can be overridden via `--refactor-max-retries` or `REFACTOR_MAX_RETRIES`.

### New status values

| Value | Meaning |
|-------|---------|
| `in_progress N/M` | Attempt N of M running (M = REFACTOR_MAX_RETRIES) |
| `completed` | Refactoring succeeded and committed |
| `discarded` | Failed after M attempts, changes rolled back |

### Persist attempt count for resume

New `REFACTOR_ATTEMPTS` field in PROGRESS.md. On entry, `refactor_phase` reads this to determine starting attempt, preventing resume from exceeding the max.

### Preserve original rollback SHA on resume

On resume, `refactor_phase` checks if `REFACTOR_SHA` is already persisted. If so, it uses that (the original pre-refactor point). Only captures a fresh SHA when starting a new refactor.

### Fix error context extraction order

Extract error context from the previous log *before* clearing it. This ensures retry prompts contain feedback about what went wrong.

### Fix verify diff scope

Pass `pre_sha` to both `build_refactor_prompt` and `verify_refactor`. Use `git diff $pre_sha..HEAD` instead of `git diff HEAD~1` to show the full accumulated refactoring scope.

## Consequences

**Positive:**
- Retries are more effective — they build on previous work instead of starting over
- Resume respects the max attempt limit
- Status values clearly distinguish success from failure
- Error feedback makes retries increasingly targeted
- Verify checks the full scope of changes

**Negative:**
- More API calls possible per phase (up to 2×REFACTOR_MAX_RETRIES: refactor + verify each)
- Accumulated commits between retries may create a messier git history before final discard
- The `in_progress N/M` status format is slightly more complex to parse
