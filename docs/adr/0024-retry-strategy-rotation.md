# 24. Retry strategy rotation for model-agnostic resilience

**Date:** 2026-03-09
**Status:** Accepted

## Context
Weaker models (e.g. local Qwen3.5-35B) fail all retries because claudeloop repeats the same prompt structure with escalating pressure. Fresh instances can't learn from previous failures. 80 lines of raw context noise fills limited context windows. Each fresh instance wastes turns on git discovery that claudeloop already knows.

## Decision
Three-tier retry strategy rotation (standard → stripped → targeted), git state injection on all attempts, adaptive verification (full → quick → skip), and focused error extraction replacing raw tail output.

- **Standard** (first 1/3 of retries): full prompt with focused error context (30 lines vs 80)
- **Stripped** (middle 1/3): minimal prompt — title, description, error only
- **Targeted** (final 1/3): error-only prompt — fix the specific failure, test, commit
- **Git state**: injected on every attempt (saves 2-3 tool calls per attempt)
- **Adaptive verification**: full on tier 1, quick (has_write_actions + exit code) on tier 2, skip on tier 3

## Consequences
- Positive: Better success rates for weaker/non-Claude models; reduced wasted time from verification on hopeless retries; git state saves tool calls on all attempts; focused error context reduces noise
- Negative: Later retry tiers give less context, which could theoretically hurt strong models on complex tasks (mitigated: strong models rarely reach those tiers)
