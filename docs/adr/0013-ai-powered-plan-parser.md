# 13. AI-Powered Plan Parser

**Date:** 2026-02-25
**Status:** Accepted

## Context

The regex-based parser (`lib/parser.sh`) requires plans in `## Phase N: Title` format. Users want to feed any plan file — free-form text, bullet lists, or vague descriptions — and have an AI decompose it into executable phases. Smaller increments work better with non-frontier LLM models.

## Decision

Add `--ai-parse` flag and a new library `lib/ai_parser.sh` that:

1. Calls `claude --print` to decompose free-form plans into `## Phase N:` markdown
2. Calls `claude --print` a second time to verify completeness against the original
3. Shows the result to the user for confirmation before proceeding
4. Outputs standard format consumed by the **unchanged existing parser**

Key design choices:
- **`claude --print`** for AI calls — same tool already required by the project
- **Integer-only numbering** (1, 2, 3...) to avoid float comparison edge cases in `phase_less_than`
- **Two-call pattern** (parse + verify) — verification is heuristic (same model family reviewing its own work), user confirmation is the real safety net
- **One retry** on parse validation failure with specific error feedback
- **120s timeout** on AI calls via `timeout` command (POSIX fallback: background + sleep + kill)
- **Preamble stripping** via awk to extract only `## Phase` content
- **AI-parsed plan persisted** to `.claudeloop/ai-parsed-plan.md`; `--continue` checks config to reuse
- **Three granularity levels** (`--granularity phases|tasks|steps`) controlling breakdown depth

## Consequences

**Positive:**
- Users can feed any plan format without manual conversion
- Granularity control lets users choose appropriate breakdown depth
- Existing parser remains unchanged — AI output is just standard markdown
- Verification step catches obvious decomposition errors

**Negative:**
- Requires working `claude` CLI with API access for parsing (not just execution)
- Verification is heuristic — same model family reviewing its own work
- Large plans (500+ lines) may degrade AI quality or hit context limits
- No model selection flag — uses default claude model
