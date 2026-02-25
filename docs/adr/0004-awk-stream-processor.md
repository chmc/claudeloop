# 4. AWK Stream Processor Replacing Python

**Date:** 2026-02-19
**Status:** Accepted

## Context

The original stream processor was a Python script (`stream_processor.py`) that parsed Claude CLI output and formatted it for terminal display. This added a Python runtime dependency, which conflicted with the goal of minimal dependencies after the POSIX sh migration (ADR 0001).

## Decision

Replace the Python stream processor with inline AWK. AWK is available on all POSIX systems and handles line-by-line text processing well. The stream processor:

- Parses Claude CLI JSON output events
- Extracts result data, cost information, and session metadata
- Adds timestamps to output lines
- Colorizes stderr output with ANSI codes
- Detects and summarizes Claude Code task lists
- Injects heartbeats to keep the spinner alive during idle periods

Later enhancements added `--monitor` colorization via a separate AWK pipe.

## Consequences

**Positive:**
- Zero external dependencies — AWK is universally available
- Consistent with POSIX sh approach (ADR 0001)
- Lower startup overhead than Python
- Single process pipeline instead of inter-process coordination

**Negative:**
- AWK is less expressive than Python for complex parsing logic
- JSON parsing in AWK is fragile (regex-based rather than proper parsing)
- Harder to test in isolation compared to a standalone Python script
- Complex AWK programs embedded in shell scripts reduce readability
