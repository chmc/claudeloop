---
paths:
  - "assets/fake-claude-*"
  - "assets/setup-demo*.sh"
  - "assets/demo-*.tape"
---

# Demo Asset Rules

## Fake-claude stdin pattern

NEVER use `cat > /dev/null` to consume stdin — blocks forever on FIFO (`lib/execution.sh` holds FD 7 open).

USE instead:
```sh
IFS= read -r _discard 2>/dev/null || true  # consume stdin (cat blocks forever on FIFO)
```

Reference: `tests/lib/fake_provider_common.sh:32` uses the same pattern.

## GIF regeneration — mandatory verification

After running VHS tapes, MUST verify content via ffmpeg frame extraction. File size alone is NOT verification — broken GIFs can be large (the original broken GIFs were 55K–500K and showed only spinners).

```sh
# Extract frames at 25%, 50%, 75% of duration
dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 demo.gif)
ffmpeg -ss $(echo "$dur * 0.25" | bc) -i demo.gif -vframes 1 /tmp/frame-25.png -y
ffmpeg -ss $(echo "$dur * 0.50" | bc) -i demo.gif -vframes 1 /tmp/frame-50.png -y
ffmpeg -ss $(echo "$dur * 0.75" | bc) -i demo.gif -vframes 1 /tmp/frame-75.png -y
```

View each with the Read tool. Check against `assets/demo-<name>.verify`.

## Gifsicle compression (per-GIF settings)

```sh
# All except execution:
gifsicle --optimize=3 --lossy=80 -o demo.gif demo.gif
# Execution only (more frames, larger):
gifsicle --optimize=3 --lossy=120 --colors 64 -o demo-execution.gif demo-execution.gif
```

## CLAUDECODE env var trap

When running claudeloop under `expect` (e.g. nudge demo), `CLAUDECODE` env var is inherited from the Claude Code session. This triggers `orchestration.sh:92` → `YES_MODE=true` → sentinel skips `/dev/tty` read entirely → interactive features (nudge, sentinel keystrokes) silently stop working.

Fix: `catch {unset env(CLAUDECODE)}` at the top of expect scripts. Use `catch` because outside Claude Code the var doesn't exist and bare `unset` crashes expect.

## VHS tape changes

- Test by running VHS once and extracting frames BEFORE regenerating all 6 GIFs
- Configs set `SKIP_PERMISSIONS=true` and `AI_PARSE=false` — `-y` flag is usually not needed
- Adjust Sleep values if output is cut off or shows excess idle time
- VHS stops recording when the shell command exits (GIF may be shorter than total Sleep sum)
