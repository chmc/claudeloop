# 24. Drop DECSTBM scroll regions for sticky panel rendering

**Date:** 2026-03-06
**Status:** Accepted

## Context

The sticky bottom panel (showing Claude's todos/tasks) used DECSTBM (DEC Set Top and Bottom Margins) scroll regions to pin content at the bottom of the terminal. This approach proved fundamentally fragile — six consecutive fix attempts (commits c485886 through 8e91d5a) failed to resolve persistent text overlap bugs caused by stdout/stderr interleaving, cursor save/restore timing, and terminal compatibility issues.

The alternative cursor-up/clear approach had previously been rejected due to two bugs: (1) panel writing to stdout (interleaving with assistant text), and (2) ghost duplication when the panel exceeded available terminal space. Bug #1 was already fixed (panel moved to stderr in c485886). Bug #2 is solved by capping panel height to fit within the terminal.

## Decision

Replace DECSTBM scroll regions with cursor-up/clear rendering for the sticky panel:

- Remove `activate_panel()`, `deactivate_panel()`, and `render_panel_content()` functions
- Rewrite `render_sticky()` to use cursor-up with height capping — when items exceed `term_height - 5`, show a windowed view centered on the first in-progress/pending item with an overflow indicator
- Simplify `clear_bottom_block()` to only handle cursor-up panel clearing
- Remove all `\033[r` (DECSTBM reset) sequences from `claudeloop` cleanup handlers

## Consequences

**Positive:**
- Eliminates persistent text overlap / scrollback corruption bugs
- Significantly simpler code (~60 lines removed)
- Works reliably across all terminal emulators (no DECSTBM compatibility concerns)
- Scrollback is naturally preserved

**Negative:**
- Brief flicker possible during panel re-render on content events (acceptable trade-off)
- Panel no longer re-renders during heartbeats (only on content changes), so spinner updates are independent of panel
