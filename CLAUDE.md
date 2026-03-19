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

## Planning

### Exploration must produce constraints, not summaries

Explore agents must output a structured constraints brief, not prose summaries:

1. **Conventions observed** — patterns, error handling, naming. Cite files and lines.
2. **Touch points** — every function, variable, and file the change interacts with. Include signatures and callers.
3. **Traps and gotchas** — anything that would surprise a naive implementation (e.g., `set -eu` behavior, `eval`-based dynamic vars, lock file semantics, `_CLAUDELOOP_NO_*` env vars for test isolation).
4. **Existing tests to update** — which test files cover the functions being modified, with specifics.

### Plan agents must justify decisions from constraints

Every design decision must trace to a constraint from exploration or an explicit trade-off. If the planner is making an assumption about the codebase, that's a gap — flag it, don't guess. Plans must:

- List every file to create/modify with specific functions and variables
- For each modified function, state current signature, proposed change, affected callers
- For each edge case, state the scenario and handling (not "handle errors" — say what error, what happens)
- State what is NOT changing and why

### One review pass, not three

Single fact-checking pass: for each file in the plan, verify function signatures exist, callers are accounted for, and tests are updated. This is fact-checking, not design critique. If it finds issues, the exploration was insufficient — improve exploration, don't add more review rounds.

## Continuous improvement (mandatory)

When you notice a friction point, missing guardrail, or automation opportunity during any phase of work, raise it and suggest a concrete change. Target:

- **CLAUDE.md** — new rules, refined wording, missing examples
- **Skills/hooks** — repetitive multi-step sequences that could be a slash command or hook
- **MCP tools/plugins** — external integrations that would reduce manual steps

Keep suggestions brief and actionable (what to change, where, why). Don't derail the current task — note it at a natural pause point (end of a planning phase, after implementation, during wrap-up).

## Documentation

When implementation is changed, check if the change affects user-facing behavior (CLI options, workflows, defaults, install steps, output format). If so, update stale sections in README.md and QUICKSTART.md, or add new sections for new features.

### Visual assets (mandatory)

When changes affect terminal output (logo, colors, spinners, progress display, phase formatting), regenerate all demo GIFs and screenshots via VHS tapes. See `assets/README.md` for commands. All tapes can run in parallel.

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
REFACTOR_PHASES       (true|false, default false)
LIVE_LOG              (path to .claudeloop/live.log; empty string during dry-run)
.claudeloop/signals/phase-N.md  (no-changes signal file; written by Claude when phase needs no code changes)
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
| `lib/retry.sh` | `calculate_backoff`, `should_retry_phase`, `has_write_actions`, `has_signal_file`, `retry_strategy`, `escalate_strategy`, `verify_mode`, `extract_error_context`, `extract_verify_error`, `build_retry_context` |
| `lib/stream_processor.sh` | `process_stream_json` (AWK-based stream parser), `inject_heartbeats` |
| `lib/ui.sh` | `print_header`, `print_phase_status`, `print_all_phases`, `print_phase_exec_header`, `print_success/error/warning`, `log_verbose` |
| `lib/config.sh` | `load_config`, `write_config`, `update_conf_key`, `run_setup_wizard` |
| `lib/verify.sh` | `verify_phase`, `check_verdict` — read-only verification, verdict-based pass/fail (`VERIFICATION_PASSED`/`VERIFICATION_FAILED`), JSON-aware anti-skip check, stream processor integration, timeout |
| `lib/refactor.sh` | `build_refactor_prompt`, `verify_refactor`, `refactor_phase`, `run_refactor_if_needed` — opt-in auto-refactoring with git rollback |
| `lib/execution.sh` | `execute_phase`, `run_claude_pipeline`, `evaluate_phase_result`, `run_adaptive_verification`, `update_fail_reason` |
| `lib/archive.sh` | `archive_current_run`, `list_archives`, `restore_archive`, `generate_archive_metadata`, `is_run_complete`, `prompt_archive_completed_run` |
| `claudeloop` | Orchestrator: arg parsing, `trap handle_interrupt INT TERM`, lock file, `main_loop` |

### Execution flow

```
main → parse_plan → init_progress → main_loop
  find_next_phase → execute_phase → verify_phase → refactor_phase → update_phase_status → write_progress
  no-changes:  signal file (.claudeloop/signals/phase-N.md) + successful session → skip verification → complete
  on failure:  should_retry_phase → retry_strategy → calculate_backoff → sleep → retry (standard/stripped/targeted)
  on Ctrl+C:   handle_interrupt → rollback refactor (if active) → write_progress → save_state → exit 130
  --monitor:   run_monitor → tail -f .claudeloop/live.log
```

All `print_*` output (via `lib/ui.sh`) and stream processor output are teed to `.claudeloop/live.log` via `LIVE_LOG` (set in `main()` after `setup_project`; empty during dry-run).

### Packaging

Runtime files ship via three mechanisms that must stay in sync:

| Mechanism | File | What to update |
|-----------|------|----------------|
| Release tarball | `.github/workflows/release.yml` | `Build release tarball` step |
| Installer | `install.sh` | `cp`/`mkdir` commands |
| Installer tests | `tests/test_install.sh` | assert file exists after install |

Currently packaged: `claudeloop`, `lib/*.sh`, `assets/replay-template.html`.

### PROGRESS.md field registry

`write_progress` / `generate_phase_details` in `lib/progress.sh` is the source of truth
for PROGRESS.md fields. Three parsers read this format:

| Parser | File | Namespace | Notes |
|--------|------|-----------|-------|
| `read_progress` | `lib/progress.sh` | `PHASE_*` | Validates status enum, normalizes in_progress |
| `read_old_phase_list` | `lib/plan_changes.sh` | `_OLD_PHASE_*` | Normalizes in_progress, no validation |
| `rec_load_progress` | `lib/recorder.sh` | `_REC_PHASE_*` | No normalization (preserves raw state) |

When adding fields to `write_progress`, update all three parsers. A round-trip parity
test in `test_progress.sh` enforces this. Per-attempt fields must also be added to
`transfer_attempt_fields()` in `lib/plan_changes.sh`.

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

**Reproduce before fixing (mandatory):** When fixing a bug, reproduce it first using existing test infrastructure (fake CLI, bats fixtures, `--replay`). If the infrastructure can't reproduce the scenario, extend it. Code tracing alone is insufficient — verify the fix works end-to-end.

When found failing suites that are pre-existing, mandatory rule to fix them.

### Completion gate (mandatory)

After all implementation and tests pass, run `/verify` before reporting the task as done. The verify skill selects appropriate checks (smoke, stub, GUI) based on which files changed. Skip only for documentation-only or test-only changes with no implementation modifications.

When adding runtime files (libraries, templates, assets), verify they are included in the release tarball (`.github/workflows/release.yml`), installer (`install.sh`), and installer tests (`tests/test_install.sh`).

If the change affects terminal output, also regenerate visual assets (`assets/README.md`) before reporting done.