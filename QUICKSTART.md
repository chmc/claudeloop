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
```

## Tips

- Press **Ctrl+C** at any time to stop — progress is saved, resume with `--continue`
- Keep phases small and focused — one clear task per phase
- Each phase should commit its changes so the next phase starts clean
- Check `.claudeloop/logs/phase-N.log` if a phase fails
- Claude output streams live to the terminal. Logs are saved to `.claudeloop/logs/phase-N.log`

See `examples/PLAN.md.example` for a full example, and `README.md` for complete documentation.
