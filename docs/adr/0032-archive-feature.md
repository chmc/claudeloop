# 32. Archive Old Plan Runs

**Date:** 2026-03-16
**Status:** Accepted

## Context

Users running multiple plans in the same project directory have no clean way to save the state of a completed (or abandoned) run before starting a new one. `--reset` clears progress but discards logs. There is no way to review what happened in a previous run.

## Decision

Add an archive system that saves full run state (PROGRESS.md, logs, signals, state) into timestamped directories under `.claudeloop/archive/`. Three new CLI flags (`--archive`, `--list-archives`, `--restore <name>`) provide manual control. Auto-archive triggers on successful completion and when a completed run is detected on startup.

Implementation lives in `lib/archive.sh` with six functions: `archive_current_run`, `list_archives`, `restore_archive`, `generate_archive_metadata`, `is_run_complete`, and `prompt_archive_completed_run`.

A `_CLAUDELOOP_NO_AUTO_ARCHIVE=1` env var disables auto-archive for tests that verify PROGRESS.md after completion.

## Consequences

- **Positive:** Users can review past runs, restore abandoned work, and start fresh without losing history.
- **Positive:** Auto-archive on completion keeps the working directory clean for the next run.
- **Negative:** Slightly more disk usage in `.claudeloop/archive/` (mitigated: users can delete old archives).
- **Negative:** Integration tests need `_CLAUDELOOP_NO_AUTO_ARCHIVE=1` to prevent auto-archive from moving PROGRESS.md.
