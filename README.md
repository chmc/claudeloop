# ClaudeLoop

[![Sponsor](https://img.shields.io/github/sponsors/chmc?style=social)](https://github.com/sponsors/chmc)

A phase-by-phase execution tool that spawns fresh Claude CLI instances for each phase of a multi-phase plan, preventing context degradation and ensuring focused execution.

## Install / Update

```sh
curl -fsSL https://raw.githubusercontent.com/chmc/claudeloop/main/install.sh | sh
```

```sh
claudeloop --version   # verify installation
```

For full setup instructions see **[QUICKSTART.md](QUICKSTART.md)**.


### Beta versions

To install the latest beta:
```sh
curl -fsSL https://raw.githubusercontent.com/chmc/claudeloop/main/install.sh | BETA=1 sh
```

To install a specific version (stable or beta):
```sh
curl -fsSL https://raw.githubusercontent.com/chmc/claudeloop/main/install.sh | VERSION=0.14.0-beta.1 sh
```

**Uninstall:**
```sh
curl -fsSL https://raw.githubusercontent.com/chmc/claudeloop/main/uninstall.sh | sh
```

Releases and changelogs: [GitHub Releases](https://github.com/chmc/claudeloop/releases) — each release includes a download count badge and a structured changelog grouped by features, bug fixes, and other changes.

## Why ClaudeLoop?

Long-running tasks suffer from context window exhaustion and accumulated confusion. ClaudeLoop solves this by giving each phase a fresh Claude instance while maintaining overall progress.

## Plan file format

```markdown
# Project Title

## Phase 1: Title
Description of what Claude should do.

## Phase 2: Title
**Depends on:** Phase 1

Description of the next task.
```

Rules:
- Headers must be `## Phase N: Title` where N is a number in ascending order (case-insensitive: `Phase`, `phase`, `PHASE` all work)
- Gaps and decimals are allowed: `1, 2, 2.5, 2.6, 3` is valid (useful for inserting sub-phases)
- Dependencies: `**Depends on:** Phase X, Phase Y` on the first line after the header
- Phases can only depend on earlier phases

See `examples/PLAN.md.example` for a complete example.

## Options

```
--plan <file>        Plan file to execute (default: PLAN.md)
--progress <file>    Progress file (default: PROGRESS.md)
--reset              Reset progress and start from beginning
--continue           Resume from last checkpoint
--phase <n>          Start from specific phase number
--mark-complete <n>  Mark a phase as completed (use when a phase succeeded but was logged as failed)
--recover-progress   Reconstruct PROGRESS.md from .claudeloop/logs/ (use after progress corruption)
--force              Kill any running instance and take over (preserves progress)
--dry-run            Validate plan without executing
--max-retries <n>    Max retry attempts per phase (default: 5)
--quota-retry-interval <s>  Seconds to wait after quota limit error (default: 900)
--max-phase-time <s> Kill claude after N seconds per phase, then retry (0=disabled, default 1800)
--idle-timeout <s>   Exit if no stream activity for N seconds (default: 600, 0=disabled)
--verify             Verify each phase with a fresh read-only Claude instance using verdict-based checking (VERIFICATION_PASSED/FAILED keywords, doubles API calls)
--ai-parse             Use AI to decompose plan into granular phases
--granularity <level>  Breakdown depth: phases, tasks, steps (default: tasks)
--simple             Plain output (no colors)
--dangerously-skip-permissions  Bypass claude permission prompts (use with caution)
--phase-prompt <file>  Custom prompt template for phase execution
--monitor            Watch live output of a running claudeloop instance
--version, -V        Print version and exit
--help               Show help
```

## Config file

On first run, ClaudeLoop automatically creates `.claudeloop/.claudeloop.conf` with the active settings. You can then run `claudeloop` with no arguments and it will reuse those settings.

If you pass CLI arguments on a subsequent run, only the explicitly set keys are updated in the conf file.

`--dry-run` never writes or modifies the conf file.

**Persistable keys:**

| Key | CLI flag | Default |
|---|---|---|
| `PLAN_FILE` | `--plan` | `PLAN.md` |
| `PROGRESS_FILE` | `--progress` | `.claudeloop/PROGRESS.md` |
| `MAX_RETRIES` | `--max-retries` | `5` |
| `SIMPLE_MODE` | `--simple` | `false` |
| `SKIP_PERMISSIONS` | `--dangerously-skip-permissions` | `false` |
| `BASE_DELAY` | — | `5` |
| `MAX_DELAY` | — | `60` |
| `PHASE_PROMPT_FILE` | `--phase-prompt` | _(empty)_ |
| `QUOTA_RETRY_INTERVAL` | `--quota-retry-interval` | `900` |
| `MAX_PHASE_TIME` | `--max-phase-time` | `0` |
| `IDLE_TIMEOUT` | `--idle-timeout` | `600` |
| `AI_PARSE` | `--ai-parse` | `false` |
| `GRANULARITY` | `--granularity` | `tasks` |
| `VERIFY_PHASES` | `--verify` | `false` |

Example `.claudeloop/.claudeloop.conf`:

```
PLAN_FILE=my-plan.md
MAX_RETRIES=5
SKIP_PERMISSIONS=true
```

The conf file is plain text — edit or delete it freely. One-time flags (`--reset`, `--phase`, `--mark-complete`, `--dry-run`, `--verbose`, `--continue`) are never persisted.

## Custom phase prompts

By default ClaudeLoop generates a prompt for each phase from the phase title and description.
Pass `--phase-prompt <file>` to use your own template instead.

**Substitution mode** — if the template contains `{{}}` placeholders, they are replaced with phase data:

| Placeholder | Value |
|---|---|
| `{{PHASE_NUM}}` | Phase number (e.g. `2.5`) |
| `{{PHASE_TITLE}}` | Phase title |
| `{{PHASE_DESCRIPTION}}` | Phase description |
| `{{PLAN_FILE}}` | Path to the plan file |

Example template:

```
/implement {{PHASE_TITLE}}

Plan: @{{PLAN_FILE}}
Phase: {{PHASE_NUM}}

{{PHASE_DESCRIPTION}}
```

**Append mode** — if the template contains no `{{}}` placeholders, the phase data is appended as a markdown block at the end of your template. Useful for static system-level instructions.

You can also set the template path in `.claudeloop/.claudeloop.conf`:

```
PHASE_PROMPT_FILE=prompts/my-template.md
```

## AI plan decomposition

Instead of writing a structured plan manually, use `--ai-parse` to let AI decompose any plan file into phases:

```bash
# Decompose a free-form plan into tasks (default granularity)
claudeloop --plan ideas.md --ai-parse

# Use finer granularity for smaller steps
claudeloop --plan ideas.md --ai-parse --granularity steps

# Preview without executing
claudeloop --plan ideas.md --ai-parse --dry-run
```

The AI parser:
1. Reads any plan format (free text, bullet lists, structured docs)
2. Calls `claude --print` to **extract** original content into `## Phase N:` format (preserves descriptions, no rewriting)
3. Verifies completeness, correctness, ordering, and content preservation against the original
4. On verification failure, offers retry/continue/abort — retries with feedback up to 3 times (configurable via `AI_RETRY_MAX`)
5. Shows you the plan for confirmation before proceeding

The generated plan is saved to `.claudeloop/ai-parsed-plan.md` and reused on `--continue`.

## How it works

1. Parse `PLAN.md` — extract phases and dependencies
2. Find the next runnable phase (dependencies met, not yet completed)
3. Spawn a fresh `claude` CLI instance with the phase description
4. Optionally verify with a fresh read-only Claude instance (`--verify`)
5. Save result to `PROGRESS.md`
6. On failure: retry with exponential backoff (up to `--max-retries`)
6. Repeat until all phases complete

Press **Ctrl+C** at any time — progress is saved and you can resume with `--continue`.

If you edit `PLAN.md` between runs, ClaudeLoop detects changes on resume: it reports added/removed/renumbered phases and carries forward progress by matching phase titles. Phases not found in the new plan are treated as removed; new phases start as pending.

## Architecture decisions

Key design decisions are recorded in [docs/adr/](docs/adr/).

## Project structure

```
claudeloop/
├── claudeloop              # main executable
├── lib/
│   ├── parser.sh          # phase parsing
│   ├── dependencies.sh    # dependency resolution
│   ├── progress.sh        # progress tracking
│   ├── retry.sh           # retry + backoff
│   ├── ui.sh              # terminal output
│   ├── ai_parser.sh       # AI plan decomposition
│   ├── verify.sh          # phase verification
│   └── release_notes.sh   # release changelog formatter
├── tests/
│   ├── run_all_tests.sh
│   └── test_*.sh
└── examples/
    └── PLAN.md.example
```

## Output and logs

Claude's output streams live to the terminal as each phase runs. All output is also saved to `.claudeloop/logs/phase-N.log`. ClaudeLoop also writes a combined live log to `.claudeloop/live.log`.

When Claude uses task lists or todo lists to track its progress, a compact summary is shown:

    [Tasks: 1/3 done] ▸ "Implementing auth flow"
    [Task completed] ✓ "Fix authentication bug"
    [Todos: 3/11 done] ▸ "Implementing..."

To watch progress live from a second terminal, use:

    claudeloop --monitor

Or to tail the raw log directly:

    tail -F .claudeloop/live.log

## Troubleshooting

**`claude: command not found`** — install the Claude CLI and ensure it's in your PATH

**`Not in a git repository`** — run `git init && git add . && git commit -m "init"` in your project

**Phase keeps failing** — check `.claudeloop/logs/phase-N.log`, break complex phases into smaller ones

**Phase completes but no changes made** — Claude is asking for write permissions it can't grant non-interactively. Re-run with `--dangerously-skip-permissions`, or grant permissions in Claude settings.

**Phase marked as failed but the work was done** — ClaudeLoop automatically detects this: if a background sub-invocation caused the Claude process to exit non-zero but the main session completed real work (turns > 0 in the log), the phase is marked completed with a warning. If auto-detection misses a case, use `--mark-complete <n>` to override the status manually:

    claudeloop --mark-complete 1

If the repo has uncommitted changes from the prior session, ClaudeLoop detects the existing progress and skips the uncommitted-changes gate automatically.

**Progress corrupted (wrong plan file overwrote PROGRESS.md)** — ClaudeLoop now backs up PROGRESS.md before overwriting and warns on drastic plan changes. If progress was already lost, reconstruct it from execution logs:

    claudeloop --plan your-plan.md --recover-progress

**Orphan log detection** — When ClaudeLoop finds log files for phases not in the current plan (e.g., after switching between `--ai-parse` and manual plans), it warns and offers options:

- If `.claudeloop/ai-parsed-plan.md` exists: `[r]ecover` (recommended) switches to the AI-parsed plan and reconstructs progress from logs automatically, `[c]ontinue`, or `[a]bort`
- If no AI-parsed plan exists: `[c]ontinue` or `[a]bort` (with `--reset` hint)

## Testing

```bash
./tests/run_all_tests.sh        # run all tests
bats tests/test_parser.sh       # run one test file
shellcheck -s sh lib/retry.sh   # lint
./tests/mutate.sh               # mutation testing (all lib files)
./tests/mutate.sh lib/retry.sh  # mutation testing (single file)
```

Mutation testing applies small faults to source code one at a time, runs the corresponding tests, and reports which mutations survived undetected. Use `--with-deletions` to include line-deletion mutations and `--with-integration` to re-test survivors against the integration test suite.

### Automated mutation testing

A GitHub Actions workflow runs mutation testing weekly (Monday 06:00 UTC). You can also trigger it manually:

```bash
gh workflow run "Mutation Testing"                              # all lib files
gh workflow run "Mutation Testing" -f file=lib/retry.sh         # single file
gh workflow run "Mutation Testing" -f with-deletions=true       # include deletions
```

Results appear in the workflow's job summary. When survivors exist, the full report is available as a downloadable artifact.

## Credits

Inspired by [ralph](https://github.com/snarktank/ralph) by snarktank.

## Author

**Aleksi Sutela** ([chmc](https://github.com/chmc)) — if you find ClaudeLoop useful, [consider sponsoring](https://github.com/sponsors/chmc).
