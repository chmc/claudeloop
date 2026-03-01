# 17. Input sanitization for eval/awk contexts

**Date:** 2026-03-01
**Status:** Accepted

## Context

Several code paths accepted external input (plan files, CLI arguments, progress files) and passed it unsafely into shell evaluation or awk program strings:

1. **`phase_less_than` in `lib/parser.sh`** used `awk "BEGIN { exit ($1 < $2 ? 0 : 1) }"`, interpolating arguments directly into the awk program text. Since phase numbers originate from plan files, a crafted plan could inject arbitrary awk code including `system()` calls.

2. **`calculate_backoff` and `should_retry_phase` in `lib/retry.sh`** used `$((...))` arithmetic and `[ "$var" -lt "$var" ]` comparisons on values that could be non-numeric (empty strings, corrupted progress data, or invalid CLI arguments). Under `set -eu`, these crash with "integer expression expected" instead of failing gracefully.

3. **CLI argument parsing in `claudeloop`** accepted `--max-retries`, `--max-phase-time`, `--idle-timeout`, `--quota-retry-interval`, and `--phase` without validating that the values are numeric. Non-numeric values would propagate silently and crash later in arithmetic contexts.

4. **`--phase N` validation** did not check whether the specified phase number actually exists in the parsed plan, silently marking all phases as completed when given an out-of-range value.

## Decision

Three complementary sanitization patterns are applied at different layers:

1. **awk `-v` variable binding** — `phase_less_than` now uses `awk -v a="$1" -v b="$2" 'BEGIN { exit (a < b ? 0 : 1) }'`. Values are passed as awk variables, never interpolated into the program string. This eliminates the code injection vector entirely.

2. **POSIX `case` pattern guards before arithmetic** — All arithmetic operations on external input are preceded by `case "$var" in ''|*[!0-9]*) <fallback> ;; esac`. This is a POSIX-portable, zero-dependency way to reject non-numeric input before it reaches `$((...))` or `[ -lt ]`.

3. **CLI argument validation at parse time** — All numeric CLI flags are validated immediately after parsing with the same `case` pattern. Invalid values produce a clear error message and exit 1, preventing them from propagating into the system.

4. **`--phase` range validation** — After plan parsing, the specified phase number is verified to exist in `PHASE_NUMBERS`. If not found, an error is printed listing available phases.

## Consequences

**Positive:**
- Eliminates awk code injection via crafted plan files
- Prevents arithmetic crashes from non-numeric input at every layer
- Provides clear error messages for invalid CLI arguments instead of cryptic shell errors
- Catches `--phase` typos/mistakes early with helpful feedback
- All patterns are POSIX-portable (`case`, awk `-v`) with no external dependencies

**Negative:**
- `phase_less_than` with non-numeric input now silently treats values as 0 (awk's default for non-numeric strings in `-v`) rather than erroring. This is acceptable because phase numbers are validated by `parse_plan` before reaching comparison.
- Adds ~1 line of validation per numeric CLI flag (minimal code overhead)
