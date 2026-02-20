# ClaudeLoop Quick Start

## 1. Install prerequisites

- **Claude CLI** — `claude` must be in your PATH
- **Git** — your project must be a git repo

```bash
# Clone claudeloop
git clone https://github.com/yourusername/claudeloop.git
chmod +x claudeloop/claudeloop

# Optionally add to PATH
ln -s "$(pwd)/claudeloop/claudeloop" /usr/local/bin/claudeloop
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
claudeloop --plan my-plan.md   # use a specific plan file
claudeloop --reset             # reset progress and start over
claudeloop --continue          # resume after Ctrl+C interrupt
claudeloop --phase 3           # start from a specific phase
claudeloop --dry-run           # validate without executing
claudeloop --dangerously-skip-permissions  # skip write permission prompts
claudeloop --phase-prompt prompts/template.md  # use a custom prompt template
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
```

## Config file

ClaudeLoop creates `.claudeloop.conf` automatically on first run. After that, you can just run `claudeloop` with no arguments:

```bash
# First run — conf is created with your settings
claudeloop --plan my-plan.md --max-retries 5

# Subsequent runs — settings are read from .claudeloop.conf
claudeloop
```

Edit or delete `.claudeloop.conf` freely. `--dry-run` never writes to it.

## Tips

- Press **Ctrl+C** at any time to stop — progress is saved, resume with `--continue`
- Keep phases small and focused — one clear task per phase
- Each phase should commit its changes so the next phase starts clean
- Check `.claudeloop/logs/phase-N.log` if a phase fails
- Claude output streams live to the terminal. Logs are saved to `.claudeloop/logs/phase-N.log`

See `examples/PLAN.md.example` for a full example, and `README.md` for complete documentation.
