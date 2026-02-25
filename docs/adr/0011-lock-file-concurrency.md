# 11. Lock File with PID-Based Concurrency Control

**Date:** 2026-02-18
**Status:** Accepted

## Context

Running multiple ClaudeLoop instances in the same project directory would cause race conditions: both instances would read/write the same progress file, execute the same phases, and produce corrupt state. A concurrency control mechanism is needed to prevent simultaneous execution.

## Decision

Use a PID-based lock file (`.claudeloop/lock`) to ensure only one ClaudeLoop instance runs per project directory at a time.

The mechanism:
1. On startup, check if the lock file exists
2. If it exists, read the PID and check if that process is still running
3. If the process is alive, exit with an error message suggesting `--force`
4. If the process is dead (stale lock), clean up and proceed
5. Write the current PID to the lock file
6. On exit (normal or interrupt), remove the lock file

The `--force` flag allows taking over from a running instance: it kills the existing process (preserving its progress) and acquires the lock.

## Consequences

**Positive:**
- Prevents accidental concurrent execution and state corruption
- Stale lock detection handles crashes without manual cleanup
- `--force` provides an escape hatch for stuck processes
- Simple implementation — just a file containing a PID

**Negative:**
- PID-based detection has a TOCTOU race (process could die and PID be reused between check and action)
- Lock file is per-directory, not per-plan-file — can't run different plans in the same directory simultaneously
- `--force` kills the other process, which could lose in-flight work if the phase hasn't checkpointed yet
- No advisory locking (flock) — relies on PID file convention, which is less robust
