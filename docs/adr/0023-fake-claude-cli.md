# 23. Fake Claude CLI for Verification & Testing

**Date:** 2026-03-08
**Status:** Accepted

## Context

The `/verify` skill and integration tests use trivial 2-line stubs (`printf 'stub output\n'` + one tool_use JSON line) that barely exercise the stream processor, retry logic, or verification flow. A realistic fake CLI would let verification observe behavior closely matching real Claude Code — multi-turn tool calls, model metadata, session summaries — without API costs.

## Decision

Create `tests/fake_claude`, a standalone POSIX shell script that emits hardcoded NDJSON matching the real Claude CLI `--output-format=stream-json` contract. It supports multiple scenarios (success, failure, quota error, permission error, verify pass/fail/skip, rate limit, slow, custom) configured via files in `$FAKE_CLAUDE_DIR`.

Key design choices:

- **Hardcoded printf strings** per scenario — no dynamic JSON generation, so the output is deterministic and auditable
- **Per-call overrides** via numbered files (scenarios, exit_codes) for multi-call test sequences
- **Stdin/args capture** for prompt and argument verification
- **Golden file** (`tests/fixtures/stream_json_sample.ndjson`) extracted from real logs for structural conformance
- **Weekly GitHub Actions workflow** checks for Claude Code version changes and opens an issue if the upstream format may have changed

The `/verify` skill is updated to use `fake_claude` with the `success_multi` scenario instead of the minimal inline stub.

## Consequences

**Positive:**
- Verification observes realistic stream processor output (model name, multiple tool calls, session summary with cost/tokens)
- New test scenarios can be added as simple functions without touching existing test stubs
- Version drift is detected automatically via CI

**Negative:**
- Fake scenarios must be kept in sync with real CLI output format (mitigated by compat workflow)
- Another file to maintain in the test suite
