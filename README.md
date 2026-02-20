# ClaudeLoop

[![Sponsor](https://img.shields.io/github/sponsors/chmc?style=social)](https://github.com/sponsors/chmc)

A phase-by-phase execution tool that spawns fresh Claude CLI instances for each phase of a multi-phase plan, preventing context degradation and ensuring focused execution.

**→ [QUICKSTART.md](QUICKSTART.md)** — install and run in minutes

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
- Headers must be `## Phase N: Title` where N is a number in ascending order
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
--dry-run            Validate plan without executing
--max-retries <n>    Max retry attempts per phase (default: 3)
--simple             Plain output (no colors)
--dangerously-skip-permissions  Bypass claude permission prompts (use with caution)
--phase-prompt <file>  Custom prompt template for phase execution
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
| `MAX_RETRIES` | `--max-retries` | `3` |
| `SIMPLE_MODE` | `--simple` | `false` |
| `SKIP_PERMISSIONS` | `--dangerously-skip-permissions` | `false` |
| `BASE_DELAY` | — | `5` |
| `MAX_DELAY` | — | `60` |
| `PHASE_PROMPT_FILE` | `--phase-prompt` | _(empty)_ |
| `QUOTA_RETRY_INTERVAL` | `--quota-retry-interval` | `900` |

Example `.claudeloop/.claudeloop.conf`:

```
PLAN_FILE=my-plan.md
MAX_RETRIES=5
SKIP_PERMISSIONS=true
```

The conf file is plain text — edit or delete it freely. One-time flags (`--reset`, `--phase`, `--dry-run`, `--verbose`, `--continue`) are never persisted.

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

## How it works

1. Parse `PLAN.md` — extract phases and dependencies
2. Find the next runnable phase (dependencies met, not yet completed)
3. Spawn a fresh `claude` CLI instance with the phase description
4. Save result to `PROGRESS.md`
5. On failure: retry with exponential backoff (up to `--max-retries`)
6. Repeat until all phases complete

Press **Ctrl+C** at any time — progress is saved and you can resume with `--continue`.

If you edit `PLAN.md` between runs, ClaudeLoop detects changes on resume: it reports added/removed/renumbered phases and carries forward progress by matching phase titles. Phases not found in the new plan are treated as removed; new phases start as pending.

## Project structure

```
claudeloop/
├── claudeloop              # main executable
├── lib/
│   ├── parser.sh          # phase parsing
│   ├── dependencies.sh    # dependency resolution
│   ├── progress.sh        # progress tracking
│   ├── retry.sh           # retry + backoff
│   └── ui.sh              # terminal output
├── tests/
│   ├── run_all_tests.sh
│   └── test_*.sh
└── examples/
    └── PLAN.md.example
```

## Output and logs

Claude's output streams live to the terminal as each phase runs. All output is also saved to `.claudeloop/logs/phase-N.log`.

To watch a phase log in real time in another terminal:

    tail -f .claudeloop/logs/phase-1.log

## Troubleshooting

**`claude: command not found`** — install the Claude CLI and ensure it's in your PATH

**`Not in a git repository`** — run `git init && git add . && git commit -m "init"` in your project

**Phase keeps failing** — check `.claudeloop/logs/phase-N.log`, break complex phases into smaller ones

**Phase completes but no changes made** — Claude is asking for write permissions it can't grant non-interactively. Re-run with `--dangerously-skip-permissions`, or grant permissions in Claude settings.

## Testing

```bash
./tests/run_all_tests.sh        # run all tests
bats tests/test_parser.sh       # run one test file
shellcheck -s sh lib/retry.sh   # lint
```

## Credits

Inspired by [ralph](https://github.com/snarktank/ralph) by snarktank.

## Author

**Aleksi Sutela** ([chmc](https://github.com/chmc)) — if you find ClaudeLoop useful, [consider sponsoring](https://github.com/sponsors/chmc).
