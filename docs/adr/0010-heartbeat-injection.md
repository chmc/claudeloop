# 10. Heartbeat Injection for Spinner Keepalive

**Date:** 2026-02-23
**Status:** Accepted

## Context

The terminal UI displays a spinner while Claude CLI processes each phase. During long idle periods (e.g., Claude thinking or waiting for API responses), no output is produced and the spinner appears frozen. Users couldn't tell whether the process was still running or had hung.

## Decision

Inject periodic heartbeat characters into the output stream to keep the spinner alive during idle periods. The `inject_heartbeats` function monitors the time since the last output line and emits a heartbeat if a configurable interval passes without activity.

Implementation details:
- Heartbeats are injected inline in the stream pipeline
- Uses timing-based EOF detection rather than polling, for compatibility with Bash 3.2 (macOS default)
- Heartbeat output is visually minimal — just enough to trigger the spinner update
- The mechanism is integrated into the stream processor pipeline

The Bash 3.2 compatibility requirement (macOS ships an old Bash due to GPLv3 licensing) drove the choice of timing-based detection over `read -t` with fractional timeouts, which isn't reliable across shell versions.

## Consequences

**Positive:**
- Users get visual feedback that execution is still active
- Works across macOS (Bash 3.2) and Linux (modern Bash/dash)
- Minimal overhead — only activates during idle periods
- Integrated into existing stream pipeline, no separate process needed

**Negative:**
- Adds complexity to the stream processing pipeline
- Timing-based approach is less precise than event-driven alternatives
- Heartbeat interval is a trade-off between responsiveness and noise
- Platform-specific workarounds (Bash 3.2) add conditional logic
