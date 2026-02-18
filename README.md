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
- Headers must be `## Phase N: Title` with sequential numbers (1, 2, 3…)
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
--help               Show help
```

## How it works

1. Parse `PLAN.md` — extract phases and dependencies
2. Find the next runnable phase (dependencies met, not yet completed)
3. Spawn a fresh `claude` CLI instance with the phase description
4. Save result to `PROGRESS.md`
5. On failure: retry with exponential backoff (up to `--max-retries`)
6. Repeat until all phases complete

Press **Ctrl+C** at any time — progress is saved and you can resume with `--continue`.

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
