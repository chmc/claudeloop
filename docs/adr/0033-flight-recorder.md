# 33. Replay — Self-contained HTML Execution Report

**Date:** 2026-03-17
**Status:** Accepted

Note: Renamed from "Flight Recorder" to "Replay" (2026-03-22).

## Context

ClaudeLoop generates detailed execution artifacts in `.claudeloop/` (logs, progress, raw JSON), but understanding what happened during a run requires manually reading log files and correlating timestamps. There is no visual overview of execution flow, retry behavior, cost accumulation, or tool usage patterns.

Existing observability tools (Grafana, Datadog) require infrastructure. We need something that works offline, requires zero setup, and ships as a single file alongside the run artifacts.

## Decision

Implement a "replay" report that reconstructs execution data from existing `.claudeloop/` artifacts into a self-contained HTML file at `.claudeloop/replay.html`.

Key design decisions:

- **Reconstruct, don't record:** All data already exists in logs, PROGRESS.md, and raw JSON files. The recorder extracts and assembles — no new recording hooks beyond a single call in `write_progress()`.
- **Single HTML file:** All CSS and JS inline. No external dependencies, no build step. Opens directly in any browser.
- **Shell extracts → JSON → JS renders:** `lib/recorder.sh` produces a JSON blob (spec in `docs/replay-spec.md`). The JSON is embedded in the HTML template at `assets/replay-template.html`.
- **Auto-generated on progress updates:** `write_progress()` triggers regeneration. User opens once and refreshes to see updates.
- **Dark/light theme:** Respects `prefers-color-scheme`. Dark theme uses Tokyo Night-inspired palette for consistency with terminal aesthetics.

The HTML template (`assets/replay-template.html`) uses vanilla JS with named rendering functions (`renderSidebar`, `renderOverview`, `renderPhaseDetail`, `renderAttemptCard`) for maintainability without a framework.

## Consequences

**Positive:**
- Zero-setup execution visibility — just open the HTML file
- Works for active runs (refresh to update) and archived runs
- No new dependencies or infrastructure
- Minimal recording overhead (one shell function call per progress update)
- Self-contained and portable — can be shared, attached to issues, etc.

**Negative:**
- HTML file grows with run complexity (but realistic runs produce <500KB)
- JSON extraction adds ~100ms to each `write_progress()` call
- Template maintenance requires inline CSS/JS (no tooling support)
- Browser refresh required to see updates (no WebSocket/auto-reload)
