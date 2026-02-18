# ClaudeLoop Quick Start Guide

Get started with ClaudeLoop in 5 minutes.

## Installation

```bash
# Install bash 5+ (required)
brew install bash

# Install bats-core (for tests)
brew install bats-core

# Make claudeloop executable
chmod +x claudeloop
```

## Create Your First Plan

Create a file named `PLAN.md`:

```markdown
# My First Plan

## Phase 1: Create Project Structure
Create a new directory called "my-app".
Inside it, create:
- README.md with project description
- src/ directory
- tests/ directory

## Phase 2: Add Hello World
**Depends on:** Phase 1

Create src/hello.js with a simple console.log("Hello World").
Test it with node src/hello.js.

## Phase 3: Add Tests
**Depends on:** Phase 2

Create tests/hello.test.js with basic tests.
Use Jest or another testing framework.
```

## Run ClaudeLoop

```bash
# Validate your plan (dry-run)
./claudeloop --dry-run

# Execute the plan
./claudeloop

# Or specify a different plan file
./claudeloop --plan my-plan.md
```

## What Happens

1. ClaudeLoop parses your `PLAN.md`
2. For each phase:
   - Spawns a fresh `claude` CLI instance
   - Provides the phase description as context
   - Claude implements the phase
   - Progress is saved to `PROGRESS.md`
3. If a phase fails, it retries automatically (3 attempts by default)
4. You can interrupt (Ctrl+C) and resume later with `--continue`

## Check Progress

ClaudeLoop automatically creates `PROGRESS.md`:

```markdown
# Progress for PLAN.md
Last updated: 2026-02-18 15:30:00

## Status Summary
- Total phases: 3
- Completed: 2
- In progress: 1
- Pending: 0
- Failed: 0

## Phase Details

### ✅ Phase 1: Create Project Structure
Status: completed
Started: 2026-02-18 15:25:00
Completed: 2026-02-18 15:27:30

### ✅ Phase 2: Add Hello World
Status: completed
...

### 🔄 Phase 3: Add Tests
Status: in_progress
...
```

## View Logs

All Claude output is saved to `.claudeloop/logs/`:

```bash
# View log for phase 1
cat .claudeloop/logs/phase-1.log

# Tail logs for current phase
tail -f .claudeloop/logs/phase-*.log
```

## Common Commands

```bash
# Validate plan without execution
./claudeloop --dry-run

# Reset progress and start fresh
./claudeloop --reset

# Continue from where you left off
./claudeloop --continue

# Start from a specific phase
./claudeloop --phase 3

# Change max retries
./claudeloop --max-retries 5

# Simple output mode (no colors)
./claudeloop --simple
```

## Killswitch: Interrupt and Resume

You can **stop execution at any time** with Ctrl+C:

```bash
# Start execution
./claudeloop

# Press Ctrl+C during execution
# Output:
# ⚠ Interrupt received (Ctrl+C)
# ⚠ Saving state and shutting down gracefully...
# ⚠ Marking Phase 2 as pending for retry
# ✓ State saved successfully
# ✓ Resume with: ./claudeloop --continue

# Resume later
./claudeloop --continue
# Output:
# ⚠ Found interrupted session
# Resume from last checkpoint? (Y/n) y
# ... continues from where you left off
```

**What happens on interrupt:**
- ✅ Current progress saved immediately
- ✅ In-progress phase marked as pending (not failed)
- ✅ State saved for clean resume
- ✅ Lock file cleaned up
- ✅ No work is lost!

## Tips

1. **Be Specific**: Write clear, actionable phase descriptions
2. **Small Phases**: Break complex tasks into smaller phases
3. **Dependencies**: Use dependencies to ensure correct order
4. **Commit Often**: Each phase should commit its changes
5. **Review Logs**: Check `.claudeloop/logs/` if something goes wrong

## Example Plans

See `examples/PLAN.md.example` for a complete example of building a Todo List API.

## Testing

```bash
# Run all tests
./tests/run_all_tests.sh

# Run specific tests
bats tests/test_parser.sh
```

## Troubleshooting

### Bash Version Error
```
Error: declare: -A: invalid option
```

**Solution**: Install bash 5+
```bash
brew install bash
# Verify: /opt/homebrew/bin/bash --version
```

### Claude Not Found
```
Error: claude: command not found
```

**Solution**: Install Claude CLI
```bash
# Follow Claude CLI installation instructions
```

### Not in Git Repo
```
Error: Not in a git repository
```

**Solution**: Initialize git
```bash
git init
git add .
git commit -m "Initial commit"
```

## Next Steps

1. Read the full [README.md](README.md) for detailed documentation
2. Check out [examples/](examples/) for more complex examples
3. Customize your plan and run `./claudeloop`
4. Star the repo if you find it useful!

Happy coding with ClaudeLoop! 🚀
