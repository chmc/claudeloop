# CLAUDE.md

## Rules

- Branch awareness: `git branch --show-current` before any work. Flag stable vs beta, ask before changes.
- Skill-first routing: always invoke matching skill, never perform equivalent manually. Compound requests decompose into skill invocations.
- Completion gate (mandatory): run `/verify` before reporting done. Skip for docs/test-only changes.
- Autonomous verification (mandatory): never ask user to test. Do it yourself.
- Continuous improvement: suggest CLAUDE.md/skill/hook changes at natural pause points. Project rules → CLAUDE.md. Workflow rules → skill files. User prefs → memory.
- Plan execution: multi-step plans ("promote → release → sync") = authorization. Only stop on failure.
- Shell dialect: POSIX `#!/bin/sh`. No bashisms. `local` OK (SC3043). All libs sourceable by dash/ash.
- Enforced workflow: 11 gates block progress until completed. See `docs/WORKFLOW.md` for details. Run `/workflow` for status.

## Planning

- Plan mode = read-only: no external changes (API calls, GitHub mutations, file edits) even if user confirms "y". Exit plan mode first, or document in plan and wait for approval.

Exploration must produce a constraints brief:
1. Conventions — patterns, error handling, naming. Cite files+lines.
2. Touch points — every function/variable/file affected. Include signatures+callers.
3. Traps — anything surprising (eval vars, set -eu, `_CLAUDELOOP_NO_*` env vars for test isolation).
4. Tests — which test files cover modified functions, with specifics.

Plans: justify every decision from constraints. List files to modify with functions/callers. State what is NOT changing and why.

Multi-angle review (mandatory): always launch 2-3 Plan agents with different critique perspectives. Never skip. Verify causal claims by tracing actual code paths — don't just confirm code exists.

## Architecture (TL;DR)

Phase data in flat numbered variables via eval. `phase_to_var "2.5"` → `"2_5"`. Prefer `phase_get`/`phase_set` (`lib/phase_state.sh`).

Three parsers read PROGRESS.md (`lib/progress.sh`, `lib/plan_changes.sh`, `lib/recorder.sh`) — update all three when adding fields.

Packaging triad: `.github/workflows/release.yml` + `install.sh` + `tests/test_install.sh` — keep in sync when adding runtime files.

See `/arch` for full reference (data model, libraries, execution flow, field registry).

## Running Tests (CRITICAL)

**NEVER** use redirects or pipes when running the test suite:
- ❌ `./tests/run_all_tests.sh 2>&1` — WRONG, causes 180s timeout
- ❌ `./tests/run_all_tests.sh | tail` — WRONG, causes 180s timeout
- ❌ `./tests/run_all_tests.sh 2>&1 | head` — WRONG, causes 180s timeout
- ✅ `./tests/run_all_tests.sh` — CORRECT, exactly this, nothing else

Why: Heartbeats go to stderr. Any redirect (`2>&1`) merges them into buffered stdout, hiding progress from Claude Code and triggering "connection dead" warnings.

**For full test suite**: Use Bash tool with `run_in_background: true`. You'll be notified when complete, then read the output file for results. This avoids the 180s timeout entirely.

## Testing traps

- TDD (mandatory): write failing tests first, verify fail, implement, verify pass, run suite. See `/testing`.
- Reproduce bugs with test infrastructure (fake_claude, bats) before fixing. Code tracing alone is insufficient.
- Pipeline tests must set `_SKIP_HEARTBEATS=1`, `_SENTINEL_MAX_WAIT=30`, `_SENTINEL_POLL=0.1`, `_KILL_ESCALATE_TIMEOUT=1` in `setup()`. Copy from `test_integration_basic.sh`. Missing these = 30-min hangs.
- Visual assets: regenerate VHS tapes when terminal output changes (`assets/README.md`).

## Documentation

Update README.md/QUICKSTART.md when user-facing behavior changes.

ADR: `docs/adr/NNNN-slug.md` for architectural decisions (new pattern, technology choice, significant design change). Use `docs/adr/TEMPLATE.md`, update `docs/adr/README.md`.

## Commands

```sh
./tests/run_all_tests.sh              # all tests (throttled, shows timing)
bats tests/test_parser.sh             # single file
shellcheck -s sh lib/retry.sh         # lint (SC3043 OK)
./claudeloop --plan PLAN.md --dry-run # dry run
./tests/smoke.sh                      # smoke test
./tests/mutate.sh                     # mutation testing
```

## Skills

- `/github` — commit, push, PR conventions
- `/rebase sync|promote` — branch rebasing
- `/release beta|stable` — GitHub release workflow
- `/verify` — post-change verification (smoke + GUI)
- `/wt create|rm|list` — git worktrees
- `/testing` — invoke BEFORE writing/modifying tests (TDD workflow, pipeline setup, debugging)
- `/arch` — invoke BEFORE modifying packaging, progress parsers, or execution flow

## Worktree

When inside a worktree: never `cd` outside for git writes (breaks cwd permanently). If cwd breaks, call `ExitWorktree` immediately. See `/wt` for full rules.
