# Replay Report for ClaudeLoop

Self-contained HTML report auto-generated during claudeloop runs. Always available at `.claudeloop/replay.html`. Open in browser anytime to see execution timeline, retry filmstrip with prompt diff, time-travel slider. Works on active runs (auto-updates) and archived runs.

## Design Context

Read the full design spec at `docs/replay-spec.md` (created in Phase 1). Key decisions:
- **Reconstruct, don't record:** All data exists in `.claudeloop/` already. Minimal change to recording side (one hook in `write_progress()`).
- **Single HTML file:** All CSS+JS inline. No external deps. Always at `.claudeloop/replay.html`.
- **Auto-generated:** HTML regenerates on every `write_progress()` call (after each phase status change). User opens once, refreshes to see updates.
- **Shell extracts → JSON → JS renders:** `lib/recorder.sh` produces JSON blob embedded in HTML template.

## Phase 1: Design spec + HTML skeleton with dummy data

Create the design spec document and a self-contained HTML file with **hardcoded dummy data** showing the dashboard layout. No integration yet — just open the HTML directly to verify the visual design.

**Create `docs/replay-spec.md`:** Contains the JSON schema, data source mapping (which files provide which fields), session line format (`[Session: model=X cost=$Y duration=Zs turns=T tokens=Nin/Nout cache=Nr/Nw]`), log header format (`=== EXECUTION START/END ===`), attempt log naming (`phase-N.attempt-M.log`), and edge case handling. This document is the single source of truth for all subsequent phases.

**Create `assets/replay-template.html`:** Self-contained HTML with embedded dummy JSON data showing a run with 5 phases (one with 3 attempts, one failed). Layout:
- Dark/light theme via `prefers-color-scheme` (dark = Tokyo Night-inspired)
- Sidebar (280px): phase list with status icons (✅❌⏳🔄), timestamps, attempt sub-entries
- Main panel: overview with summary cards (Duration, Cost, Phases, Tokens), proportional timeline bar
- Click phase in sidebar → show phase detail with attempt cards (strategy badge, fail reason, cost, tokens)
- Vanilla JS, no frameworks. Rendering functions: `renderSidebar()`, `renderOverview()`, `renderPhaseDetail(num)`, `renderAttemptCard(attempt)`

**Create `docs/adr/0033-flight-recorder.md`** (replay report ADR) and update `docs/adr/README.md`.

**Demo:** Open `assets/replay-template.html` directly in browser. See the full dashboard with dummy data.

## Phase 2: JSON extraction from run data
**Depends on:** Phase 1

Create `lib/recorder.sh` with functions to extract real data from `.claudeloop/` and produce the JSON blob defined in `docs/replay-spec.md`.

**Create `tests/test_recorder.sh` first (TDD).** Setup creates synthetic `.claudeloop/` fixtures:
- `PROGRESS.md` with 2 phases (1 completed in 1 attempt, 1 completed after 3 attempts)
- `logs/phase-1.log` with EXECUTION START/END headers and `[Session:]` line
- `logs/phase-2.log`, `logs/phase-2.attempt-1.log`, `logs/phase-2.attempt-2.log`
- `logs/phase-1.raw.json` with tool_use events
- `metadata.txt`

**Create `lib/recorder.sh` functions:**
- `json_escape(string)` — escape for JSON via awk. Handle: `\` → `\\`, `"` → `\"`, newline → `\n`, tab → `\t`. **Critical path — extensive tests required.**
- `rec_extract_run_overview(run_dir)` — parse `metadata.txt` (archived) or compute from PROGRESS.md (active run) → JSON `"run":{...}` fragment
- `rec_load_progress(run_dir)` — parse PROGRESS.md into `_REC_PHASE_*` variables. Reuse pattern from `read_progress()` in `lib/progress.sh:23-94`.
- `rec_extract_session(log_file)` — parse `[Session:]` line via awk → JSON with model, cost_usd, duration_s, turns, input_tokens, output_tokens, cache_read, cache_write. Handle optional fields (cache/web/denials may be absent).
- `rec_extract_exec_meta(log_file)` — parse `=== EXECUTION START phase=N attempt=M time=ISO ===` and `=== EXECUTION END exit_code=E duration=Ns time=ISO ===`. Handle missing END (interrupted run).
- `rec_extract_tools(raw_json_file)` — count tool_use events by name via awk → `[{"name":"Edit","count":5}]`. File is `.claudeloop/logs/phase-N.raw.json`.
- `rec_extract_files(raw_json_file)` — extract `file_path` from Write/Edit/Read tool_use events → `[{"path":"src/foo.ts","ops":["Edit"]}]`. Deduplicate.
- `rec_verify_verdict(run_dir, phase_num)` — grep `logs/phase-N.verify.log` for VERIFICATION_PASSED/FAILED.
- `rec_extract_git_commits(phase_num)` — `git log --oneline --grep="Phase $N:"` → `[{"sha":"abc","message":"..."}]`.
- `assemble_recorder_json(run_dir)` — orchestrates all extractors, outputs complete JSON to stdout.

**Do NOT extract prompt text yet** — that's Phase 5.

**Demo:** `bats tests/test_recorder.sh` — all extraction tests pass with synthetic fixtures.

## Phase 3: Hook into write_progress + real data in HTML
**Depends on:** Phase 1, Phase 2

Wire everything together: auto-generate `.claudeloop/replay.html` on every progress update.

**Add to `lib/recorder.sh`:**
- `inject_and_write_html(json_file, output_path)` — read `assets/replay-template.html`, replace `<!--JSON_DATA-->` marker with `<script>const DATA = {json};</script>`, write output. Use line-split approach (head/tail around marker line, cat JSON between) to avoid awk string-length limits.
- `generate_replay(run_dir)` — assemble JSON to temp file, inject into HTML template, write to `{run_dir}/replay.html`. Silent on failure (don't break execution).

**Update `assets/replay-template.html`:** Replace hardcoded dummy JSON with `<!--JSON_DATA-->` placeholder.

**Modify `lib/progress.sh`:** In `write_progress()` (after the atomic `mv` at line ~123), add a call to `generate_replay ".claudeloop"`. Wrap in a guard: only if `lib/recorder.sh` has been sourced. The call must be non-blocking and failure-tolerant (the recorder must never break the execution loop).

**Source `lib/recorder.sh`** in the main `claudeloop` script (add to the existing lib sourcing block around line ~31-44). Source it conditionally or always — it's lightweight (functions only, no side effects).

**Update `tests/test_recorder.sh`:** Test `inject_and_write_html` produces valid HTML with JSON embedded. Test end-to-end: `generate_replay` with fixture data → valid HTML file.

**Demo:** Run claudeloop on a real plan → open `.claudeloop/replay.html` in browser → see real data. Refresh after more phases complete → data updates.

## Phase 4: Tool chips + file impact view + git commits
**Depends on:** Phase 3

Enhance the HTML to show tool usage, file impact, and git commits.

**Update `assets/replay-template.html`:**
- Attempt cards show tool chips: colored badges like `Read×5`, `Edit×3`, `Bash×8`
- New "Files" nav view: table with rows=files, columns=phases, cells=operation (R/W/E). Sorted by most-touched files.
- Per-phase collapsible "Git Commits" section: SHA + message. Toggle button, default collapsed.

**Demo:** Open replay report → tool badges on attempt cards. Click "Files" → cross-phase file impact table. Toggle "Git Commits" on a phase.

## Phase 5: Retry filmstrip with prompt diff
**Depends on:** Phase 4

The killer feature no existing tool offers. For multi-attempt phases, show a filmstrip of attempts with diff between consecutive attempts.

**Update `lib/recorder.sh`:**
- `rec_extract_prompt_text(log_file)` — extract text between `=== PROMPT ===` and `=== RESPONSE ===` markers. If prompt exceeds 200 lines, truncate to first 80 + last 80 lines with `\n... N lines omitted ...\n`. JSON-escape.
- Update `assemble_recorder_json` to include `prompt_text` in each attempt's JSON.

**Update `tests/test_recorder.sh`:** Test `rec_extract_prompt_text` with normal and oversized prompts.

**Update `assets/replay-template.html`:**
- **Filmstrip layout:** For phases with >1 attempt, horizontal strip of attempt thumbnail cards. Each shows: attempt number, strategy badge, outcome (fail reason or ✅), tool count.
- **Diff panel:** Default shows diff between consecutive attempts (N vs N+1). Toggle to pick arbitrary pair.
- **Prompt diff:** Simple line-based diff algorithm in JS (~50 lines). Unified diff with red/green highlighting. Shows how retry context evolved.
- **Tool diff:** Side-by-side comparison of tool usage counts between attempts.
- **File diff:** Files touched in attempt B that weren't in attempt A.

**Demo:** Open replay report on a run with retries → filmstrip strip visible. Click between attempts → prompt diff shows how instructions changed. Tool usage shows convergence.

## Phase 6: Time-travel slider
**Depends on:** Phase 5

Reconstruct execution state at any point in time.

**Update `assets/replay-template.html`:**
- **Slider bar:** Horizontal scrubber spanning full run duration. Tick marks at phase transitions and attempt starts.
- **State reconstruction:** JS function filters events before selected timestamp → computes: phases completed/in_progress/pending/failed, current retry count, accumulated cost, files modified so far.
- **State display panel:** Phase status list, running cost counter, file count.
- **Play button:** Auto-advance with speed control (1x/5x/10x). requestAnimationFrame. Pause/resume.
- **Keyboard:** Left/right arrows step between events. Space toggles play/pause.

No recorder.sh changes — all timestamps already in JSON.

**Demo:** Drag slider → phases light up as they complete, cost accumulates. Press play → run animates like a recording.

## Phase 7: Documentation + polish
**Depends on:** Phase 6

- Update `README.md`: document replay report (what it shows, where to find it, how it works)
- Update `QUICKSTART.md` if relevant
- Create GitHub issues for future features: Phase DAG waterfall, Execution heatmap, Cost Sankey diagram
- Final visual polish on HTML (spacing, transitions, responsive)
- Run full test suite and `/verify`
