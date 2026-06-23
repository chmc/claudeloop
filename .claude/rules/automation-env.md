---
paths:
  - "assets/*.expect"
  - "tests/**"
  - ".verification-sessions/**"
---

# Automation Environment Cleanup

When spawning claudeloop under automation (expect, Terminal.app `do script`, test harnesses):

## Mandatory env var cleanup

- `CLAUDECODE` — triggers `YES_MODE=true` via `orchestration.sh:92`, silently disables all interactive features (sentinel keystroke detection, nudge). No error or warning in the affected code path.
- Check for other mode-switching vars: `YES_MODE`, `SIMPLE_MODE`, `_NUDGE_DISABLED`

## Debugging interactive failures

When `send`/keystroke doesn't reach a `read`: check env vars and mode flags at the receiver's `if` condition FIRST (2 min), before building pty/terminal reproduction harnesses (30 min).

Specific to claudeloop sentinel (`execution.sh:238`):
```sh
if [ -t 0 ] && [ "${YES_MODE:-false}" != "true" ] && [ "${_NUDGE_DISABLED:-}" != "1" ]; then
```
Any of these three guards failing = silent fallback to `sleep` loop, no `/dev/tty` read.
