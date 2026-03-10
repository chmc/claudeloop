# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git

Use conventional commits

### Branching model

Two long-lived branches:

| Branch | Purpose | VERSION state |
|--------|---------|---------------|
| `main` | Stable/production code | Always stable (e.g. `0.16.0`) |
| `beta` | Experimental/beta development | Always beta (e.g. `0.17.0-beta.1`) |

**Rebase-only policy:** No merge commits. All branch synchronization uses `git rebase` to keep linear history. After rebasing, always `git push --force-with-lease` to update the remote.

### Branch-awareness rule (mandatory)

Before starting any work (planning, coding, committing), check the current branch with `git branch --show-current`. Flag to the developer whether the current branch targets stable (`main`) or beta (`beta`) and ask how to proceed before making changes. If the work doesn't match the current branch, offer to switch.

## Documentation

Update documentation README.md QUICKSTART.md when implementation is changed

### ADR workflow (mandatory)

When making an architectural decision (new pattern, technology choice, significant design change), create an ADR:

1. Assign next sequential number from `docs/adr/`
2. Create `docs/adr/NNNN-slug.md` using the [ADR template](docs/adr/TEMPLATE.md)
3. Update `docs/adr/README.md` index

Examples of what warrants an ADR: changing the shell dialect, adding a new dependency, altering the state model, choosing a serialization format, modifying the execution pipeline.

## Commands

```sh
./tests/run_all_tests.sh              # run all tests
bats tests/test_parser.sh             # run one test file
shellcheck -s sh lib/retry.sh         # lint (SC3043 local warnings are acceptable)
./claudeloop --plan examples/PLAN.md.example --dry-run
claudeloop --monitor  # watch live output from a second terminal
./tests/smoke.sh                      # smoke test (stub-based, no bats)
./tests/mutate.sh                     # mutation testing (all lib files)
./tests/mutate.sh lib/retry.sh        # mutation testing (single file)
bats tests/test_fake_claude.sh        # fake CLI scenario tests
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
VERIFY_PHASES         (true|false, default false)
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
| `lib/retry.sh` | `calculate_backoff`, `should_retry_phase`, `has_write_actions`, `retry_strategy`, `verify_mode`, `extract_error_context`, `extract_verify_error`, `build_retry_context` |
| `lib/stream_processor.sh` | `process_stream_json` (AWK-based stream parser), `inject_heartbeats` |
| `lib/ui.sh` | `print_header`, `print_phase_status`, `print_all_phases`, `print_phase_exec_header`, `print_success/error/warning`, `log_verbose` |
| `lib/config.sh` | `load_config`, `write_config`, `update_conf_key`, `run_setup_wizard` |
| `lib/verify.sh` | `verify_phase` — read-only verification, verdict-based pass/fail (`VERIFICATION_PASSED`/`VERIFICATION_FAILED`), JSON-aware anti-skip check, stream processor integration, timeout |
| `lib/execution.sh` | `execute_phase`, `run_claude_pipeline`, `evaluate_phase_result`, `run_adaptive_verification` |
| `claudeloop` | Orchestrator: arg parsing, `trap handle_interrupt INT TERM`, lock file, `main_loop` |

### Execution flow

```
main → parse_plan → init_progress → main_loop
  find_next_phase → execute_phase → verify_phase → update_phase_status → write_progress
  on failure:  should_retry_phase → retry_strategy → calculate_backoff → sleep → retry (standard/stripped/targeted)
  on Ctrl+C:   handle_interrupt → write_progress → save_state → exit 130
  --monitor:   run_monitor → tail -f .claudeloop/live.log
```

All `print_*` output (via `lib/ui.sh`) and stream processor output are teed to `.claudeloop/live.log` via `LIVE_LOG` (set in `main()` after `setup_project`; empty during dry-run).

## Skills

- `/github` — Git/GitHub conventions (commit, push, PR)
- `/rebase sync|promote` — Safe branch rebasing (sync beta from main, promote beta to main)
- `/release beta|stable` — Trigger GitHub release workflow
- `/verify` — Verify claudeloop after code changes (smoke + GUI screenshots)

## Testing

Uses [bats-core](https://github.com/bats-core/bats-core) (`brew install bats-core`). Each lib has a corresponding `tests/test_<lib>.sh`.

### TDD workflow (mandatory)

1. **Write failing tests first** — add tests to the relevant `tests/test_<lib>.sh` before touching implementation
2. **Verify tests fail** — `bats tests/test_<lib>.sh` must show the new tests as `not ok`
3. **Implement** — make the minimal change to pass the tests
4. **Verify tests pass** — `bats tests/test_<lib>.sh` must show all tests as `ok`
5. **Run full suite** — `./tests/run_all_tests.sh` must pass (excluding pre-existing failures)

When modifying existing behavior, update affected tests before changing implementation code.

When found failing suites that are pre-existing, mandatory rule to fix them.

### Completion gate (mandatory)

After all implementation and tests pass, run `/verify` before reporting the task as done. The verify skill selects appropriate checks (smoke, stub, GUI) based on which files changed. Skip only for documentation-only or test-only changes with no implementation modifications.