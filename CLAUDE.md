# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Does

ClaudeLoop executes multi-phase plans by spawning a fresh `claude --non-interactive` CLI instance per phase. Each phase gets a full context window. The main script reads a `PLAN.md`, runs phases sequentially (respecting dependencies), writes progress to `PROGRESS.md`, and supports Ctrl+C interrupt + resume via `.claudeloop/state/current.json`.

## Commands

```sh
# Run all tests
./tests/run_all_tests.sh

# Run a single test file
bats tests/test_parser.sh

# Syntax check (POSIX sh mode)
shellcheck -s sh lib/retry.sh lib/ui.sh

# Validate a plan without executing
./claudeloop --plan examples/PLAN.md.example --dry-run
```

## Architecture

All shared state is held in global shell variables — there is no process-level state or config file.

### Data model

Phase data lives in flat numbered variables (POSIX-compatible):
```
PHASE_TITLE_1, PHASE_TITLE_2, ...
PHASE_DESCRIPTION_1, PHASE_DESCRIPTION_2, ...
PHASE_DEPENDENCIES_1, PHASE_DEPENDENCIES_2, ...  (space-separated phase numbers)
PHASE_STATUS_1, PHASE_STATUS_2, ...              (pending|in_progress|completed|failed)
PHASE_ATTEMPTS_1, PHASE_ATTEMPTS_2, ...
PHASE_START_TIME_1, PHASE_END_TIME_1, ...
PHASE_COUNT                                       (total number of phases)
```

Access pattern everywhere:
```sh
# Read
value=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")
# Write
eval "PHASE_STATUS_${phase_num}='completed'"
```

### Library responsibilities

| File | Responsibility |
|------|---------------|
| `lib/parser.sh` | Parses `PLAN.md` → sets `PHASE_TITLE_N`, `PHASE_DESCRIPTION_N`, `PHASE_DEPENDENCIES_N`, `PHASE_COUNT` |
| `lib/dependencies.sh` | `is_phase_runnable`, `find_next_phase`, cycle detection (DFS using space-separated strings for visited/stack) |
| `lib/progress.sh` | `init_progress` / `read_progress` / `write_progress` — reads and writes `PROGRESS.md`; `update_phase_status` sets status and timestamps |
| `lib/retry.sh` | `power`, `get_random`, `calculate_backoff`, `should_retry_phase` |
| `lib/ui.sh` | Terminal output — `print_header`, `print_phase_status`, `print_all_phases`, `print_phase_exec_header`, `print_success/error/warning` |
| `claudeloop` | Orchestrator: arg parsing, signal handlers (`trap handle_interrupt INT TERM`), lock file, main loop |

### Execution flow

```
main() → parse_plan → init_progress → main_loop
  main_loop:
    find_next_phase → execute_phase → update_phase_status → write_progress
    on failure: should_retry_phase → calculate_backoff → sleep → retry
    on Ctrl+C: handle_interrupt → write_progress → save_state → exit 130
```

### POSIX rewrite (in progress)

The codebase is being migrated from `#!/opt/homebrew/bin/bash` (bash 5 associative arrays, `[[ ]]`, `BASH_REMATCH`, `**` exponentiation, `$RANDOM`, `echo -e`) to `#!/bin/sh` POSIX-compatible shell. TODOs track the work:

- **TODO1.md** ✅ — `lib/retry.sh`, `lib/ui.sh` (done)
- **TODO2.md** — `lib/dependencies.sh`, `lib/progress.sh`
- **TODO3.md** — `lib/parser.sh`, `claudeloop` main script

Until TODO2/3 are complete, `lib/parser.sh`, `lib/dependencies.sh`, `lib/progress.sh`, and `claudeloop` still use bash associative arrays. The `test_killswitch.sh` assertions for `init_progress`-restored state intentionally still use `${PHASE_STATUS[N]}` array syntax until TODO2 is done.

`local` is used throughout despite not being strictly POSIX — it is supported by all target shells (dash, bash, ksh, zsh, busybox sh) and is intentionally kept.

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core). Install with `brew install bats-core`.

- Follow TDD: write tests in `tests/test_<lib>.sh` before implementing
- Each lib file has a corresponding test file
- `tests/run_all_tests.sh` runs all `test_*.sh` files
- `shellcheck -s sh <file>` is the linter; SC3043 (`local` warnings) are acceptable
