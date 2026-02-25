# 2. Global Flat Variables for All State

**Date:** 2026-02-18
**Status:** Accepted

## Context

ClaudeLoop needs to track state for multiple phases (title, description, status, attempts, dependencies, timestamps). POSIX sh has no associative arrays or structs, so a structured state model must be built from primitive features.

## Decision

Use global shell variables with a naming convention: `PHASE_{FIELD}_{N}` where `N` is the phase number (with dots replaced by underscores). All state lives in the global scope — no config files, no subprocess state, no temporary files for inter-function communication.

Core variables per phase:
- `PHASE_TITLE_N`, `PHASE_DESCRIPTION_N`, `PHASE_DEPENDENCIES_N`
- `PHASE_STATUS_N` (pending | in_progress | completed | failed)
- `PHASE_ATTEMPTS_N`, `PHASE_START_TIME_N`, `PHASE_END_TIME_N`

Global metadata:
- `PHASE_COUNT` — total number of phases
- `PHASE_NUMBERS` — space-separated ordered list (e.g., "1 2 2.5 3")
- `LIVE_LOG` — path to live log file

Read/write pattern:
```sh
phase_var=$(phase_to_var "$phase_num")
value=$(eval "echo \"\$PHASE_STATUS_${phase_var}\"")
eval "PHASE_STATUS_${phase_var}='completed'"
```

## Consequences

**Positive:**
- No file I/O overhead for state access — everything is in memory
- Simple to serialize/deserialize for progress saving
- All functions can read/write state directly without parameter passing
- Works within POSIX sh constraints

**Negative:**
- Global mutable state makes reasoning about side effects harder
- Variable name construction via `eval` requires careful input validation (see ADR 0003)
- No encapsulation — any function can modify any state
- Debugging requires inspecting shell variable namespace
