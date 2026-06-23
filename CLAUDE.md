## Behavioral Guidelines

- Think before coding. State your assumptions out loud. If the request is ambiguous, ask. If a simpler approach exists, push back. Stop when you are confused, name what is unclear, do not just pick one interpretation and run.
- Simplicity first. Write the minimum code that solves the problem. No speculative abstractions. No flexibility nobody asked for. The test: would a senior engineer call this overcomplicated.
- Surgical changes. Touch only what the task requires. Do not improve neighboring code. Do not refactor what is not broken. Every changed line should trace back to the request.
- Goal-driven execution. Turn vague instructions into verifiable targets before writing a line. “Add validation” becomes “write tests for invalid inputs, then make them pass.”
- No silent skips. If a requirement is hard or blocked, say so explicitly in your response — name the problem and propose a path forward. Never silently substitute easier work for what was asked. If any requirement is unresolved, report it — not PASS.

## Rules

- Branch awareness: `git branch --show-current` before any work. Flag stable vs beta, ask before changes.
- Skill-first routing: always invoke matching skill, never perform equivalent manually. Compound requests decompose into skill invocations. Use skills end-to-end — never partially use a skill then finish manually (manual steps skip side effects like workspace sync, state updates, cleanup).
- Completion gate (mandatory): run `/verify` before reporting done. Skip for docs/test-only changes.
- Autonomous verification (mandatory): never ask user to test. Do it yourself.
- Continuous improvement: suggest CLAUDE.md/skill/hook changes at natural pause points. Project rules → CLAUDE.md. Workflow rules → skill files. User prefs → memory.
- Post-implementation debrief: after completing a plan, share lessons that would change future approach. Codebase traps, plan-vs-reality gaps, process improvements — not generic observations. Skip if nothing non-obvious was learned. User decides what to persist.
- Plan execution: multi-step plans ("promote → release → sync") = authorization. Only stop on failure.
- Shell dialect: POSIX `#!/bin/sh`. No bashisms. `local` OK (SC3043). All libs sourceable by dash/ash. Contextual guidance in `.claude/rules/` (shell-code, parsers, hooks-and-workflow).
- Enforced workflow: 11 gates block progress until completed. See `docs/WORKFLOW.md` for details. Run `/workflow` for status.
- Task tracking: create tasks (TaskCreate) for each Verification item **before calling ExitPlanMode**. ExitPlanMode is denied until tasks exist. Mark `in_progress` before starting, `completed` when done.

## Planning

- **Plan mode = read-only**: no external changes (API calls, GitHub mutations, file edits) even if user confirms "y". **You MUST call ExitPlanMode before making any edits.** Document changes in plan and wait for approval.
- **Goal persistence (mandatory)**: every plan starts with a `## Goal` section that states the user's full request in their terms, without narrowing, reframing, or omitting sub-requirements. All plan sections must trace back to it. If a section doesn't serve the goal, flag it for review. If something required by the goal is missing, the plan is incomplete. Review the Goal before finalizing.

Exploration must produce a constraints brief:
1. Conventions — patterns, error handling, naming. Cite files+lines.
2. Touch points — every function/variable/file affected. Include signatures+callers. Flag sibling functions (same file, parallel structure, similar callers).
3. Traps — anything surprising (eval vars, set -eu, `_CLAUDELOOP_NO_*` env vars for test isolation).
4. Tests — which test files cover modified functions, with specifics.
5. See [feature docs](docs/FEATURES.md) for product features

Plans: justify every decision from constraints. List files to modify with functions/callers. State what is NOT changing and why.

Multi-angle review (mandatory): always launch 2-3 Plan agents with different critique perspectives. Skip only with explicit justification (`**Skip reason:**` in Critic section — acceptable for trivial/mechanical changes, self-referential workflow changes, or single-function changes with no design ambiguity). Verify causal claims by tracing actual code paths — don't just confirm code exists. After launching critic agents and incorporating their feedback, touch `.claude/workflow-state/critic-reviewed`.

Pre-implementation check (per phase):
1. `git log --oneline -10` — check for prior commits implementing this work
2. If already implemented: verify + fill test coverage gaps
3. When adding library dependencies: update test files that source those libraries

Issue workflow: task references GitHub issue → final plan phase:
1. Close issue: `gh issue close N` after verification passes. Commit with `Closes #N` for auto-close.
2. Update related: if sub-issue or linked to other issues → update parent/related issues appropriately.

## Architecture (TL;DR)

Phase data in flat numbered variables via eval. `phase_to_var "2.5"` → `"2_5"`. Prefer `phase_get`/`phase_set` (`lib/phase_state.sh`).

Three parsers read PROGRESS.md (`lib/progress.sh`, `lib/plan_changes.sh`, `lib/recorder.sh`) — update all three when adding fields.

Packaging triad: `.github/workflows/release.yml` + `install.sh` + `tests/test_install.sh` — keep in sync when adding runtime files.

See `/arch` for full reference (data model, libraries, execution flow, field registry).

## Running Tests

**Full test suite** (5-15 minutes): Use explicit timeout.
```
Bash({
  command: "./tests/run_all_tests.sh",
  timeout: 900000,
  description: "Full test suite"
})
```

**Quick verification** (<2 minutes):
```sh
./tests/smoke.sh              # Smoke tests (~30s)
bats tests/test_<name>.sh     # Single test file
```

**Tag-based testing** (focused verification):
```sh
bats --filter-tags provider tests/
bats --filter-tags integration tests/
```

### What NOT to do
- ❌ `run_in_background: true` — causes retry cascade in claudeloop
- ❌ `./tests/run_all_tests.sh 2>&1` — buffering hides heartbeats
- ❌ `./tests/run_all_tests.sh | tail` — buffering hides progress
- ❌ Default Bash (no timeout) — 120s default too short for full suite

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

Gate files (`.claude/workflow-state/*`) resolve via `CLAUDE_PROJECT_DIR` which may point to the main repo, not the worktree. When using EnterWorktree, create gate files in the main repo's `.claude/workflow-state/` or use `/wt create` worktrees which share the main repo's `.claude/` directory.
