# 39. Prompt-Injected Subagent Model Control

**Date:** 2026-06-09
**Status:** Accepted

## Context

claudeloop phases run inside a Claude Code CLI session. Within each session, Claude Code can spawn subagents via its `Agent()` tool, which accepts a `model` parameter to override the subagent's model. Explore agents (used for read-only codebase search) run on the main session model by default — typically opus or sonnet — even though their task is cheap grep/read work.

No Claude Code CLI flag or `settings.json` key exposes subagent model selection externally. The per-step model pattern from ADR 0038 controls which model the *phase session* uses, not which model subagents spawned *within* that session use.

Token profiling showed 55% of usage from subagent-heavy sessions, with Explore agents at 8%. Using haiku for Explore agents could materially reduce cost.

## Decision

Inject a natural-language directive into phase prompts via `append_subagent_model_instructions()` in `lib/prompt.sh`. When `SUBAGENT_MODEL_EXPLORE` is set, the directive is appended after all prompt construction (including retry strategy overrides) so it survives all retry tiers:

```
## Subagent Model Override

When using the Agent tool with subagent_type "Explore", always pass model: "<name>".
```

The injection happens in `execute_phase()` (`lib/execution.sh`) and `refactor_phase()` (`lib/refactor.sh`) after `apply_retry_strategy()` returns. Verification phases (`lib/verify.sh`) are excluded — they are quality gates and should not be downgraded.

Empirical validation confirmed compliance: `"model":"haiku"` and `"model":"claude-haiku-4-5-20251001"` appeared in Explore agent tool calls in the raw phase log.

CLI: `--subagent-model explore:haiku` (extensible to other types via `type:model` syntax).
Config key: `SUBAGENT_MODEL_EXPLORE`. Follows ADR 0008 precedence chain.

## Consequences

**Positive:**
- Works today without upstream Claude Code changes
- Zero behavior change when unset (empty default)
- Extensible: adding `plan:sonnet` support requires one config var + one line in the function
- Injection survives all retry strategy tiers (standard, stripped, targeted)

**Negative:**
- Prompt compliance is probabilistic — the model may not always pass the parameter. Validated empirically but not guaranteed
- No way to confirm the subagent used the specified model from claudeloop's own stream data; users must check Claude Code's usage reporting
- Does not apply to verification subagents (intentional, but means Explore agents in verify phases run at full cost)
