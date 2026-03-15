# 31. No-changes signal file for verification-only phases

**Date:** 2026-03-15
**Status:** Accepted

## Context

When a phase's work is already done (verification-only, already implemented), Claude reviews/tests everything and exits 0 — but claudeloop rejects it because `has_write_actions()` finds no Edit/Write/Agent tool calls. This causes endless retries at ~$1-2 each, and the retry hint ("you MUST use Edit or Write") pressures Claude to make unnecessary edits.

## Decision

Two-layer approach:

1. **Prompt instruction**: Tell Claude to write a summary to `.claudeloop/signals/phase-{N}.md` when no code changes are needed. Added to `build_default_prompt()`.

2. **Detection in `evaluate_phase_result()`**: When `has_write_actions()` fails, check for the signal file AND a successful session (`has_successful_session`). Both conditions required to prevent trivial gaming. When present, skip the failure block and treat as intentional no-change completion — also skip adaptive verification since the signal file IS the verification report.

Implementation details:
- `has_signal_file()` added to `lib/retry.sh` — simple file existence check
- Signal directory created alongside log directory in `execute_phase()`
- Stale signal files removed before each pipeline run
- Retry hints unchanged — on retry, we still push for real implementation

## Consequences

**Positive:**
- Eliminates wasteful retry loops for verification-only phases
- Saves ~$1-2 per unnecessary retry attempt
- Claude is no longer pressured to make fake edits
- Signal file serves as documentation of why no changes were needed

**Negative:**
- Adds a new file-based signaling mechanism (more state to manage)
- Requires both signal file + successful session — false negatives possible if session detection fails
