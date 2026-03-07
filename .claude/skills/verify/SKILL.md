# /verify — Verification skill

Verify claudeloop works after code changes. Run from the repo root.

## 1. Quick smoke

```sh
./tests/smoke.sh
```

If it fails, stop and fix before proceeding.

## 2. Decision matrix

| Changed files | Verification |
|---|---|
| `lib/parser.sh`, `lib/dependencies.sh` | Smoke sufficient |
| `lib/ui.sh`, `lib/stream_processor.sh` | Smoke + GUI screenshots |
| `lib/retry.sh` | Stub configured to fail/succeed |
| `lib/verify.sh` | Stub with `--verify` |
| `lib/progress.sh` | Stub, read PROGRESS.md |
| `claudeloop` | Depends on area — check matrix above |

## 3. GUI screenshot protocol

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

# 2. Take screenshot(s)
screencapture -l "$WINDOW_ID" /tmp/cl-verify-1.png
# For spinners: take multiple at 1-2s intervals
# sleep 2 && screencapture -l "$WINDOW_ID" /tmp/cl-verify-2.png

# 3. Read screenshots with Read tool to verify:
#    - Logo, header formatting, phase icons
#    - Spinner behavior (compare multiple captures)
#    - Scrollback integrity (no duplicate/overwritten lines)
#    - Final summary correct

# 4. Cleanup
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null
rm -f /tmp/cl-verify*.png
```

## 4. Stub execution for logic verification

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

# Run
(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$PWD/claudeloop" --plan PLAN.md -y)

# Inspect results
cat "$tmpdir/.claudeloop/PROGRESS.md"
ls "$tmpdir/.claudeloop/logs/"

# Cleanup
rm -rf "$tmpdir"
```

Pattern from `tests/test_integration.sh` — see `_write_claude_stub()` for configurable exit codes.

## 5. Live execution (real Claude)

Same GUI screenshot pattern but without the stub:

```sh
WINDOW_ID=$(osascript -e 'tell application "Terminal"
    activate
    do script "'"$PWD"'/claudeloop --plan '"$PWD"'/tests/fixtures/smoke-plans/single-phase.md --dangerously-skip-permissions --max-retries 1 --idle-timeout 60 -y"
    delay 5
    return id of front window
end tell')

# Monitor with multiple screenshots during execution
screencapture -l "$WINDOW_ID" /tmp/cl-verify-1.png
sleep 10
screencapture -l "$WINDOW_ID" /tmp/cl-verify-2.png
# Read both screenshots to verify progress
```

## 6. Cleanup

Always clean up after verification:

```sh
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null
rm -f /tmp/cl-verify*.png
rm -rf "$tmpdir"
```
