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

## Must-Verify
<!-- Write BEFORE running anything. Primary success criteria for this specific change. -->
- [ ] <what the change does, with expected observable values>
- [ ] <what was removed — confirm absence>
- [ ] <what should NOT happen anymore>
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
| **UI / display / stream processing** | Terminal output, colors, spinners, progress display, live log | GUI + stub (Terminal.app with fake_claude `success_verbose`) | Logo, header, spinners, colors, phase icons, scrollback integrity, todo/task summaries, session summaries with cache tokens + regenerate demo GIFs (`assets/README.md`) |
| **Retry / error handling** | Backoff, retry logic, quota handling, failure detection | Stub with configured failures | Retry messages, backoff timing, error display |
| **Verification logic** | Post-phase verification, verdict parsing | Stub with `--verify` | Verification verdict output, pass/fail display |
| **State / progress** | Progress tracking, resume, state persistence | Stub execution | PROGRESS.md content + progress display during run |
| **Monitor / live log** | Live log output, `--monitor` mode | Stub + `--monitor` in 2nd terminal | live.log updates, real-time streaming |
| **Plan changes / resume** | Plan change detection, orphan recovery | Stub with pre-existing PROGRESS.md | Orphan detection, progress recovery |
| **Orchestration / main loop** | Arg parsing, execution flow, lock files, config | Depends on area — pick from above | At minimum: `--dry-run` output + stub run observation |
| **Replay / HTML template** | replay-template.html, recorder.sh, recorder_parsers.sh, recorder_overview.sh | Browser JS test (generate replay.html → inject assertions → open Safari → screenshot) | Sidebar state, phase rendering, expand/collapse, time travel, tool display |

**Priority rule:** Multiple matches → use most demanding mode: GUI > stub+failures > stub > dry-run.

Key principles:
- Map changed files to categories (no hardcoded file paths in the matrix)
- Every row specifies both what to run AND what to look for
- No "sufficient" exit ramps — every path ends with observation

### Mandatory GUI rule

GUI screenshot verification is **required** when any of these files are changed or moved (including pure refactors, code moves, source order changes):
- `lib/execution.sh` (`run_claude_pipeline`, `execute_phase`)
- `lib/stream_processor.sh` (`process_stream_json`, `inject_heartbeats`)
- `lib/ui.sh` (display functions)
- `lib/verify.sh` (`verify_phase` — runs its own pipeline)

Reason: Bash tool cannot render TTY output (spinners, cursor movement, ANSI, sticky panels).

### Mandatory browser test rule

Browser JS test verification is **required** when `assets/replay-template.html` is changed (JS logic, CSS, or HTML structure). Reason: unit tests in `test_recorder.sh` validate data assembly and HTML generation, but cannot exercise interactive JS behavior (DOM state, event handlers, CSS class toggling).

### fake_claude scenarios

See scenario list and env vars in `tests/fake_claude` header (lines 1–16).

Log which category/path was chosen in the README.

## Step 3: Execute verification

### Common stub setup

All execution modes below share this preamble. Write it once, then add mode-specific lines after.

```sh
orig_dir="$PWD"
tmpdir=$(mktemp -d)
git -C "$tmpdir" init -q && git -C "$tmpdir" config user.email "test@test.com" && git -C "$tmpdir" config user.name "Test"
mkdir -p "$tmpdir/bin" "$tmpdir/.claudeloop"
cp tests/fake_claude "$tmpdir/bin/claude" && chmod +x "$tmpdir/bin/claude"
export FAKE_CLAUDE_DIR="$tmpdir"
printf 'BASE_DELAY=0\n' > "$tmpdir/.claudeloop/.claudeloop.conf"
cp tests/fixtures/smoke-plans/two-phase-deps.md "$tmpdir/PLAN.md"
git -C "$tmpdir" add PLAN.md && git -C "$tmpdir" commit -q -m "init"
```

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

After common stub setup, add:

```sh
# GUI-specific setup
printf 'success_verbose\n' > "$tmpdir/scenario"

# Sleeps tuned for success_verbose + FAKE_CLAUDE_THINK=2 (~30s total)

# Open Terminal.app with stub, get window ID
WINDOW_ID=$(osascript -e 'tell application "Terminal"
    activate
    do script "export FAKE_CLAUDE_THINK=2 && export FAKE_CLAUDE_DIR='"$tmpdir"' && cd '"$tmpdir"' && PATH='"$tmpdir"'/bin:$PATH '"$orig_dir"'/claudeloop --plan PLAN.md -y"
    delay 1
    return id of front window
end tell')

# Phase-aware screenshots at key moments
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-1-header.png"
sleep 8
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-2-phase1-mid.png"
sleep 8
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-3-transition.png"
sleep 6
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-4-phase2-mid.png"
sleep 12
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-5-final.png"

# Scroll to top to capture logo if it scrolled off
osascript -e 'tell application "System Events" to key code 115' 2>/dev/null
sleep 0.5
screencapture -l "$WINDOW_ID" "$SESSION/screenshot-6-scrolltop.png"

# Read ALL screenshots with Read tool and verify against checklist below

# Close Terminal window and clean up
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null
rm -rf "$tmpdir"
```

#### Screenshot verification checklist

Regression checklist for UI changes. Your must-verify assertions (from Step 0) are the primary success criteria.

- [ ] Logo + version + plan name
- [ ] Phase listing with pending icons
- [ ] Spinner: `<spinner> <elapsed>s Todo <done>/<total>`
- [ ] Cyan tools, green todos, blue headers
- [ ] Phase N→N+1 transition, spinner/timer reset
- [ ] No duplicated/overwritten lines across captures
- [ ] Final banner: "All phases completed" + session summary (model, cost, duration, tokens, cache)

If any capture point was missed (e.g., timing was off), note the gap and either re-run with adjusted timing or explain why it's acceptable.

### Stub execution for logic verification

For non-UI changes, run claudeloop with fake_claude directly from the Bash tool. After common stub setup, add:

```sh
printf 'success_verbose\n' > "$tmpdir/scenario"

# Run and capture output
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$orig_dir/claudeloop" --plan PLAN.md -y) 2>&1 | tee "$SESSION/stub-run.log"

# Copy PROGRESS.md from stub run
cp "$tmpdir/.claudeloop/PROGRESS.md" "$SESSION/PROGRESS.md" 2>/dev/null

rm -rf "$tmpdir"
```

### Stub execution with configured failures

For retry/error-handling changes. After common stub setup, add:

```sh
# Per-call scenarios: first call fails, second succeeds (per phase)
printf 'failure\nsuccess_multi\nfailure\nsuccess_multi\n' > "$tmpdir/scenarios"
printf 'BASE_DELAY=2\n' > "$tmpdir/.claudeloop/.claudeloop.conf"  # override for observable timing

# Run and capture output
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$orig_dir/claudeloop" --plan PLAN.md -y) 2>&1 | tee "$SESSION/stub-failure-run.log"

# Inspect retry prompts for correct context
ls "$tmpdir/prompts/" 2>/dev/null | tee "$SESSION/prompt-files.log"
for f in "$tmpdir/prompts/"*; do cat "$f"; echo "---"; done > "$SESSION/prompt-contents.log" 2>/dev/null

cp "$tmpdir/.claudeloop/PROGRESS.md" "$SESSION/PROGRESS.md" 2>/dev/null
rm -rf "$tmpdir"
```

After running, verify:
- [ ] Each phase fails once then succeeds on retry
- [ ] Retry delay matches `BASE_DELAY` (not exponential)
- [ ] Retry prompts contain error context from the failure
- [ ] Final result: all phases completed

### Browser JS test protocol

For Replay / HTML template changes. Generate a replay file, inject test assertions, and screenshot the result.

```sh
# 1. Load browser test fixtures (baseline — extend or replace to match the specific change)
tmpdir=$(mktemp -d)
run_dir="$tmpdir/.claudeloop"
mkdir -p "$run_dir/logs" "$run_dir/signals"
cp -r tests/fixtures/verify-browser/* "$run_dir/"

# 2. Generate replay HTML via recorder libs (POSIX sh, not zsh)
orig_dir="$PWD"
CLAUDELOOP_DIR="$orig_dir" sh -c '
  . "$CLAUDELOOP_DIR/lib/parser.sh"
  . "$CLAUDELOOP_DIR/lib/recorder.sh"
  generate_replay "'"$run_dir"'"
'

# 3. Verify embedded JSON with python3
python3 -c "
import re, json, sys
html = open('$run_dir/replay.html').read()
m = re.search(r'const DATA = ({.*?});', html, re.DOTALL)
if not m:
    print('FAIL: no DATA found'); sys.exit(1)
data = json.loads(m.group(1))
phases = data.get('phases', [])
print(f'Phases: {len(phases)}')
for p in phases:
    print(f'  {p[\"title\"]}: status={p[\"status\"]}, attempts={len(p.get(\"attempts\", []))}')
assert len(phases) == 4, f'Expected 4 phases, got {len(phases)}'
print('JSON verification: PASS')
"

# 4. Inject assertion script before </body>
#    IMPORTANT: Tailor assertions to the specific change being verified.
#    Generic "elements exist" checks are insufficient — assert the behavior that changed.
python3 -c "
html = open('$run_dir/replay.html').read()
# Example assertions — REPLACE with assertions specific to the change under test
test_script = '''
<script>
window.addEventListener('load', function() {
  var overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;top:10px;right:10px;background:#000;color:#fff;padding:20px;z-index:99999;font-family:monospace;border-radius:8px;max-width:400px;font-size:14px;';
  var results = [];
  function assert(name, condition) {
    results.push((condition ? 'PASS' : 'FAIL') + ': ' + name);
  }

  // --- Replace these with change-specific assertions ---
  var sidebarItems = document.querySelectorAll('.phase-item.overview-item');
  assert('Sidebar nav items exist', sidebarItems.length >= 3);

  var ttNav = Array.from(sidebarItems).find(function(el) {
    return el.textContent.indexOf('Time Travel') !== -1;
  });
  assert('Time Travel nav exists', !!ttNav);

  var phaseItems = document.querySelectorAll('.phase-item:not(.overview-item)');
  assert('Phase items rendered', phaseItems.length >= 1);
  // --- End assertions ---

  var allPass = results.every(function(r) { return r.startsWith('PASS'); });
  overlay.innerHTML = '<strong style=\"font-size:18px;\">' + (allPass ? '✅ ALL PASS' : '❌ FAILURES') + '</strong><br><br>' + results.join('<br>');
  overlay.style.borderColor = allPass ? '#0f0' : '#f00';
  overlay.style.borderWidth = '2px';
  overlay.style.borderStyle = 'solid';
  document.body.appendChild(overlay);
});
</script>
'''
html = html.replace('</body>', test_script + '</body>')
open('$run_dir/replay.html', 'w').write(html)
print('Assertions injected')
"

# 5. Open in Safari, screenshot, read with Read tool
open -a Safari "$run_dir/replay.html"
sleep 3
screencapture -x "$SESSION/screenshot-browser-test.png"

# 6. Close Safari tab and clean up
osascript -e 'tell application "Safari" to close current tab of front window' 2>/dev/null
rm -rf "$tmpdir"
```

**Key traps:**
- Safari `do JavaScript` requires developer settings — always use the HTML injection approach instead
- PROGRESS.md emoji prefixes (`✅`/`❌`) in phase headers are parsed by `is_progress_phase_header`, not decorative — include them in fixtures
- Must use `sh -c` not `zsh` for recorder sourcing (POSIX project)
- Assertions must be tailored to the specific change — generic "elements exist" checks are insufficient
- `.raw.json` files must exist for each phase or the recorder will skip session extraction
- `lib/recorder.sh` depends on `lib/parser.sh` for `phase_to_var`, `is_progress_phase_header` etc. — always source parser.sh first in standalone contexts
- `generate_replay` takes ONE argument (`$run_dir`) and writes to `$run_dir/replay.html` — do not pass an output path

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
