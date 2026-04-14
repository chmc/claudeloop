# CLAUDE.md

## Git

Use conventional commits.

**Branches:** `main` (stable, e.g. `0.16.0`) / `beta` (experimental, e.g. `0.17.0-beta.1`). Rebase-only — no merge commits. After rebasing, `git push --force-with-lease`.

**Branch-awareness (mandatory):** Before any work, run `git branch --show-current`. Flag whether current branch targets stable or beta and ask before making changes. Offer to switch if work doesn't match.

## Planning

### Exploration must produce constraints, not summaries

Explore agents must output a structured constraints brief:

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

### Multi-angle review (mandatory)

Always launch 2-3 Plan agents with different critique perspectives during planning, even for seemingly simple fixes. Never skip this step. Thoroughness over speed in planning.

**One review pass:** Single fact-checking pass per file — verify function signatures exist, callers are accounted for, tests are updated. If it finds issues, the exploration was insufficient — improve exploration, don't add more review rounds.

## Continuous improvement (mandatory)

When you notice a friction point, missing guardrail, or automation opportunity, raise it and suggest a concrete change targeting **CLAUDE.md**, **skills/hooks**, or **MCP tools/plugins**. Keep suggestions brief and actionable. Don't derail the current task — note it at a natural pause point.

When a behavioral correction applies to this project, update CLAUDE.md or the relevant skill file — don't write a memory as a substitute. Rules scoped to a single workflow (e.g., releases, rebasing) belong in that workflow's skill file. CLAUDE.md is for cross-cutting project rules only. Memory is for ephemeral context and cross-project user preferences.

**Plan execution (mandatory):** When the user provides an explicit multi-step plan (e.g., "promote → release → sync"), execute all steps without asking for confirmation between them. The stated plan is the authorization. Only stop on failure, unexpected results, or conditional warnings.

## Documentation

When implementation changes affect user-facing behavior, update stale sections in README.md and QUICKSTART.md.

**Visual assets (mandatory):** When changes affect terminal output, regenerate all demo GIFs/screenshots via VHS tapes. See `assets/README.md`. All tapes can run in parallel.

**ADR workflow (mandatory):** For architectural decisions (new pattern, technology choice, significant design change): assign next number from `docs/adr/`, create `docs/adr/NNNN-slug.md` using the [template](docs/adr/TEMPLATE.md), update `docs/adr/README.md`. Examples: changing shell dialect, adding dependency, altering state model, choosing serialization format, modifying execution pipeline.

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

**Shell dialect:** POSIX `#!/bin/sh`. No bashisms (arrays, `[[ ]]`, `local` in functions is acceptable per SC3043). All libraries must be sourceable by dash/ash.

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

Prefer `phase_get`/`phase_set` from `lib/phase_state.sh` for new code. Raw eval shown for reading existing code and parsers.

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
| `lib/ai_parser.sh` | `ai_parse_plan`, `ai_verify_plan`, `ai_reparse_with_feedback`, `ai_parse_and_verify`, `show_ai_plan`, `confirm_ai_plan`, `ai_parse_no_retry` (`--no-retry`: single pass, exit 2 on failure), `ai_parse_feedback` (`--ai-parse-feedback`: reparse from ai-verify-reason.txt, no live.log archival) |
| `lib/dependencies.sh` | `find_next_phase`, `is_phase_runnable`, `detect_dependency_cycles` (DFS, space-separated visited/stack strings) |
| `lib/phase_state.sh` | `phase_get`, `phase_set`, `get_phase_status`, `reset_phase_for_retry`, `reset_phase_full`, `auto_commit_changes` |
| `lib/progress.sh` | `init_progress`, `read_progress`, `write_progress`, `update_phase_status` |
| `lib/plan_changes.sh` | `transfer_attempt_fields`, `read_old_phase_list`, `detect_plan_changes`, `detect_orphan_logs`, `recover_progress_from_logs` |
| `lib/prompt.sh` | `build_phase_prompt`, `capture_git_context`, `build_default_prompt`, `apply_retry_strategy` |
| `lib/retry.sh` | `calculate_backoff`, `should_retry_phase`, `has_write_actions`, `has_signal_file`, `retry_strategy`, `escalate_strategy`, `verify_mode`, `extract_error_context`, `extract_verify_error`, `build_retry_context` |
| `lib/stream_processor.sh` | `process_stream_json` (AWK-based stream parser), `inject_heartbeats` |
| `lib/ui.sh` | `print_header`, `print_phase_status`, `print_all_phases`, `print_phase_exec_header`, `print_success/error/warning`, `log_verbose` |
| `lib/config.sh` | `load_config`, `write_config`, `update_conf_key`, `run_setup_wizard` |
| `lib/verify.sh` | `verify_phase`, `check_verdict` — read-only verification, verdict-based pass/fail (`VERIFICATION_PASSED`/`VERIFICATION_FAILED`), JSON-aware anti-skip check, stream processor integration, timeout |
| `lib/refactor.sh` | `build_refactor_prompt`, `verify_refactor`, `refactor_phase`, `run_refactor_if_needed` — opt-in auto-refactoring with git rollback |
| `lib/execution.sh` | `execute_phase`, `run_claude_pipeline`, `evaluate_phase_result`, `run_adaptive_verification`, `update_fail_reason` |
| `lib/archive.sh` | `archive_current_run`, `list_archives`, `restore_archive`, `generate_archive_metadata`, `is_run_complete`, `prompt_archive_completed_run` |
| `lib/recorder.sh` | `rec_load_progress`, `inject_and_write_html`, `generate_replay`, `assemble_recorder_json`, `safe_json_array`, `safe_json_object`, `validate_json` |
| `lib/recorder_overview.sh` | `rec_extract_run_overview`, `_rec_overview_from_metadata`, `_rec_aggregate_sessions` |
| `lib/recorder_parsers.sh` | `rec_extract_session`, `rec_extract_tools`, `rec_extract_files`, `rec_extract_tool_calls`, `rec_verify_verdict` |
| `lib/release_notes.sh` | `format_release_notes` |
| `claudeloop` | Orchestrator: arg parsing, `trap handle_interrupt INT TERM`, lock file, `main_loop` |

### Execution flow

```
main → parse_plan → init_progress → main_loop
  find_next_phase → execute_phase → verify_phase → refactor_phase → update_phase_status → write_progress
  no-changes:  signal file (.claudeloop/signals/phase-N.md) + successful session → skip verification → complete
  on failure:  should_retry_phase → retry_strategy → calculate_backoff → sleep → retry (standard/stripped/targeted)
  on Ctrl+C:   handle_interrupt → rollback refactor (if active) → write_progress (skip recorder) → fork recorder bg → save_state → exit 130
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
- `/wt create|rm|list` — Manage git worktrees for parallel Claude Code sessions

**Skill-first routing (mandatory):** When the user requests an operation that matches a defined skill (release, rebase, verify, etc.), always invoke the skill — never perform the equivalent operation manually. Compound requests like "promote and release" must decompose into skill invocations (`/rebase promote` then `/release stable`), not ad-hoc commands.

## Worktree workflow

When inside a worktree (`git rev-parse --show-toplevel` points to a `*-wt-*` directory or branch matches `wt/*`):

- **Scope awareness**: Worktree is an isolated copy. Changes don't affect the main repo until merged.
- **Branch convention**: Worktree branches are `wt/<name>`. Do not rename.
- **Commit normally**: Conventional commits, push with `git push -u origin wt/<name>`.
- **PR target**: PRs target the base branch the worktree was created from.
- **Cleanup**: Use `/wt rm <name>` from the main repo, not from inside the worktree.
- **CWD isolation (mandatory):** Never `cd` outside the worktree in Bash commands for git write operations (`cherry-pick`, `rebase`, `checkout`, `merge`). These can invalidate the worktree path, permanently breaking all subsequent Bash calls. Use `git -C <path>` for read-only queries if needed.
- **Landing worktree changes:** Push the branch and create a PR targeting the desired base branch. Never cherry-pick or rebase manually from inside a worktree. `/wt rm` offers integrated "PR then remove".
- **Broken cwd recovery (mandatory):** If Bash commands fail with "Path does not exist" or similar cwd errors, the worktree directory was removed externally. Do NOT retry Bash commands — they will all fail. Immediately call `ExitWorktree` to restore the session's working directory.

**VS Code integration (mandatory):**
- **On worktree enter:** After `EnterWorktree` or `/wt create`, add the worktree to the active VS Code workspace:
  ```sh
  VSCODE_CLI="$(find /Applications -name 'code' -path '*/bin/*' 2>/dev/null | head -1)"
  [ -n "$VSCODE_CLI" ] && "$VSCODE_CLI" --add <worktree-path>
  ```
- **On worktree cleanup:** Before `ExitWorktree` or `/wt rm`, remove the worktree from the VS Code workspace:
  ```sh
  [ -n "$VSCODE_CLI" ] && "$VSCODE_CLI" --remove <worktree-path>
  ```
- Fail silently if VS Code CLI is not found (non-blocking).

## Testing

Each lib has a corresponding `tests/test_<lib>.sh`.

### TDD workflow (mandatory)

1. **Write failing tests first** — add tests to the relevant `tests/test_<lib>.sh` before touching implementation
2. **Verify tests fail** — `bats tests/test_<lib>.sh` must show the new tests as `not ok`
3. **Implement** — make the minimal change to pass the tests
4. **Verify tests pass** — `bats tests/test_<lib>.sh` must show all tests as `ok`
5. **Run full suite** — `./tests/run_all_tests.sh` must pass (excluding pre-existing failures)

When modifying existing behavior, update affected tests before changing implementation code.

**Reproduce before fixing (mandatory):** When fixing a bug, reproduce it first using existing test infrastructure (fake CLI, bats fixtures, `--replay`). If the infrastructure can't reproduce the scenario, extend it. Code tracing alone is insufficient — verify the fix works end-to-end.

**Use project tools for test data (mandatory):** When generating test artifacts (PROGRESS.md, raw.json, replay.html), run the actual execution pipeline (claudeloop with fake_claude, smoke tests) instead of hand-crafting files. Hand-crafted files easily get formats wrong; the project's own tools are the source of truth.

Pre-existing failing suites are mandatory to fix when found.

### Completion gate (mandatory)

After all implementation and tests pass, run `/verify` before reporting the task as done. The verify skill selects appropriate checks (smoke, stub, GUI) based on which files changed. Skip only for documentation-only or test-only changes with no implementation modifications.

When adding runtime files (libraries, templates, assets), verify they are included in the release tarball (`.github/workflows/release.yml`), installer (`install.sh`), and installer tests (`tests/test_install.sh`).

If the change affects terminal output, also regenerate visual assets (`assets/README.md`) before reporting done.

### Autonomous verification (mandatory)

Never suggest the user test something manually when you can do it yourself. If you can generate test data, open a browser, inject test scripts, and screenshot results — do it without asking. Verification is your job, not the user's. This applies to all verification, not just `/verify`.
