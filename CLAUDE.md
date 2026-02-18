# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
./tests/run_all_tests.sh              # run all tests
bats tests/test_parser.sh             # run one test file
shellcheck -s sh lib/retry.sh         # lint (SC3043 local warnings are acceptable)
./claudeloop --plan examples/PLAN.md.example --dry-run
```

## Architecture

All state is global shell variables — no config file, no subprocess state.

### Data model

Phase data in flat numbered variables:
```
PHASE_TITLE_N         PHASE_DESCRIPTION_N    PHASE_DEPENDENCIES_N  (space-separated nums)
PHASE_STATUS_N        (pending|in_progress|completed|failed)
PHASE_ATTEMPTS_N      PHASE_START_TIME_N     PHASE_END_TIME_N
PHASE_COUNT
```

Read/write pattern used everywhere:
```sh
value=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")
eval "PHASE_STATUS_${phase_num}='completed'"
```

### Libraries

| File | Key functions |
|------|--------------|
| `lib/parser.sh` | `parse_plan` → sets all `PHASE_*_N` vars and `PHASE_COUNT` |
| `lib/dependencies.sh` | `find_next_phase`, `is_phase_runnable`, `detect_dependency_cycles` (DFS, space-separated visited/stack strings) |
| `lib/progress.sh` | `init_progress`, `read_progress`, `write_progress`, `update_phase_status` |
| `lib/retry.sh` | `calculate_backoff` (exponential + jitter), `should_retry_phase`, `power`, `get_random` |
| `lib/ui.sh` | `print_header`, `print_phase_status`, `print_all_phases`, `print_phase_exec_header`, `print_success/error/warning` |
| `claudeloop` | Orchestrator: arg parsing, `trap handle_interrupt INT TERM`, lock file, `main_loop` |

### Execution flow

```
main → parse_plan → init_progress → main_loop
  find_next_phase → execute_phase → update_phase_status → write_progress
  on failure:  should_retry_phase → calculate_backoff → sleep → retry
  on Ctrl+C:   handle_interrupt → write_progress → save_state → exit 130
```

### POSIX migration

Migrated from `#!/opt/homebrew/bin/bash` (associative arrays, `[[ ]]`, `BASH_REMATCH`, `**`, `$RANDOM`, `echo -e`) to `#!/bin/sh`:

| TODO | Files | Status |
|------|-------|--------|
| TODO1.md | `lib/retry.sh`, `lib/ui.sh` | ✅ done |
| TODO2.md | `lib/dependencies.sh`, `lib/progress.sh` | ✅ done |
| TODO3.md | `lib/parser.sh`, `claudeloop` | ✅ done |

## Testing

Uses [bats-core](https://github.com/bats-core/bats-core) (`brew install bats-core`). TDD: write `tests/test_<lib>.sh` before implementing. Each lib has a corresponding test file.
