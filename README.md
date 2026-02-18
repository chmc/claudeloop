# ClaudeLoop

A phase-by-phase execution tool that spawns fresh Claude CLI instances for each phase of a multi-phase plan, preventing context degradation and ensuring focused execution.

## Overview

ClaudeLoop implements a "ralph loop" pattern inspired by [ralph](https://github.com/snarktank/ralph). It executes complex multi-phase plans by:

- **Fresh Context Per Phase**: Each phase gets a clean Claude instance with full context window
- **Dependency Management**: Phases can depend on other phases completing first
- **Progress Tracking**: Persistent progress tracking with resume capability
- **Retry Logic**: Automatic retry with exponential backoff for failed phases
- **Safety First**: Git repository checks and uncommitted change warnings

## Why ClaudeLoop?

Long-running tasks often suffer from:
- Context window exhaustion
- Accumulated confusion from previous phases
- Loss of focus on the current task

ClaudeLoop solves this by giving each phase a fresh start while maintaining overall progress.

## Installation

### Prerequisites

- **bash 5.0+**: Required for associative arrays
  ```bash
  # macOS
  brew install bash

  # Verify version
  /opt/homebrew/bin/bash --version
  ```

- **Claude CLI**: The official Anthropic Claude CLI
  ```bash
  # Installation instructions from Claude CLI documentation
  ```

- **Git**: Must be in a git repository for safety

- **bats-core** (optional, for running tests):
  ```bash
  brew install bats-core
  ```

### Setup

```bash
# Clone or copy the claudeloop directory
cd /path/to/claudeloop

# Make executable
chmod +x claudeloop

# Optionally add to PATH
ln -s "$(pwd)/claudeloop" /usr/local/bin/claudeloop
```

## Usage

### Basic Usage

```bash
# Execute PLAN.md in current directory
./claudeloop

# Execute specific plan file
./claudeloop --plan my_feature.md

# Validate plan without executing
./claudeloop --dry-run

# Reset progress and start fresh
./claudeloop --reset

# Interrupt at any time with Ctrl+C (state is saved)
# Then resume with:
./claudeloop --continue
```

### Killswitch (Interrupt and Resume)

ClaudeLoop supports graceful interruption at any time:

1. **Interrupt**: Press **Ctrl+C** during execution
   - Current progress is immediately saved to `PROGRESS.md`
   - In-progress phase is marked as pending (not counted as a failed attempt)
   - Execution state is saved to `.claudeloop/state/current.json`
   - Lock file is cleaned up

2. **Resume**: Run `./claudeloop --continue` (or just `./claudeloop`)
   - Detects interrupted session automatically
   - Prompts to resume from last checkpoint
   - Continues from where you left off

This is useful when:
- You need to stop work and continue later
- You want to review progress before continuing
- You need to make changes to the plan
- System needs to restart or update

### Command-Line Options

```
--plan <file>        Plan file to execute (default: PLAN.md)
--progress <file>    Progress file (default: PROGRESS.md)
--reset              Reset progress and start from beginning
--continue           Continue from last checkpoint (default)
--phase <n>          Start from specific phase number
--dry-run            Validate plan without execution
--max-retries <n>    Maximum retry attempts per phase (default: 3)
--simple             Use simple output mode (no colors/fancy UI)
--help               Show this help message
```

## Plan File Format

Create a `PLAN.md` file with phases defined as `## Phase N: Title` headers:

```markdown
# Project: User Authentication System

## Phase 1: Database Schema
Create the users table with the following columns:
- id (primary key, UUID)
- email (unique, not null)
- password_hash (not null)
- created_at (timestamp)

Add migration file and run migrations.

## Phase 2: API Endpoints
**Depends on:** Phase 1

Implement REST endpoints:
- POST /api/users (create user)
- GET /api/users/:id (get user)
- POST /api/login (authenticate)

Include input validation and error handling.

## Phase 3: Authentication Middleware
**Depends on:** Phase 2

Create middleware to verify JWT tokens.
Protect routes that require authentication.

## Phase 4: Integration Tests
**Depends on:** Phase 2, Phase 3

Write integration tests for all endpoints.
Ensure >90% code coverage.
Test authentication flow end-to-end.
```

### Plan File Rules

- **Phase Headers**: Must be `## Phase N: Title` where N is sequential (1, 2, 3...)
- **Dependencies**: Use `**Depends on:** Phase X, Phase Y` on the first line after the header
- **Description**: Everything after the header (and dependency line) until the next phase header
- **Sequential Numbering**: Phases must be numbered 1, 2, 3, etc. (no gaps)
- **Forward Dependencies**: Phases can only depend on earlier phases

## Progress Tracking

ClaudeLoop automatically creates a `PROGRESS.md` file tracking:

- **Phase Status**: pending, in_progress, completed, failed
- **Timestamps**: When each phase started and completed
- **Attempts**: Number of retry attempts
- **Dependencies**: Visual indicators of dependency status

Example `PROGRESS.md`:

```markdown
# Progress for PLAN.md
Last updated: 2026-02-18 14:23:45

## Status Summary
- Total phases: 4
- Completed: 2
- In progress: 0
- Pending: 2
- Failed: 0

## Phase Details

### ✅ Phase 1: Database Schema
Status: completed
Started: 2026-02-18 14:15:30
Completed: 2026-02-18 14:18:22
Attempts: 1

### ✅ Phase 2: API Endpoints
Status: completed
Started: 2026-02-18 14:18:25
Completed: 2026-02-18 14:25:10
Attempts: 1
Depends on: Phase 1 ✅

### ⏳ Phase 3: Authentication Middleware
Status: pending
Depends on: Phase 2 ✅

### ⏳ Phase 4: Integration Tests
Status: pending
Depends on: Phase 2 ✅, Phase 3 ⏳
```

## How It Works

1. **Parse Plan**: Read PLAN.md and extract phases with dependencies
2. **Initialize Progress**: Load existing progress or start fresh
3. **Find Next Phase**: Select first runnable phase (dependencies met, not completed)
4. **Execute Phase**: Spawn fresh `claude` CLI instance with phase context
5. **Track Progress**: Update PROGRESS.md with results
6. **Retry on Failure**: Automatically retry failed phases with backoff
7. **Repeat**: Continue until all phases complete or blocked

### Dependency Resolution

- Phases only run when all dependencies are `completed`
- Circular dependencies are detected and rejected
- If a phase fails, dependent phases remain blocked
- Progress is saved after each phase

### Retry Logic

- Failed phases automatically retry with exponential backoff
- Default: 3 attempts per phase
- Backoff delay: min(2^(attempt-1) * 5s, 60s) with random jitter
- After max retries, phase marked as failed and execution stops

## Examples

### Example 1: Simple Feature Implementation

```markdown
# Feature: Add Dark Mode

## Phase 1: Add Theme State
Create a theme context and state management.
Support 'light' and 'dark' themes.

## Phase 2: Update Components
**Depends on:** Phase 1

Update all components to use theme context.
Add theme-aware CSS variables.

## Phase 3: Add Toggle UI
**Depends on:** Phase 2

Add theme toggle button to navbar.
Persist theme preference to localStorage.

## Phase 4: Test
**Depends on:** Phase 3

Add tests for theme switching.
Test localStorage persistence.
```

### Example 2: Bug Fix with Investigation

```markdown
# Fix: Memory Leak in Websocket Handler

## Phase 1: Investigate and Identify
Read the websocket handler code.
Check memory profiling data.
Identify the source of the leak.
Document findings.

## Phase 2: Implement Fix
**Depends on:** Phase 1

Based on findings from Phase 1, implement the fix.
Ensure proper cleanup of event listeners.
Add defensive checks.

## Phase 3: Verify Fix
**Depends on:** Phase 2

Run memory profiling again.
Verify leak is resolved.
Add regression test.
```

## Testing

ClaudeLoop is developed using TDD (Test-Driven Development):

```bash
# Run all tests
./tests/run_all_tests.sh

# Run specific test file
bats tests/test_parser.sh
```

### Test Coverage

- ✅ **Parser Tests**: Phase extraction, dependencies, validation
- ⏳ **Dependency Tests**: Graph building, cycle detection, runnable phases
- ⏳ **Progress Tests**: Read/write, status updates, atomic operations
- ⏳ **Retry Tests**: Backoff calculation, retry logic
- ⏳ **Integration Tests**: Full execution flow

## Safety Features

- **Git Repository Check**: Must be in a git repo
- **Uncommitted Changes Warning**: Alerts if there are uncommitted changes
- **Lock File**: Prevents concurrent runs (PID-based)
- **Atomic Progress Updates**: Progress file updated atomically
- **Killswitch (Ctrl+C)**: Graceful interrupt with state saving
  - Press Ctrl+C at any time to stop immediately
  - Current progress is saved
  - In-progress phase is marked as pending (not failed)
  - Resume later with `--continue`
- **Exit Cleanup**: Signal handlers ensure clean shutdown
- **State Persistence**: Execution state saved on interrupt

## Troubleshooting

### "declare: -A: invalid option"

You're using bash 3.2 (macOS default). Install bash 5+:
```bash
brew install bash
# Use /opt/homebrew/bin/bash explicitly
```

### "claude: command not found"

Install the Claude CLI:
```bash
# Follow Claude CLI installation instructions
```

### "Not in a git repository"

Initialize git in your project:
```bash
git init
git add .
git commit -m "Initial commit"
```

### Phase keeps failing

- Check `.claudeloop/logs/phase-N.log` for detailed output
- Verify phase description is clear and actionable
- Consider breaking complex phases into smaller ones
- Adjust `--max-retries` if needed

## Limitations

- Phases execute sequentially (no parallelization)
- Requires bash 5.0+ for associative arrays
- Claude CLI must support `--non-interactive` flag
- Terminal UI is basic (no curses-based TUI yet)

## Future Enhancements

- Parallel execution for independent phases
- Web UI for remote monitoring
- Conditional phases (if/else logic)
- Phase templates and reusable patterns
- Remote execution (queue-based)
- Rollback on failure
- Notifications (Slack, email)

## Development

### Project Structure

```
claudeloop/
├── claudeloop              # Main executable
├── lib/
│   ├── parser.sh          # Phase parsing
│   ├── dependencies.sh    # Dependency resolution
│   ├── progress.sh        # Progress tracking
│   ├── retry.sh           # Retry logic
│   └── ui.sh              # Terminal UI
├── tests/
│   ├── run_all_tests.sh   # Test runner
│   └── test_*.sh          # Test files
├── examples/
│   └── PLAN.md.example    # Example plan
└── README.md              # This file
```

### Contributing

1. Write tests first (TDD approach)
2. Ensure all tests pass: `./tests/run_all_tests.sh`
3. Follow existing code style
4. Update README for new features

## License

MIT License - See LICENSE file for details

## Credits

Inspired by [ralph](https://github.com/snarktank/ralph) by snarktank.

Built with ❤️ for better AI-assisted development workflows.
