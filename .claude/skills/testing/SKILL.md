---
name: testing
description: Testing methodology — TDD workflow, pipeline test setup, debugging, test data generation
---

# Testing Methodology

Each lib has a corresponding `tests/test_<lib>.sh`.

## TDD workflow (mandatory)

1. **Write failing tests first** — add tests to the relevant `tests/test_<lib>.sh` before touching implementation
2. **Verify tests fail** — `bats tests/test_<lib>.sh` must show the new tests as `not ok`
3. **Implement** — make the minimal change to pass the tests
4. **Verify tests pass** — `bats tests/test_<lib>.sh` must show all tests as `ok`
5. **Run full suite** — `./tests/run_all_tests.sh` must pass (excluding pre-existing failures)

When modifying existing behavior, update affected tests before changing implementation code.

## Test source dependencies (mandatory)

When adding a dependency to `lib/*.sh`, grep for test files that source that library:

```sh
grep -l "source.*lib/changed_file.sh" tests/*.sh
```

Update each test file's `setup()` to also source any new dependencies that `lib/changed_file.sh` now requires.

## Reproduce before fixing (mandatory)

When fixing a bug, reproduce it first using existing test infrastructure (fake CLI, bats fixtures, `--replay`). If the infrastructure can't reproduce the scenario, extend it. Code tracing alone is insufficient — verify the fix works end-to-end.

## Live debugging for performance

When investigating slow tests, hangs, or unexplained timeouts, prefer process inspection (`lsof`, `ps`) over code tracing as the first step. Check: What FDs are open? What is the process waiting on? Is the sentinel polling or stuck?

## Use project tools for test data (mandatory)

When generating test artifacts (PROGRESS.md, raw.json, replay.html), run the actual execution pipeline (claudeloop with fake_claude, smoke tests) instead of hand-crafting files. Hand-crafted files easily get formats wrong; the project's own tools are the source of truth.

## Pipeline test setup (mandatory)

Tests running full `claudeloop` pipelines must set these env vars in `setup()`:

| Variable | Value | Why |
|----------|-------|-----|
| `_SENTINEL_POLL` | `0.1` | Faster sentinel detection (default 1s) |
| `_SKIP_HEARTBEATS` | `1` | Skip inject_heartbeats read loop (prevents 30-min hangs) |
| `_SENTINEL_MAX_WAIT` | `30` | Safety net: fail fast on hangs (default 1800s) |
| `_KILL_ESCALATE_TIMEOUT` | `1` | Faster pipeline teardown (default 3s) |
| `_CLAUDELOOP_NO_AUTO_ARCHIVE` | `1` | Skip archive prompt at startup |
| `_NUDGE_DISABLED` | `1` | Prevents `read < /dev/tty` hang in non-TTY test context |
| `CLAUDECODE` | unset | Claude Code sets this; forces `YES_MODE=true`, disabling interactive features (nudge). Unset when testing interactive behavior. |

Also set in `.claudeloop.conf`: `BASE_DELAY=0`, `AI_PARSE=false`, `VERIFY_PHASES=false`, `REFACTOR_PHASES=false` (unless testing those features).

Copy from `test_integration_basic.sh` as the reference implementation.

## Pre-existing failures

Pre-existing failing suites are mandatory to fix when found.
