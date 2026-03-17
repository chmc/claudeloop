# 3. Eval-Based Dynamic Variable Access with Hardening

**Date:** 2026-02-24
**Status:** Accepted

## Context

The global state model (ADR 0002) requires constructing variable names dynamically from phase numbers. POSIX sh has no indirect variable references (`${!var}` is a Bash extension), making `eval` the only portable mechanism. However, `eval` is inherently dangerous — unsanitized input can lead to arbitrary code execution.

## Decision

Use `eval` for all dynamic variable access but harden every call site:

1. **`phase_to_var` converts dots to underscores** — relies on parser-level validation (regex in `parse_plan`) to guarantee input contains only digits and dots, making additional character stripping unnecessary
2. **All eval'd values are quoted** — `eval "PHASE_STATUS_${phase_var}='$value'"` prevents word splitting
3. **Validation at boundaries** — phase numbers are validated during plan parsing before they ever reach eval
4. **State serialization hardening** — progress file output escapes single quotes and strips control characters

The `phase_to_var` function is the single gateway for all variable name construction:
```sh
phase_to_var() { echo "$1" | tr '.' '_'; }
```

The implementation intentionally uses only `tr` (not `sed` with character stripping) because phase numbers are pre-validated through multiple layers: parser regex accepts only `[0-9.]+`, runtime iteration uses `$PHASE_NUMBERS` (set by parser), CLI args are validated, and progress file extraction uses matching patterns. Per-call sanitization would spawn ~370 extra subprocesses per run for zero practical benefit.

## Consequences

**Positive:**
- Portable across all POSIX shells
- Single sanitization function reduces surface area for injection bugs
- Hardening at both input (parsing) and output (serialization) boundaries

**Negative:**
- `eval` remains a code smell that requires vigilance on every use
- Performance overhead from spawning `sed` subprocesses for each variable access
- Requires discipline — every new eval site must go through `phase_to_var`
