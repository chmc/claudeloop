# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git

Use conventional commits

## Commands

```sh
./tests/run_all_tests.sh              # run all tests
bats tests/test_parser.sh             # run one test file
shellcheck -s sh lib/retry.sh         # lint (SC3043 local warnings are acceptable)
./claudeloop --plan examples/PLAN.md.example --dry-run
claudeloop --monitor  # watch live output from a second terminal
```

## Architecture

All state is global shell variables — no config file, no subprocess state.

### Data model

Phase data in flat numbered variables (dots replaced with underscores in var names):
```
PHASE_TITLE_N         PHASE_DESCRIPTION_N    PHASE_DEPENDENCIES_N  (space-separated nums)
PHASE_STATUS_N        (pending|in_progress|completed|failed)
PHASE_ATTEMPTS_N      PHASE_START_TIME_N     PHASE_END_TIME_N
PHASE_COUNT           (total number of phases)
PHASE_NUMBERS         (space-separated ordered list, e.g. "1 2 2.5 2.6 3")
LIVE_LOG              (path to .claudeloop/live.log; empty string during dry-run)
```

Phase numbers may be decimals (e.g. `2.5`). The dot is replaced with underscore for variable
names: `PHASE_TITLE_2_5`. Two helpers defined in `lib/parser.sh` and available everywhere:

```sh
phase_to_var "2.5"          # → "2_5"  (used before every eval)
phase_less_than "2.5" "3"   # → exit 0 (true); uses awk for correct float comparison
```

Read/write pattern used everywhere:
```sh
phase_var=$(phase_to_var "$phase_num")
value=$(eval "echo \"\$PHASE_STATUS_${phase_var}\"")
eval "PHASE_STATUS_${phase_var}='completed'"
```

Iteration pattern (replaces old `i=1; while [ "$i" -le "$PHASE_COUNT" ]` loops):
```sh
for phase_num in $PHASE_NUMBERS; do
  phase_var=$(phase_to_var "$phase_num")
  ...
done
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
  --monitor:   run_monitor → tail -f .claudeloop/live.log
```

All `print_*` output (via `lib/ui.sh`) and stream processor output are teed to `.claudeloop/live.log` via `LIVE_LOG` (set in `main()` after `setup_project`; empty during dry-run).

### POSIX migration

Migrated from `#!/opt/homebrew/bin/bash` (associative arrays, `[[ ]]`, `BASH_REMATCH`, `**`, `$RANDOM`, `echo -e`) to `#!/bin/sh`:

| TODO | Files | Status |
|------|-------|--------|
| TODO1.md | `lib/retry.sh`, `lib/ui.sh` | ✅ done |
| TODO2.md | `lib/dependencies.sh`, `lib/progress.sh` | ✅ done |
| TODO3.md | `lib/parser.sh`, `claudeloop` | ✅ done |

## Testing

Uses [bats-core](https://github.com/bats-core/bats-core) (`brew install bats-core`). Each lib has a corresponding `tests/test_<lib>.sh`.

### TDD workflow (mandatory)

1. **Write failing tests first** — add tests to the relevant `tests/test_<lib>.sh` before touching implementation
2. **Verify tests fail** — `bats tests/test_<lib>.sh` must show the new tests as `not ok`
3. **Implement** — make the minimal change to pass the tests
4. **Verify tests pass** — `bats tests/test_<lib>.sh` must show all tests as `ok`
5. **Run full suite** — `./tests/run_all_tests.sh` must pass (excluding pre-existing failures)

When modifying existing behavior, update affected tests before changing implementation code.
