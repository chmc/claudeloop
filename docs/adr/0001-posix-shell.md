# 1. Use POSIX sh Instead of Bash

**Date:** 2026-02-18
**Status:** Accepted

## Context

The original implementation used `#!/opt/homebrew/bin/bash` with Bash-specific features: associative arrays, `[[ ]]` conditionals, `BASH_REMATCH`, `**` globbing, `$RANDOM`, and `echo -e`. This tied the tool to a specific Bash installation path and version, limiting portability across macOS and Linux systems where Bash versions and paths vary.

## Decision

Migrate all scripts to `#!/bin/sh` (POSIX sh). The migration was done in three phases:

1. `lib/retry.sh` and `lib/ui.sh` — replaced `$RANDOM` with an awk-based RNG, `echo -e` with `printf`, `[[ ]]` with `[ ]`
2. `lib/dependencies.sh` and `lib/progress.sh` — replaced associative arrays with space-separated strings, `BASH_REMATCH` with `expr` or `sed`
3. `lib/parser.sh` and `claudeloop` — final conversion of the parser and orchestrator

Key substitutions:
- Associative arrays → space-separated key-value strings
- `[[ ]]` → `[ ]` with proper quoting
- `BASH_REMATCH` → `expr` / `sed` / `awk`
- `$RANDOM` → `awk 'BEGIN{srand(); print int(rand()*32768)}'`
- `echo -e` → `printf`

## Consequences

**Positive:**
- Runs on any POSIX-compliant system without requiring a specific Bash version
- No dependency on Homebrew or a particular Bash path
- Smaller attack surface (fewer shell features to misuse)

**Negative:**
- More verbose code for operations that Bash handles natively (e.g., arrays, pattern matching)
- `local` keyword triggers SC3043 shellcheck warnings (accepted as pragmatic trade-off since all target shells support it)
- Some constructs require external tools (awk, sed, expr) instead of shell builtins
