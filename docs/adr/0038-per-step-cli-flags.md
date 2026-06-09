# 38. Per-Step CLI Flag Management in Provider Adapters

**Date:** 2026-06-09
**Status:** Accepted

## Context

claudeloop spawns Claude CLI for three distinct purposes: phase execution, verification, and AI plan parsing. Each step has different capability requirements — verification benefits from a stronger model for careful reasoning, while execution and refactoring favor speed. Additionally, target projects can configure a default model (e.g., `"model": "opusplan"`) in `.claude/settings.json`, which the spawned Claude inherits, causing execution phases to run in plan mode rather than implementing changes.

The `--effort` flag (introduced in v0.31.0) established a pattern where a provider-specific CLI flag is managed as a global config variable and interpolated inside the adapter function. This ADR documents the generalization of that pattern to per-step model selection.

## Decision

Extend the adapter pattern so that provider-specific flags can vary by step type:

1. **Adapter resolves globals internally** — `_claude_exec_args()` reads `$MODEL` and `$MODEL_VERIFY` from the environment, same as `$EFFORT_LEVEL`. The public interface (`provider_exec_args()`) accepts an optional step-type argument (`exec`, `verify`, `refactor`) and forwards it to the adapter. OpenCode adapter ignores it (no model flag exists there).

2. **Step-type parameter, not new functions** — a single `provider_exec_args()` with an optional step-type argument rather than `provider_verify_args()`, `provider_refactor_args()`, etc. Avoids combinatorial explosion as step types grow.

3. **Two config variables** — `MODEL` (execution + refactoring) and `MODEL_VERIFY` (verification). Refactoring shares `MODEL` because it is the same workload tier. If `MODEL_VERIFY` is empty, verification falls back to `MODEL`.

4. **Empty defaults** — no `--model` flag is emitted when the variable is empty, preserving existing behavior where Claude CLI respects the project's `.claude/settings.json`. Users who want explicit control set the variables.

5. **Config precedence follows ADR 0008** — env var → config file → CLI flag, same as all other settings.

## Consequences

**Positive:**
- Existing users: zero behavior change (empty defaults)
- Projects with `"model": "opusplan"` can be overridden via `--model sonnet --model-verify opus`
- Pattern generalizes: per-step effort or other flags follow the same shape
- OpenCode adapter is unaffected

**Negative:**
- `EFFORT_LEVEL` remains global (no per-step effort). If per-step effort is needed later, the same parameterization applies
- Two model variables to configure instead of one (acceptable given the different capability needs of verify vs exec)
