# ClaudeLoop Quick Start

## 1. Install prerequisites

- **Claude CLI** — `claude` must be in your PATH
- **Git** — your project must be a git repo

## Install

**One-liner (public repo):**

```sh
curl -fsSL https://raw.githubusercontent.com/chmc/claudeloop/main/install.sh | sh
```

**From a local clone (private repo or specific version):**

```sh
git clone git@github.com:chmc/claudeloop.git claudeloop-src
cd claudeloop-src
./install.sh
```

**Install latest beta:**

```sh
curl -fsSL https://raw.githubusercontent.com/chmc/claudeloop/main/install.sh | BETA=1 sh
```

**Install a specific version (stable or beta):**

```sh
curl -fsSL https://raw.githubusercontent.com/chmc/claudeloop/main/install.sh | VERSION=0.14.0-beta.1 sh
```

**Verify installation:**

```sh
claudeloop --version
```

**Uninstall:**

```sh
./uninstall.sh   # from the repo clone
# or
curl -fsSL https://raw.githubusercontent.com/chmc/claudeloop/main/uninstall.sh | sh
```

## 2. Create a plan

In your project directory, create `PLAN.md`:

```markdown
# My Project

## Phase 1: First Task
Describe what Claude should do in this phase.

## Phase 2: Second Task
**Depends on:** Phase 1

Describe what Claude should do next.
```

## 3. Run

```bash
cd /path/to/your/project

claudeloop --dry-run      # validate plan first
claudeloop                # execute
```

## Common commands

```bash
claudeloop --version           # print installed version
claudeloop --plan my-plan.md   # use a specific plan file
claudeloop --reset             # reset progress and start over
claudeloop --continue          # resume after Ctrl+C interrupt
claudeloop --phase 3           # start from a specific phase
claudeloop --dry-run           # validate without executing
claudeloop --dangerously-skip-permissions  # skip write permission prompts
claudeloop --phase-prompt prompts/template.md  # use a custom prompt template
claudeloop --force             # kill any running instance and take over (preserves progress)
claudeloop --recover-progress  # reconstruct progress from logs after corruption
claudeloop --archive           # archive current run state and exit
claudeloop --list-archives     # list past archived runs
claudeloop --restore 20260316-143022  # restore an archived run
claudeloop --monitor           # watch live output from a second terminal
claudeloop --max-phase-time 1800  # kill and retry phases that run longer than 30 min
claudeloop --idle-timeout 300    # exit stream processor after 5 min of no activity (default: 600)
claudeloop --verify                    # verify each phase with a fresh Claude instance
claudeloop --verify-timeout 900        # increase verification timeout to 15 min (default: 300)
claudeloop --refactor                  # auto-refactor code after each phase (up to 20 attempts, preserves work between retries)
claudeloop --plan ideas.md --ai-parse  # AI-extract a free-form plan into phases
claudeloop --plan ideas.md --ai-parse --granularity steps  # finer breakdown (with verification feedback loop)
```

## Full examples

```bash
# Run a plan non-interactively (auto-approve file writes)
claudeloop --plan PLAN.md --dangerously-skip-permissions

# Validate a plan before running it
claudeloop --plan PLAN.md --dry-run

# Start (or restart) from phase 3, auto-approving writes
claudeloop --plan PLAN.md --phase 3 --dangerously-skip-permissions

# Resume after an interrupt, auto-approving writes
claudeloop --continue --dangerously-skip-permissions

# Reset progress and re-run from scratch
claudeloop --plan PLAN.md --reset --dangerously-skip-permissions

# AI-decompose a free-form plan and execute
claudeloop --plan ideas.md --ai-parse --dangerously-skip-permissions
```

## Config file

ClaudeLoop creates `.claudeloop/.claudeloop.conf` automatically on first run. After that, you can just run `claudeloop` with no arguments:

```bash
# First run — conf is created with your settings
claudeloop --plan my-plan.md --max-retries 10

# Subsequent runs — settings are read from .claudeloop/.claudeloop.conf
claudeloop
```

Edit or delete `.claudeloop/.claudeloop.conf` freely. `--dry-run` never writes to it.

## Tips

- Press **Ctrl+C** at any time to stop — progress is saved, resume with `--continue`
- Keep phases small and focused — one clear task per phase
- Each phase should commit its changes so the next phase starts clean
- Check `.claudeloop/logs/phase-N.log` if a phase fails
- Claude output streams live to the terminal. Logs are saved to `.claudeloop/logs/phase-N.log`
- Phase runs longer than `MAX_PHASE_TIME` seconds are automatically killed and retried (disabled by default; set `--max-phase-time <s>` to enable)
- If no stream activity is detected for `IDLE_TIMEOUT` seconds (default: 600), the stream processor exits and the phase is retried. Use `--idle-timeout 0` to disable.
- On retry, the previous attempt's output is injected into the prompt so Claude can learn from it
- `--verify` doubles API calls per phase (one for execution, one for verification)
- `--refactor` adds up to 40 more API calls per phase (20 attempts × refactoring + verification each); up to 42 total with `--verify`
- Live output is archived to `.claudeloop/live-YYYYMMDD-HHMMSS.log` on each run

## Output and Logs

Claude's output streams live to the terminal as each phase runs. All output is also saved to `.claudeloop/logs/phase-N.log`. ClaudeLoop also writes a combined live log to `.claudeloop/live.log`.

When Claude uses task lists or todo lists, a compact summary is shown on the spinner line:

    / 30s Todo 3/8
    - 12s Task 2/5

Inline summaries also appear as `[Tasks: 1/3 done]` and `[Todos: 3/8 done]`.

To watch progress live from a second terminal, use:

    claudeloop --monitor

Or to tail the raw log directly:

    tail -F .claudeloop/live.log

Live output is archived to `.claudeloop/live-YYYYMMDD-HHMMSS.log` on each run.

## Project Structure

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

## Detailed Execution Flow

1. Parse `PLAN.md` — extract phases and dependencies
2. Find the next runnable phase (dependencies met, not yet completed)
3. Spawn a fresh `claude` CLI instance with the phase description
4. Optionally verify with a fresh read-only Claude instance (`--verify`)
5. Optionally auto-refactor code structure (`--refactor`) with up to 20 attempts (configurable via `--refactor-max-retries`), preserving work between retries and discarding on final failure
6. Save result to `PROGRESS.md`
7. On failure: retry with exponential backoff and automatic strategy rotation — early retries use the full phase description, later retries strip boilerplate and focus on the specific error
8. Repeat until all phases complete

Press **Ctrl+C** at any time — progress is saved and you can resume with `--continue`.

If you edit `PLAN.md` between runs, ClaudeLoop detects changes on resume: it reports added/removed/renumbered phases and carries forward progress by matching phase titles. Phases not found in the new plan are treated as removed; new phases start as pending.

## CI

Mutation testing runs automatically every Monday via GitHub Actions. Trigger it manually with `gh workflow run "Mutation Testing"`. Results appear in the job summary; survivor reports are uploaded as artifacts.

See `examples/PLAN.md.example` for a full example, and `README.md` for complete documentation.
