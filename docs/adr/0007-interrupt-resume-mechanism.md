# 7. Graceful Interrupt with State Preservation

**Date:** 2026-02-18
**Status:** Accepted

## Context

Long-running multi-phase executions need a way to stop cleanly and resume later. A raw Ctrl+C would terminate the process without saving progress, losing track of which phases completed and forcing users to restart from the beginning.

## Decision

Implement a signal trap mechanism that catches INT and TERM signals, saves current state, and exits with code 130 (standard for SIGINT termination).

The flow:
1. `trap handle_interrupt INT TERM` is set at startup
2. On signal, `handle_interrupt` runs:
   - Marks the current in-progress phase back to pending (or failed if partially complete)
   - Calls `write_progress` to persist all phase statuses to the progress file
   - Calls `save_state` to flush any remaining state
   - Exits with code 130
3. On resume (`--continue`), `read_progress` restores state from the progress file
4. `find_next_phase` picks up from where execution left off

The progress file (`PROGRESS.md`) serves as the durable checkpoint, written after every phase status change.

## Consequences

**Positive:**
- Users can safely interrupt at any time without losing progress
- Resume is automatic — `--continue` picks up from last checkpoint
- Standard exit code (130) integrates with shell scripting conventions
- Progress file is human-readable markdown, easy to inspect or manually edit

**Negative:**
- Brief window between phase completion and progress write where a kill could lose one phase's status
- Signal handling in shell is inherently racy — nested signals can cause partial state writes
- The in-progress phase is reset to pending on interrupt, so its work must be redone even if nearly complete
