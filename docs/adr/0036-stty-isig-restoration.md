# 36. Restore terminal ISIG after Claude CLI pipeline

**Date:** 2026-03-27
**Status:** Accepted

## Context

Ctrl+C completely fails to stop claudeloop during phase execution. The only way to exit is killing the terminal.

The Claude Code CLI uses Ink (React for CLI) which calls `process.stdin.setRawMode(true)`. Node.js translates this to libuv's `uv_tty_set_mode()` → `cfmakeraw()`, which clears the terminal's `ISIG` flag. Terminal line discipline settings are a kernel-level property of the TTY device — when any process clears `ISIG` on `/dev/tty`, **all processes** on that terminal lose Ctrl+C signal generation. Even though `claude --print` receives stdin from a pipe, it can still open `/dev/tty` directly.

Multiple Claude Code issues confirm this behavior:
- anthropics/claude-code#17724: "Terminal is in raw mode (-isig). Ctrl+C doesn't generate SIGINT"
- anthropics/claude-code#12483: Terminal state corruption after Ctrl+Z
- anthropics/claude-code#18880: Ctrl+C unresponsive during tool execution

## Decision

Three defensive measures, applied together:

1. **`_restore_isig`**: Call `stty isig < /dev/tty` before each `sleep` in sentinel polling loops (execution.sh, verify.sh). Re-enables SIGINT generation every poll interval (~1s). Small race window where Ctrl+C might not work if claude just disabled ISIG, but repeated Ctrl+C works within the next poll.

2. **Full stty save/restore**: Save `stty -g` before starting the pipeline, restore after cleanup. Catches any terminal corruption beyond just ISIG.

3. **`set +e` in `handle_interrupt`**: bash 3.2 does not exempt trap handlers from `set -e`. If any subcommand in the handler fails, `set -e` would silently abort the handler before `exit 130`.

4. **`_safe_disable_jobctl`**: Re-arm `trap handle_interrupt INT TERM` after each `set +m`. Defensive insurance against bash 3.2 edge cases with signal disposition after toggling job control.

## Consequences

**Positive:**
- Ctrl+C works reliably during phase execution and verification
- Graceful degradation: all stty operations fail silently without a TTY (pipes, CI)
- Zero overhead: `stty isig` is a single `ioctl` syscall
- Terminal settings are always restored after pipeline, even on normal completion

**Negative:**
- Race window of up to 1 second where Ctrl+C might not work (between claude disabling ISIG and the next poll restoring it)
- Adds 1 `stty` call per poll iteration (~1/second) — negligible performance impact
- Does not fix the root cause in the Claude CLI itself
