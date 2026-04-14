# 14. AI verification feedback loop

**Date:** 2026-02-25
**Status:** Accepted

## Context

The AI parser (`--ai-parse`) generates structured phases from free-form plans via `claude --print`. The original implementation had two problems:

1. **Content loss**: The AI rewrote/summarized descriptions instead of extracting original content. Since `ai-parsed-plan.md` is the only file referenced at runtime (the original plan is not), any rewriting caused permanent content loss — missing tasks, wrong dependencies, shortened descriptions.

2. **Hard failure on verification**: When `ai_verify_plan` detected problems, the tool exited immediately with no way to recover except re-running from scratch.

## Decision

### Extract, don't rewrite

Changed `ai_parse_plan()` from a "decomposition" prompt to an "extraction" prompt:
- Instructs the AI to copy relevant original text as phase descriptions
- Explicitly forbids summarizing, paraphrasing, or inventing phases
- Excludes non-phase sections (Context, Architecture, TDD Rules, etc.)

### Verification feedback loop

Added `ai_parse_and_verify()` orchestrator that wraps the parse→verify cycle:

1. `ai_parse_plan()` — initial extraction
2. `ai_verify_plan()` — now checks 4 criteria (completeness, correctness, ordering, content preservation)
3. On FAIL: writes reason to `.claudeloop/ai-verify-reason.txt`
4. `ai_reparse_with_feedback()` — sends original + failed output + reason back to AI
5. Loop up to `AI_RETRY_MAX` (default 3) times
6. Interactive prompt "Send feedback to AI and retry? (Y/n)" (auto-retry in `YES_MODE`)

### Setup wizard integration

Added AI_PARSE and GRANULARITY questions to the interactive first-run wizard, following the existing pattern for other settings.

## Consequences

**Positive:**
- Phase descriptions faithfully represent the original plan content
- Verification failures are recoverable without full restart
- Each retry gives the AI specific feedback about what went wrong
- Wizard makes AI parsing discoverable for new users

**Negative:**
- Retries cost additional API calls (up to 3 extra round-trips)
- Extraction prompt is more constrained, potentially less creative for truly ambiguous plans

### Non-interactive extension points

Two flags expose the feedback loop to external callers (e.g., editor extensions) that need to drive retries programmatically rather than interactively:

- `--no-retry` — runs a single parse+verify pass via `ai_parse_no_retry()` and exits immediately. Exit codes: 0 = verification passed, 2 = verification failed, 1 = unexpected error. Failure reason is written to `.claudeloop/ai-verify-reason.txt`.
- `--ai-parse-feedback` — entry point for a programmatic retry pass via `ai_parse_feedback()`. Reads the failure reason from `ai-verify-reason.txt` and sends it back to the AI. Does not archive `live.log` so that consecutive programmatic retries share one continuous log.

Together these flags let an external caller implement its own retry loop: call `--no-retry`, inspect the exit code, and if 2 is returned call `--ai-parse-feedback` with the desired granularity.
