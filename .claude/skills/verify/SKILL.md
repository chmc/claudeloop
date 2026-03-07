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
| **UI / display / stream processing** | Terminal output, colors, spinners, progress display, live log | GUI screenshots (Terminal.app) | Logo, header, spinners, colors, phase icons, scrollback integrity |
| **Retry / error handling** | Backoff, retry logic, quota handling, failure detection | Stub with configured failures | Retry messages, backoff timing, error display |
| **Verification logic** | Post-phase verification, verdict parsing | Stub with `--verify` | Verification verdict output, pass/fail display |
| **State / progress** | Progress tracking, resume, state persistence | Stub execution | PROGRESS.md content + progress display during run |
| **Orchestration / main loop** | Arg parsing, execution flow, lock files, config | Depends on area — pick from above | At minimum: `--dry-run` output + stub run observation |

Key principles:
- Map changed files to categories (no hardcoded file paths in the matrix)
- Every row specifies both what to run AND what to look for
- No "sufficient" exit ramps — every path ends with observation

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

Use **absolute paths** — Terminal.app's `do script` opens in `~`:

```sh
# 1. Open Terminal.app, run claudeloop, get window ID
WINDOW_ID=$(osascript -e 'tell application "Terminal"
    activate
    do script "'"$PWD"'/claudeloop --plan '"$PWD"'/tests/fixtures/smoke-plans/two-phase-deps.md --dry-run"
    delay 3
    return id of front window
end tell')

# 2. Take screenshot(s) — saved to session folder
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-1.png"
# For spinners: take multiple at 1-2s intervals
# sleep 2 && screencapture -l "$WINDOW_ID" "$SESSION/screenshot-2.png"

# 3. Read screenshots with Read tool to verify:
#    - Logo, header formatting, phase icons
#    - Spinner behavior (compare multiple captures)
#    - Scrollback integrity (no duplicate/overwritten lines)
#    - Final summary correct

# 4. Close Terminal window (no file cleanup — artifacts are the audit trail)
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null
```

### Stub execution for logic verification

For non-UI changes, run claudeloop with a stub claude directly from the Bash tool:

```sh
tmpdir=$(mktemp -d)
git -C "$tmpdir" init -q
git -C "$tmpdir" config user.email "test@test.com"
git -C "$tmpdir" config user.name "Test"

# Write stub claude
mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/claude" << 'STUB'
#!/bin/sh
printf 'stub output\n'
printf '{"type":"tool_use","name":"Edit","input":{}}\n'
exit 0
STUB
chmod +x "$tmpdir/bin/claude"

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

Pattern from `tests/test_integration.sh` — see `_write_claude_stub()` for configurable exit codes.

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
