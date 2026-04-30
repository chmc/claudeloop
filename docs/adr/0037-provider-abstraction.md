# 37. Provider Abstraction Layer

**Date:** 2026-04-30
**Status:** Accepted

## Context

claudeloop was tightly coupled to Claude CLI: hardcoded binary name, stream-json event format, FD7 permission protocol, tool names for write-action detection, and verification verdict keywords. This blocked support for alternative AI CLIs (e.g., OpenCode) and made protocol changes high-risk.

## Decision

Introduce an adapter-shim pattern that normalizes provider differences without rewriting the 928-line AWK stream processor:

- `lib/provider.sh` — public interface (detect, cli, args, patterns)
- `lib/adapters/{provider}.sh` — provider-specific implementations
- `lib/permission_interface.sh` — shared permission decision logic
- `lib/adapters/permission_{provider}.sh` — provider permission protocols

Each provider adapter implements:
1. `_provider_exec_args()` / `_provider_print_args()` — CLI invocation flags
2. `_provider_write_tool_pattern()` — regex for detecting write actions
3. `_provider_verdict_pass/fail_keyword()` — verification verdict markers
4. `_provider_permission_protocol()` — "stdio" (FD7), "http" (API), or "none"

User configuration via `--provider <name>` or `PROVIDER` env/config variable.

## Consequences

**Positive:**
- Claude behavior unchanged (adapter is parity-preserving)
- New providers plug in without modifying stream processor
- Permission handling is provider-agnostic at decision layer
- Configuration precedence follows existing pattern (CLI > env > config)

**Negative:**
- Event normalization adds a translation layer
- Each provider needs its own adapter + permission handler
- Version compatibility tracking required per provider
