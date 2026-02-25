# 8. Layered Config Precedence (Defaults → Conf → Env → CLI)

**Date:** 2026-02-18
**Status:** Accepted

## Context

Users need multiple ways to configure ClaudeLoop: sensible defaults for zero-config usage, a project-level config file for team settings, environment variables for CI/automation, and CLI flags for one-off overrides. These sources can conflict, so a clear precedence order is needed.

## Decision

Implement a four-layer config precedence chain where later layers override earlier ones:

1. **Hardcoded defaults** — set in the script (e.g., `MAX_RETRIES=5`, `BASE_DELAY=5`)
2. **Config file** (`.claudeloop/.claudeloop.conf`) — plain `KEY=VALUE` format, auto-created on first run
3. **Environment variables** — same names as config keys (e.g., `MAX_RETRIES=10 claudeloop`)
4. **CLI arguments** — highest priority (e.g., `--max-retries 10`)

On first run, the active settings are written to the config file. On subsequent runs with CLI arguments, only the explicitly set keys are updated in the conf file. `--dry-run` never writes or modifies the config file.

One-time flags (`--reset`, `--phase`, `--mark-complete`, `--dry-run`, `--verbose`, `--continue`) are never persisted to the config file.

## Consequences

**Positive:**
- Zero-config works out of the box with sensible defaults
- Teams can commit `.claudeloop.conf` for shared settings
- CI pipelines can override via environment variables
- CLI flags provide escape hatches for any setting
- Config file is plain text — easy to edit or delete

**Negative:**
- Four layers of precedence can make it hard to determine where a value came from
- Auto-creation of config file on first run is a side effect that may surprise users
- Selective update of CLI-specified keys requires tracking which flags were explicitly set vs. defaulted
