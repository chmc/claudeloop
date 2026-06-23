# ClaudeLoop Features

<!-- LLM-PARSE-HINT: Each ## is a category. Each ### is a feature with a kebab-case ID.
     Fields use **Bold:** prefix. Status: stable|beta|deprecated. Missing field = not applicable.
     Dependencies reference other feature IDs in [brackets]. -->

## Execution

### plan-execution
**Status:** stable
**Summary:** Execute a multi-phase plan from a structured Markdown file.
**Description:** Reads `## Phase N: Title` sections from a plan file and executes them in sequence. Each phase runs in a fresh Claude instance.
**CLI:** `--plan <file>`
**Env:** `PLAN_FILE`
**Config:** (none)
**Default:** `PLAN.md`
**Files:** `claudeloop`, `lib/phase.sh`

---

### fresh-context
**Status:** stable
**Summary:** Each phase spawns a new Claude instance with a fresh context window.
**Description:** Prevents context degradation across phases. Progress is preserved between instances via PROGRESS.md.
**CLI:** (always enabled)
**Env:** (none)
**Config:** (none)
**Files:** `claudeloop`

---

### dependency-graph
**Status:** stable
**Summary:** Declare phase dependencies; claudeloop resolves execution order automatically.
**Description:** Phases can depend on earlier phases via `**Depends on:** Phase N` syntax. Cycle detection prevents invalid plans.
**CLI:** (parsed from plan file)
**Env:** (none)
**Config:** (none)
**Files:** `lib/dependencies.sh`, `lib/plan_changes.sh`

---

### dry-run
**Status:** stable
**Summary:** Validate plan structure without executing any phases.
**CLI:** `--dry-run`
**Env:** `DRY_RUN`
**Config:** (none)
**Files:** `claudeloop`

---

### start-phase
**Status:** stable
**Summary:** Begin execution at a specific phase number, skipping earlier phases.
**CLI:** `--phase <n>`
**Env:** (none)
**Config:** (none)
**Files:** `claudeloop`

---

### continue-resume
**Status:** stable
**Summary:** Resume from last checkpoint after interruption.
**Description:** Automatically resumes incomplete runs. Prior progress is detected and respected.
**CLI:** `--continue`
**Env:** (none)
**Config:** (none)
**Depends:** [progress-tracking]
**Files:** `claudeloop`

---

### mark-complete
**Status:** stable
**Summary:** Manually mark a phase as completed.
**Description:** Use after a phase completed successfully but was logged as failed (e.g. after manual intervention).
**CLI:** `--mark-complete <n>`
**Env:** (none)
**Config:** (none)
**Depends:** [progress-tracking]
**Files:** `claudeloop`

---

## AI Parsing

### ai-parse
**Status:** stable
**Summary:** Decompose free-form notes or bullet points into structured phases using AI.
**Description:** Reads unstructured input and outputs `## Phase N:` format with dependencies. Includes a verification loop that retries until the plan passes structural checks.
**CLI:** `--ai-parse`
**Env:** `AI_PARSE`
**Config:** `AI_PARSE`
**Default:** `true`
**Files:** `lib/ai_parse.sh`, `lib/ai_verify.sh`

---

### granularity
**Status:** stable
**Summary:** Control the breakdown depth when using AI parsing.
**Description:** `phases` = coarse, `tasks` = medium (default), `steps` = fine-grained.
**CLI:** `--granularity <level>`
**Env:** `GRANULARITY`
**Config:** `GRANULARITY`
**Default:** `tasks`
**Depends:** [ai-parse]

---

### no-retry-mode
**Status:** stable
**Summary:** Single parse+verify pass for programmatic/CI use.
**Description:** Skips interactive retry loop. Exit 0 = passed, exit 2 = verification failed. Failure reason in `.claudeloop/ai-verify-reason.txt`.
**CLI:** `--no-retry`
**Env:** (none)
**Config:** (none)
**Depends:** [ai-parse]

---

### ai-parse-feedback
**Status:** stable
**Summary:** Reparse using the failure reason from a previous verification run.
**CLI:** `--ai-parse-feedback`
**Env:** (none)
**Config:** (none)
**Depends:** [ai-parse]

---

## Quality Assurance

### verify
**Status:** stable
**Summary:** Spawn a fresh read-only Claude instance to check each phase with pass/fail verdict.
**Description:** Independent from the execution instance. Requires an explicit pass keyword in the verdict. Runs after each phase completes.
**CLI:** `--verify`
**Env:** `VERIFY_PHASES`
**Config:** `VERIFY_PHASES`
**Default:** `true`
**Depends:** [fresh-context]
**Files:** `lib/verify.sh`

---

### verify-timeout
**Status:** stable
**Summary:** Kill the verification instance after N seconds.
**CLI:** `--verify-timeout <s>`
**Env:** `VERIFY_TIMEOUT`
**Config:** `VERIFY_TIMEOUT`
**Default:** `300`
**Depends:** [verify]

---

### refactor
**Status:** stable
**Summary:** Auto-refactor code after each phase completion with rollback on test failure.
**Description:** Detects large files, extracts modules, runs tests before and after. Git rollback if tests fail post-refactor.
**CLI:** `--refactor`
**Env:** `REFACTOR_PHASES`
**Config:** `REFACTOR_PHASES`
**Default:** `true`
**Depends:** [verify]
**Files:** `lib/refactor.sh`

---

### refactor-max-retries
**Status:** stable
**Summary:** Maximum refactor attempts per phase before giving up.
**CLI:** `--refactor-max-retries <n>`
**Env:** (none)
**Config:** `REFACTOR_MAX_RETRIES`
**Default:** `20`
**Depends:** [refactor]

---

## Retry and Resilience

### retry-strategies
**Status:** stable
**Summary:** Automatic retry with strategy rotation on phase failure.
**Description:** Escalating strategies: full prompt → stripped prompt → error-focused. Configurable max attempts.
**CLI:** `--max-retries <n>`
**Env:** `MAX_RETRIES`
**Config:** `MAX_RETRIES`
**Default:** `15`
**Files:** `lib/retry.sh`, `lib/prompt.sh`

---

### quota-handling
**Status:** stable
**Summary:** Detect rate-limit and quota errors, wait before retrying.
**Description:** Distinguishes rate-limit (429), quota exhaustion, and server errors (500/502/503/529). Configurable wait interval.
**CLI:** `--quota-retry-interval <s>`
**Env:** `QUOTA_RETRY_INTERVAL`
**Config:** `QUOTA_RETRY_INTERVAL`
**Default:** `900`
**Depends:** [retry-strategies]

---

### phase-timeout
**Status:** stable
**Summary:** Kill Claude after N seconds per phase, then retry.
**Description:** Prevents runaway phases. Killed phases are retried with the next strategy.
**CLI:** `--max-phase-time <s>`
**Env:** `MAX_PHASE_TIME`
**Config:** `MAX_PHASE_TIME`
**Default:** `900`
**Depends:** [retry-strategies]

---

### idle-timeout
**Status:** stable
**Summary:** Exit stream processor after N seconds of no stream activity.
**Description:** Detects hung Claude sessions with no output.
**CLI:** `--idle-timeout <s>`
**Env:** `IDLE_TIMEOUT`
**Config:** `IDLE_TIMEOUT`
**Default:** `600`

---

### dead-timeout
**Status:** stable
**Summary:** Exit if only heartbeat events arrive for N seconds (no real progress).
**Description:** Detects Claude sessions that are alive but making no meaningful progress.
**CLI:** `--dead-timeout <s>`
**Env:** `DEAD_TIMEOUT`
**Config:** `DEAD_TIMEOUT`
**Default:** `180`

---

## Providers

### effort-level
**Status:** stable
**Summary:** Configurable Claude reasoning effort level passed as `--effort` to every Claude invocation.
**CLI:** `--effort <level>`
**Env:** `EFFORT_LEVEL` (also reads `CLAUDE_CODE_EFFORT_LEVEL` as fallback)
**Config:** `EFFORT_LEVEL`
**Default:** `medium`
**Allowed:** `low`, `medium`, `high`, `xhigh`, `max`
**Files:** `lib/adapters/claude.sh`, `lib/config.sh`, `lib/wizard.sh`, `lib/orchestration.sh`

---

### model-per-step
**Status:** stable
**Summary:** Override the target project's model setting per step type (execution, verification, subagents).
**Description:** Prevents project-level model settings (e.g. `opusplan`) from affecting claudeloop phases. Execution and refactoring share `MODEL`; verification uses `MODEL_VERIFY` (falls back to `MODEL`); Explore subagents use `SUBAGENT_MODEL_EXPLORE` (prompt-injected directive). AI parsing always uses opus.
**CLI:** `--model <name>`, `--model-verify <name>`, `--subagent-model explore:<name>`
**Env:** `MODEL`, `MODEL_VERIFY`, `SUBAGENT_MODEL_EXPLORE`
**Config:** `MODEL`, `MODEL_VERIFY`, `SUBAGENT_MODEL_EXPLORE`
**Default:** empty (uses project default)
**Depends:** [effort-level], [multi-provider]
**Files:** `lib/adapters/claude.sh`, `lib/provider.sh`, `lib/execution.sh`, `lib/verify.sh`, `lib/refactor.sh`, `lib/prompt.sh`, `lib/config.sh`, `lib/wizard.sh`, `lib/orchestration.sh`
**ADR:** [0038](docs/adr/0038-per-step-cli-flags.md)

---

### multi-provider
**Status:** stable
**Summary:** Support multiple AI providers via an adapter pattern.
**Description:** Currently: Claude Code (default, auto-detected), OpenCode. Selection persists to config.
**CLI:** `--provider <name>`
**Env:** `PROVIDER`
**Config:** `PROVIDER`
**Default:** auto-detect from PATH
**Files:** `lib/provider.sh`

---

### provider-claude
**Status:** stable
**Summary:** Claude Code CLI adapter (default provider).
**Description:** Requires Claude CLI. Handles streaming JSON events, permission prompts, and tool use.
**Depends:** [multi-provider]
**Files:** `lib/adapters/claude.sh`, `lib/adapters/permission_claude.sh`

---

### provider-opencode
**Status:** experimental
**Summary:** OpenCode CLI adapter.
**Description:** Requires OpenCode with `--output-format json` support.
**Depends:** [multi-provider]
**Files:** `lib/adapters/opencode.sh`, `lib/adapters/permission_opencode.sh`

---

## Monitoring

### live-monitor
**Status:** stable
**Summary:** Watch live execution output from a second terminal.
**Description:** Real-time progress display including todo and task counts.
**CLI:** `--monitor`
**Env:** (none)
**Config:** (none)
**Files:** `lib/monitor.sh`

---

### replay-report
**Status:** stable
**Summary:** Self-contained HTML report at `.claudeloop/replay.html` with timeline and cost data.
**Description:** Updates live during execution. Includes cost, tokens, timeline, file impact, tool usage, and retry filmstrip for side-by-side attempt comparison.
**CLI:** `--replay [archive]`
**Env:** (none)
**Config:** (none)
**Files:** `lib/recorder.sh`, `lib/recorder_parsers.sh`, `lib/recorder_overview.sh`

---

### lessons-capture
**Status:** stable
**Summary:** Per-phase metrics file for Oxveil integration and self-improvement.
**Description:** Captures retries, duration, exit status, failure reason, and phase summary to `.claudeloop/lessons.md` after each phase.
**CLI:** (always enabled)
**Env:** (none)
**Config:** (none)
**Files:** `lib/lessons.sh`

---

## State Management

### progress-tracking
**Status:** stable
**Summary:** Track phase status, attempts, and timestamps in PROGRESS.md.
**Description:** Enables resume, dependency checking, and replay generation. Three parsers read this file: `lib/progress.sh`, `lib/plan_changes.sh`, `lib/recorder.sh`.
**CLI:** `--progress <file>`
**Env:** `PROGRESS_FILE`
**Config:** (none)
**Default:** `.claudeloop/PROGRESS.md`
**Files:** `lib/progress.sh`

---

### archive
**Status:** stable
**Summary:** Save and restore completed run state.
**Description:** Auto-archives on completion. Archives stored in `.claudeloop/archive/{timestamp}/`. Disable with `_CLAUDELOOP_NO_AUTO_ARCHIVE=1`.
**CLI:** `--archive`, `--list-archives`, `--restore <name>`
**Env:** `_CLAUDELOOP_NO_AUTO_ARCHIVE=1` (disable auto-archive)
**Config:** (none)
**Files:** `lib/archive.sh`

---

### recover-progress
**Status:** stable
**Summary:** Reconstruct PROGRESS.md from execution logs after corruption.
**Description:** Reads `.claudeloop/logs/` to rebuild progress state. Use when PROGRESS.md is corrupted or mismatched to a plan.
**CLI:** `--recover-progress`
**Env:** (none)
**Config:** (none)
**Depends:** [progress-tracking]

---

### reset
**Status:** stable
**Summary:** Clear all run state for a fresh start.
**CLI:** `--reset`
**Env:** (none)
**Config:** (none)

---

### force-takeover
**Status:** stable
**Summary:** Kill any running claudeloop instance and take over, preserving progress.
**CLI:** `--force`
**Env:** (none)
**Config:** (none)

---

## Configuration

### setup-wizard
**Status:** stable
**Summary:** Interactive first-run configuration with smart defaults.
**Description:** Walks through all configurable options. Saves choices to `.claudeloop/.claudeloop.conf`.
**CLI:** (auto on first run)
**Env:** (none)
**Config:** (none)
**Files:** `lib/wizard.sh`, `lib/config.sh`

---

### config-precedence
**Status:** stable
**Summary:** Configuration override order: built-in defaults < config file < env vars < CLI args.
**Files:** `lib/config.sh`, `lib/args.sh`

---

### plan-context
**Status:** stable
**Summary:** Inject plan overview and original plan file reference into each phase prompt.
**Description:** Copies the original plan to `.claudeloop/original-plan.md` during AI parsing. Each phase prompt receives a full phase index (title + status for every phase, with `[CURRENT]` marking the active one) and an imperative instruction to read the original plan file for full project context. Phases with no original plan file receive no injection (graceful degradation). Excluded from stripped/targeted retry strategies.
**CLI:** (always active when AI parsing is used)
**Env:** (none)
**Config:** (none)
**Files:** `lib/prompt.sh`, `lib/execution.sh`, `lib/orchestration.sh`

---

### custom-prompts
**Status:** stable
**Summary:** Custom prompt templates with placeholder substitution per phase.
**Description:** Placeholders: `{{PHASE_NUM}}`, `{{PHASE_TITLE}}`, `{{PHASE_DESCRIPTION}}`, `{{PLAN_FILE}}`.
**CLI:** `--phase-prompt <file>`
**Env:** `PHASE_PROMPT_FILE`
**Config:** `PHASE_PROMPT_FILE`
**Files:** `lib/prompt.sh`

---

### skip-permissions
**Status:** stable
**Summary:** Pass `--dangerously-skip-permissions` to the underlying Claude CLI.
**Description:** Bypasses Claude permission prompts. Use only in trusted, controlled environments.
**CLI:** `--dangerously-skip-permissions`
**Env:** `SKIP_PERMISSIONS`
**Config:** `SKIP_PERMISSIONS`
**Default:** `false`

---

### non-interactive-mode
**Status:** stable
**Summary:** Auto-answer all interactive prompts without user input.
**CLI:** `--yes`, `-y`
**Env:** (none)
**Config:** (none)

---

### nudge
**Status:** experimental
**Summary:** Type `n` during execution to provide guidance for stuck phases.
**Description:** Interactive nudge stops the current phase and collects user guidance via single-line input or `$EDITOR`. Input prompt displays as `nudge>` for clarity. Guidance is injected at two positions in the retry prompt with strong directive framing. Forces standard retry strategy so guidance is not diluted by stripped/targeted tiers. Each nudge replaces the previous. "Nudge saved" confirmation is written to the live log. Also available via `--nudge` CLI flag for scripted/pre-run use.
**CLI:** `--nudge <phase> <text>`, `--clear-nudge <phase>`
**Env:** `_NUDGE_DISABLED` (set to `1` in tests to prevent `read -t` blocking)
**Config:** (none)
**Files:** `lib/nudge.sh`, `lib/execution.sh`, `lib/prompt.sh`, `lib/args.sh`, `lib/ui.sh`
