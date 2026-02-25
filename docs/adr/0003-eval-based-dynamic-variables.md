# 3. Eval-Based Dynamic Variable Access with Hardening

**Date:** 2026-02-24
**Status:** Accepted

## Context

The global state model (ADR 0002) requires constructing variable names dynamically from phase numbers. POSIX sh has no indirect variable references (`${!var}` is a Bash extension), making `eval` the only portable mechanism. However, `eval` is inherently dangerous — unsanitized input can lead to arbitrary code execution.

## Decision

Use `eval` for all dynamic variable access but harden every call site:

1. **`phase_to_var` sanitizes input** — converts dots to underscores and strips any character that isn't alphanumeric or underscore
2. **All eval'd values are quoted** — `eval "PHASE_STATUS_${phase_var}='$value'"` prevents word splitting
3. **Validation at boundaries** — phase numbers are validated during plan parsing before they ever reach eval
4. **State serialization hardening** — progress file output escapes single quotes and strips control characters

The `phase_to_var` function is the single gateway for all variable name construction:
```sh
phase_to_var() {
    echo "$1" | sed 's/\./_/g' | sed 's/[^a-zA-Z0-9_]//g'
}
```

## Consequences

**Positive:**
- Portable across all POSIX shells
- Single sanitization function reduces surface area for injection bugs
- Hardening at both input (parsing) and output (serialization) boundaries

**Negative:**
- `eval` remains a code smell that requires vigilance on every use
- Performance overhead from spawning `sed` subprocesses for each variable access
- Requires discipline — every new eval site must go through `phase_to_var`
