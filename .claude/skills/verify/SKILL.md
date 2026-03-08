# /verify — Verification skill

Verify claudeloop works after code changes by **observing it run**. Automated tests catch crashes; this skill catches everything else.

Every verification run creates a **session folder** under `.verification-sessions/` that serves as a persistent audit trail.

## Step 0: Create session

```sh
BRANCH=$(git branch --show-current)
GIT_SHA=$(git rev-parse --short HEAD)
CONTEXT="<kebab-case-slug-describing-what-changed>"  # max ~40 chars
SESSION=".verification-sessions/$(date +%Y%m%d-%H%M%S)-${BRANCH}-${CONTEXT}"
mkdir -p "$SESSION"
```

Write initial `$SESSION/README.md` with YAML frontmatter:

```markdown
---
date: <ISO 8601 timestamp>
git_sha: <short sha>
branch: <branch>
result: TBD
changed_files: [<list from git diff --stat>]
---

# Verification: <context>

## Trigger
<what change prompted this, one sentence>

## Changed Files
<git diff --stat output>
```

## Step 1: Smoke gate

```sh
./tests/smoke.sh 2>&1 | tee "$SESSION/smoke.log"
```

If smoke fails, stop and fix before proceeding. Smoke passing does NOT complete verification — proceed to observation.

## Step 2: Observation Focus Matrix

Map changed files to functional categories. Pick the row(s) that match, then follow the specified execution mode and observation targets.

| Category | Examples | Execution mode | What to observe |
|---|---|---|---|
| **Plan parsing / dependencies** | Parser, dependency resolver, plan validation | `--dry-run` + stub execution | Phase ordering, dependency display, parsed plan output |
| **UI / display / stream processing** | Terminal output, colors, spinners, progress display, live log | GUI + stub (Terminal.app with fake_claude `success_verbose`) | Logo, header, spinners, colors, phase icons, scrollback integrity, todo/task summaries, session summaries with cache tokens |
| **Retry / error handling** | Backoff, retry logic, quota handling, failure detection | Stub with configured failures | Retry messages, backoff timing, error display |
| **Verification logic** | Post-phase verification, verdict parsing | Stub with `--verify` | Verification verdict output, pass/fail display |
| **State / progress** | Progress tracking, resume, state persistence | Stub execution | PROGRESS.md content + progress display during run |
| **Orchestration / main loop** | Arg parsing, execution flow, lock files, config | Depends on area — pick from above | At minimum: `--dry-run` output + stub run observation |

Key principles:
- Map changed files to categories (no hardcoded file paths in the matrix)
- Every row specifies both what to run AND what to look for
- No "sufficient" exit ramps — every path ends with observation

### fake_claude scenario reference

Map verification goals to `tests/fake_claude` scenarios and env vars:

| Goal | Scenario | Env vars | Notes |
|------|----------|----------|-------|
| Full UI (spinners, todos, tasks, cache) | `success_verbose` | `FAKE_CLAUDE_THINK=2` for GUI | 14 tool calls, 35+ JSON lines |
| Basic tool flow | `success_multi` | — | Read/Edit/Bash, fast |
| Retry behavior | `failure` → `success_multi` | — | Use per-call `scenarios` file |
| Verification flow | `verify_pass` / `verify_fail` | — | Tests verdict parsing |
| Rate limiting | `rate_limit` | — | Shows `[Rate limit: N%]` |
| Quota exhaustion | `quota_error` → `success_multi` | — | Tests quota recovery |
| Long-running (timeout) | `slow` | `FAKE_CLAUDE_SLEEP=N` | |

Log which category/path was chosen in the README.

## Step 3: Execute verification

### `--dry-run` observation

Lightweight baseline for parsing/dependency changes:

```sh
./claudeloop --plan tests/fixtures/smoke-plans/two-phase-deps.md --dry-run 2>&1 | tee "$SESSION/dry-run.log"
```

Read the output. Describe what you saw (phase ordering, dependency resolution, parsed structure).

### GUI screenshot protocol

**Prerequisite:** macOS Screen Recording permission must be granted for `screencapture` (one-time system prompt on first use).

For UI changes (spinners, colors, formatting), use Terminal.app screenshots to see what users actually see. The Bash tool captures raw bytes, not rendered terminal output.

Use **absolute paths** — Terminal.app's `do script` opens in `~`.

#### GUI + stub (primary — for UI and stream processor changes)

This is the most valuable verification mode. It exercises the full stream processor pipeline with realistic Claude output in a real TTY, catching bugs that the Bash tool cannot see (TTY prompts, ANSI rendering, spinner timing).

```sh
# 1. Prepare stub environment
tmpdir=$(mktemp -d)
git -C "$tmpdir" init -q
git -C "$tmpdir" config user.email "test@test.com"
git -C "$tmpdir" config user.name "Test"
cp tests/fake_claude "$tmpdir/bin/claude"
chmod +x "$tmpdir/bin/claude"
export FAKE_CLAUDE_DIR="$tmpdir"
printf 'success_verbose\n' > "$tmpdir/scenario"
mkdir -p "$tmpdir/.claudeloop"
printf 'BASE_DELAY=0\nMAX_DELAY=0\n' > "$tmpdir/.claudeloop/.claudeloop.conf"
cp tests/fixtures/smoke-plans/two-phase-deps.md "$tmpdir/PLAN.md"
git -C "$tmpdir" add PLAN.md && git -C "$tmpdir" commit -q -m "init"

# 2. Open Terminal.app with stub, get window ID
#    FAKE_CLAUDE_THINK=2 adds delay so spinners are visible in screenshots
WINDOW_ID=$(osascript -e 'tell application "Terminal"
    activate
    do script "export FAKE_CLAUDE_THINK=2 && export FAKE_CLAUDE_DIR='"$tmpdir"' && cd '"$tmpdir"' && PATH='"$tmpdir"'/bin:$PATH '"$PWD"'/claudeloop --plan PLAN.md -y"
    delay 3
    return id of front window
end tell')

# 3. Take screenshot(s) — saved to session folder
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-1.png"
# For spinners/progress: take multiple at intervals
# sleep 2 && screencapture -l "$WINDOW_ID" "$SESSION/screenshot-2.png"

# 4. Read screenshots with Read tool to verify:
#    - Logo, header formatting, phase icons
#    - Spinner behavior (compare multiple captures)
#    - Todo/Task summaries, session summary with cache tokens
#    - Scrollback integrity (no duplicate/overwritten lines)
#    - Final summary correct

# 5. Close Terminal window
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null
rm -rf "$tmpdir"
```

#### GUI + dry-run (secondary — for parser changes)

When changes only affect plan parsing or dependency resolution, `--dry-run` is sufficient:

```sh
WINDOW_ID=$(osascript -e 'tell application "Terminal"
    activate
    do script "'"$PWD"'/claudeloop --plan '"$PWD"'/tests/fixtures/smoke-plans/two-phase-deps.md --dry-run"
    delay 3
    return id of front window
end tell')

screencapture -l "$WINDOW_ID" "$SESSION/screenshot-1.png"

osascript -e 'tell application "Terminal" to close front window' 2>/dev/null
```

### Stub execution for logic verification

For non-UI changes, run claudeloop with fake_claude directly from the Bash tool. Use `success_verbose` for full stream processor exercise, `success_multi` for fast basic flow:

```sh
tmpdir=$(mktemp -d)
git -C "$tmpdir" init -q
git -C "$tmpdir" config user.email "test@test.com"
git -C "$tmpdir" config user.name "Test"

# Copy fake_claude as stub (realistic stream-json output)
cp tests/fake_claude "$tmpdir/bin/claude"
chmod +x "$tmpdir/bin/claude"
export FAKE_CLAUDE_DIR="$tmpdir"
# success_verbose: full UI with todos, tasks, cache (14 tool calls)
# success_multi: basic Read/Edit/Bash flow (fast)
printf 'success_verbose\n' > "$tmpdir/scenario"

# Zero-delay config
mkdir -p "$tmpdir/.claudeloop"
printf 'BASE_DELAY=0\nMAX_DELAY=0\n' > "$tmpdir/.claudeloop/.claudeloop.conf"

# Copy plan and commit
cp tests/fixtures/smoke-plans/two-phase-deps.md "$tmpdir/PLAN.md"
git -C "$tmpdir" add PLAN.md && git -C "$tmpdir" commit -q -m "init"

# Run and capture output
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$PWD/claudeloop" --plan PLAN.md -y) 2>&1 | tee "$SESSION/stub-run.log"

# Copy PROGRESS.md from stub run
cp "$tmpdir/.claudeloop/PROGRESS.md" "$SESSION/PROGRESS.md" 2>/dev/null

# Cleanup tmpdir (session artifacts already saved)
rm -rf "$tmpdir"
```

### Live execution (real Claude)

Same GUI screenshot pattern but without the stub:

```sh
WINDOW_ID=$(osascript -e 'tell application "Terminal"
    activate
    do script "'"$PWD"'/claudeloop --plan '"$PWD"'/tests/fixtures/smoke-plans/single-phase.md --dangerously-skip-permissions --max-retries 1 --idle-timeout 60 -y"
    delay 5
    return id of front window
end tell')

# Monitor with multiple screenshots during execution
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-1.png"
sleep 10
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-2.png"
# Read both screenshots to verify progress

# Close Terminal window when done
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null
```

## Step 4: Record observation and investigate

Write to `$SESSION/README.md` incrementally:

```markdown
## Observation
<!-- MANDATORY: Describe what you saw when claudeloop ran. Reference screenshots or log files. "None" is not valid. -->

## Investigations
<what was checked, observations, anomalies>

## Issues Found
<problems discovered, or "None">

## Fixes Applied
<what was fixed, file paths, descriptions — or "None">
```

The **Observation** section is mandatory and must describe what the verifier actually saw — command output, screenshot contents, or log file observations. A verification without observation is not a verification.

## Step 5: Finalize

Update `$SESSION/README.md` frontmatter — change `result: TBD` to `result: PASS` or `result: FAIL`.

Write final Result section:

```markdown
## Result
PASS/FAIL — <one-line summary>
```

## Browsing past sessions

Before starting, optionally scan recent sessions in `.verification-sessions/` to check for recurring issues or compare with past results.
