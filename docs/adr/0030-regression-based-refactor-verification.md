# 30. Regression-based refactor verification

**Date:** 2026-03-12
**Status:** Accepted

## Context

Two bugs caused good refactoring work to be rolled back unnecessarily:

1. **Raw log scope leak:** The raw JSON log (`phase-N.raw.json`) appended across retry attempts via AWK's `>>` in the stream processor. But `has_write_actions()` in retry.sh scopes to `=== EXECUTION START` markers that only exist in the formatted log, not the raw JSON. Result: attempt N inherited tool call records from attempt 1, causing a read-only session to pass the "has write actions" check.

2. **Absolute refactor verification:** The refactor verification prompt said "if ANY check fails: output VERIFICATION_FAILED." If the build was already broken before refactoring, the verifier saw pre-existing errors and failed — even though the refactoring didn't cause them. After 5 failures, all refactoring was rolled back.

A secondary issue: small models (e.g. Qwen3.5-35B) often explored extensively without outputting the required `VERIFICATION_PASSED`/`VERIFICATION_FAILED` keyword, causing "no verdict" failures.

## Decision

### Raw log reset

Truncate the raw log (`: > "$raw_log"`) in `execute_phase()` before calling `run_claude_pipeline`. This ensures `has_write_actions()` and `has_trapped_tool_calls()` only see events from the current attempt. The formatted log already gets overwritten via `> "$log_file"`.

### Regression-based verification

Replace the absolute pass/fail verification prompt in `verify_refactor()` with regression-aware instructions:

- Provide the pre-refactor SHA for `git diff --name-only` (lightweight, no huge diff output)
- Check for regressions, not absolute correctness
- Pre-existing errors in unchanged code are acceptable
- Errors that moved between files during refactoring (e.g., from original to extracted module) are acceptable
- Only fail if the refactoring introduced genuinely new errors

### Anti-duplication rule

Add explicit instruction to `build_refactor_prompt()`: "MOVE code into new files — do NOT create copies." This prevents observed behavior where models created near-duplicate files instead of extracting.

### Stronger verdict prompts

Strengthen verdict wording in both `verify_phase()` and `verify_refactor()` with explicit warnings that omitting the verdict causes automatic failure. This helps small models that tend to explore without concluding.

## Consequences

**Positive:**
- Retry logic correctly scopes to current attempt's tool calls
- Pre-existing build failures no longer cause refactoring rollback
- Clearer model instructions reduce "no verdict" failures
- Anti-duplication rule prevents file bloat during refactoring

**Negative:**
- Regression-based verification is more permissive — a refactoring could theoretically mask a pre-existing error becoming worse, though this is unlikely for purely structural changes
- Raw log history across attempts is lost (but formatted log archives remain via `rotate_phase_log`)
