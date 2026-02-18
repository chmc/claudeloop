# ClaudeLoop POSIX Rewrite - Part 3: lib/parser.sh + claudeloop

## Context

ClaudeLoop currently uses bash-specific features (associative arrays, `declare -A`, `BASH_REMATCH`, `[[ ]]`, `source`, `${BASH_SOURCE[0]}`, `${0:A:h}`) which are causing compatibility issues. The goal is to rewrite using pure POSIX shell features.

**Outcome:** `lib/parser.sh` and the main `claudeloop` script converted to POSIX-compatible shell.

**Prerequisite:** TODO1.md and TODO2.md must be completed first (lib/retry.sh, lib/ui.sh, lib/dependencies.sh, lib/progress.sh).

---

## POSIX Compatibility Requirements

**Shell Requirements:**
- Must have `/bin/sh` or compatible POSIX shell (dash, bash, ksh, zsh, busybox sh)
- Must support `local` keyword (not strictly POSIX but supported by all modern shells)

**Required Commands (all POSIX):**
- `sed`, `grep`, `date`, `printf`

---

## Data Model Transformation

### Associative Arrays → Numbered Variables

```
PHASE_TITLES[1]         → PHASE_TITLE_1
PHASE_DESCRIPTIONS[1]   → PHASE_DESCRIPTION_1
PHASE_DEPENDENCIES[1]   → PHASE_DEPENDENCIES_1
PHASE_STATUS[1]         → PHASE_STATUS_1
PHASE_ATTEMPTS[1]       → PHASE_ATTEMPTS_1
```

### Access Pattern

```sh
# Get value:
title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")

# Set simple string value:
eval "PHASE_TITLE_${phase_num}='$escaped_value'"

# Set multi-line value (use _desc temp variable):
_desc="$current_description"
eval "PHASE_DESCRIPTION_${phase_num}=\"\${_desc}\""
```

---

## Key Technical Patterns

### Single-quote Escaping for eval

```sh
# When storing user content that may contain single quotes:
phase_title_escaped=$(printf '%s' "$phase_title" | sed "s/'/'\\\\''/g")
eval "PHASE_TITLE_${phase_num}='${phase_title_escaped}'"
# This replaces ' with '\'' (close quote, literal quote, open quote)
```

### Multi-line String Storage

```sh
# Store multi-line in temp variable first to avoid eval quoting issues
_desc="$current_description"
eval "PHASE_DESCRIPTION_${phase_num}=\"\${_desc}\""
```

### Regex → case + grep + sed

```sh
# Phase header detection:
# Old: [[ "$line" =~ ^##\ +Phase\ +([0-9]+):\ *(.*) ]]
# New:
case "$line" in
  "## Phase "*)
    if echo "$line" | grep -qE '^##[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
      phase_num=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
      phase_title=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*[0-9][0-9]*:[[:space:]]*\(.*\)/\1/p')
    fi
    ;;
esac

# Dependency line detection:
# Old: [[ "$line" =~ ^\*\*Depends\ +on:\*\*\ +(.*) ]]
# New:
case "$line" in
  "**Depends on:**"*)
    deps_line=$(echo "$line" | sed 's/^\*\*Depends[[:space:]]*on:[[:space:]]*\*\*[[:space:]]*//')
    deps=$(echo "$deps_line" | sed 's/Phase //g' | grep -oE '[0-9]+' | xargs echo)
    eval "PHASE_DEPENDENCIES_${current_phase}='$deps'"
    ;;
esac
```

### Y/N Response Handling

```sh
# Old: if [[ "$response" =~ ^[Nn]$ ]]; then
# New:
case "$response" in
  [Nn]) # user said no ;;
  *)    # user said yes or other ;;
esac
```

### Script Directory Detection

```sh
# Old (bash/zsh specific):
SCRIPT_DIR="${0:A:h}"                                        # zsh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # bash

# New (POSIX):
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
```

### Source → Dot Command

```sh
# Old:
source "$SCRIPT_DIR/lib/parser.sh"

# New:
. "$SCRIPT_DIR/lib/parser.sh"
```

---

## TDD Workflow

**Steps:**

1. Update `tests/test_parser.sh` with the content below (fixes shebang, `source` → `.`, adds new tests).
2. Run `bats tests/test_parser.sh` — the three new tests should **fail** (red); existing tests may already pass.
3. Implement `lib/parser.sh` and `claudeloop` per the Implementation sections below.
4. Run the tests again — all tests should **pass** (green).

### tests/test_parser.sh (full updated content)

```bash
#!/usr/bin/env bash
# bats file_tags=parser

# Test Phase Parser
# These tests are written FIRST (TDD approach)

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "parse_simple_plan: extracts correct number of phases" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# My Project Plan

## Phase 1: Setup
Create the initial setup.

## Phase 2: Implementation
Implement the feature.

## Phase 3: Testing
Add tests.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "parse_simple_plan: extracts phase titles correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup Database
Create database schema.

## Phase 2: Add API
Create REST endpoints.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [ "$output" = "Setup Database" ]

  run get_phase_title 2
  [ "$status" -eq 0 ]
  [ "$output" = "Add API" ]
}

@test "parse_simple_plan: extracts phase descriptions correctly" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Create the initial setup.
This includes multiple lines.

## Phase 2: Implementation
Implement the feature.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_description 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Create the initial setup."* ]]
  [[ "$output" == *"This includes multiple lines."* ]]
}

@test "parse_dependencies: extracts dependency declarations" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Create database.

## Phase 2: API
**Depends on:** Phase 1

Create API endpoints.

## Phase 3: Tests
**Depends on:** Phase 2

Add tests.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_dependencies 2
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  run get_phase_dependencies 3
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "parse_dependencies: handles multiple dependencies" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Create database.

## Phase 2: API
Create API.

## Phase 3: Integration
**Depends on:** Phase 1, Phase 2

Integrate everything.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_dependencies 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]
  [[ "$output" == *"2"* ]]
}

@test "validate_plan: rejects non-sequential phase numbers" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Setup phase.

## Phase 3: Testing
Testing phase.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sequential"* ]] || [[ "$output" == *"Expected Phase 2"* ]]
}

@test "validate_plan: rejects duplicate phase numbers" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Setup phase.

## Phase 1: Another Setup
Another setup phase.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate"* ]] || [[ "$output" == *"Duplicate"* ]] || [[ "$output" == *"Expected Phase 2, found Phase 1"* ]]
}

@test "validate_plan: rejects invalid dependency references" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
Setup phase.

## Phase 2: Implementation
**Depends on:** Phase 5

Implementation phase.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-existent"* ]] || [[ "$output" == *"invalid"* ]] || [[ "$output" == *"depends on"* ]]
}

@test "parse_plan: handles empty lines and spacing" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# Project

## Phase 1: Setup

Create setup.


## Phase 2: Implementation

Implement feature.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "parse_plan: ignores non-phase headers" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
# Project Title

Some intro text.

## Phase 1: Setup
Create setup.

### Subsection
This is not a phase.

## Phase 2: Implementation
Implement feature.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "parse_plan: handles single-quote in phase title" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Install 'foo' package
Install the foo package.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_title 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"* ]]
}

@test "parse_plan: preserves dollar sign in description without expanding" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Configure
Set the $DEBUG variable to true.
EOF

  parse_plan "$TEST_DIR/PLAN.md"

  run get_phase_description 1
  [ "$status" -eq 0 ]
  [[ "$output" == *'$DEBUG'* ]]
}

@test "validate_plan: rejects forward dependency" {
  cat > "$TEST_DIR/PLAN.md" << 'EOF'
## Phase 1: Setup
**Depends on:** Phase 2

Setup phase.

## Phase 2: Implementation
Implementation phase.
EOF

  run parse_plan "$TEST_DIR/PLAN.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"forward"* ]] || [[ "$output" == *"cannot depend"* ]]
}
```

### tests/test_killswitch.sh (update after TODO2)

`tests/test_killswitch.sh` already uses POSIX flat variables for the interrupt-handling assertions. After TODO2 completes, make two fixes:

1. Remove the stale comment on line 110:
   ```sh
   # progress.sh still uses associative arrays; updated in TODO2/3
   ```

2. Change lines 111–113 from associative-array syntax to flat-variable syntax:
   ```sh
   # Before:
   [ "${PHASE_STATUS[1]}" = "completed" ]
   [ "${PHASE_STATUS[2]}" = "pending" ]
   [ "${PHASE_STATUS[3]}" = "pending" ]

   # After:
   [ "$PHASE_STATUS_1" = "completed" ]
   [ "$PHASE_STATUS_2" = "pending" ]
   [ "$PHASE_STATUS_3" = "pending" ]
   ```

---

## Implementation: lib/parser.sh

**Current issues:** `#!/opt/homebrew/bin/bash` shebang, `declare -A` array declarations, `PHASE_TITLES=()` array resets, `[[ "$line" =~ ... ]]` + `BASH_REMATCH`, `${PHASE_TITLES[$phase_num]:-}` array access, `PHASE_TITLES[$phase_num]="..."` array assignment, `${!PHASE_DEPENDENCIES[@]}` key iteration, `current_description+=$'\n'` append syntax, `current_description+="$line"` append syntax

**Changes:**

- Line 1: Change shebang to `#!/bin/sh`
- Lines 8-10: Remove all `declare -A` declarations
- Lines 25-27: Remove array reset lines (`PHASE_TITLES=()` etc.)
- Lines 40-43: Replace `[[ "$line" =~ ... ]]` + `BASH_REMATCH` with `case` + `grep` + `sed`
- Line 46: Replace `PHASE_DESCRIPTIONS[$current_phase]="$current_description"` with eval + temp var
- Line 56: Replace `${PHASE_TITLES[$phase_num]:-}` check with eval + empty check
- Line 62: Replace `PHASE_TITLES[$phase_num]="$phase_title"` with escaped eval assignment
- Lines 71-83: Replace `[[ "$line" =~ ... ]]` dependency regex + while loop with `case` + `grep -oE`
- Lines 89-92: Replace `+=` string append syntax with POSIX concatenation
- Line 99: Replace `PHASE_DESCRIPTIONS[$current_phase]="$current_description"` with eval + temp var
- Line 103: Replace `for phase_num in "${!PHASE_DEPENDENCIES[@]}"` with `while` loop
- Line 104: Replace `${PHASE_DEPENDENCIES[$phase_num]}` with eval access
- Line 106: Replace `${PHASE_TITLES[$dep]:-}` with eval access
- Lines 134, 141, 148: Replace array access in getter functions with eval

**Full rewrite of lib/parser.sh:**

```sh
#!/bin/sh

# Phase Parser Library
# Parses PLAN.md files and extracts phase information

PHASE_COUNT=0

# Parse a PLAN.md file
# Args: $1 - path to PLAN.md file
# Returns: 0 on success, non-zero on error
parse_plan() {
  local plan_file="$1"

  if [ ! -f "$plan_file" ]; then
    echo "Error: Plan file not found: $plan_file" >&2
    return 1
  fi

  # Reset global state
  PHASE_COUNT=0

  local current_phase=""
  local current_description=""
  local in_phase=false
  local line_num=0
  local expected_phase=1

  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))

    # Check if this is a phase header: ## Phase N: Title
    case "$line" in
      "## Phase "*)
        if echo "$line" | grep -qE '^##[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
          local phase_num
          phase_num=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
          local phase_title
          phase_title=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*[0-9][0-9]*:[[:space:]]*\(.*\)/\1/p')

          # Save previous phase description if exists
          if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
            _desc="$current_description"
            eval "PHASE_DESCRIPTION_${current_phase}=\"\${_desc}\""
          fi

          # Validate sequential numbering
          if [ "$phase_num" -ne "$expected_phase" ]; then
            echo "Error: Phase numbers must be sequential. Expected Phase $expected_phase, found Phase $phase_num at line $line_num" >&2
            return 1
          fi

          # Check for duplicate phase numbers
          local existing_title
          existing_title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
          if [ -n "$existing_title" ]; then
            echo "Error: Duplicate phase number $phase_num at line $line_num" >&2
            return 1
          fi

          # Store phase title (escape single quotes for eval safety)
          local phase_title_escaped
          phase_title_escaped=$(printf '%s' "$phase_title" | sed "s/'/'\\\\''/g")
          eval "PHASE_TITLE_${phase_num}='${phase_title_escaped}'"

          # Initialize dependencies to empty
          eval "PHASE_DEPENDENCIES_${phase_num}=''"

          current_phase="$phase_num"
          current_description=""
          in_phase=true
          PHASE_COUNT=$phase_num
          expected_phase=$((expected_phase + 1))
        fi
        ;;
      *)
        if [ "$in_phase" = true ]; then
          # Check for dependency declaration: **Depends on:** Phase X, Phase Y
          case "$line" in
            "**Depends on:**"*)
              local deps_line
              deps_line=$(echo "$line" | sed 's/^\*\*Depends[[:space:]]*on:[[:space:]]*\*\*[[:space:]]*//')
              local deps
              deps=$(echo "$deps_line" | sed 's/Phase //g' | grep -oE '[0-9]+' | xargs echo)
              eval "PHASE_DEPENDENCIES_${current_phase}='$deps'"
              ;;
            *)
              # Accumulate description
              if [ -n "$current_description" ]; then
                current_description="${current_description}
${line}"
              else
                current_description="$line"
              fi
              ;;
          esac
        fi
        ;;
    esac
  done < "$plan_file"

  # Save last phase description
  if [ "$in_phase" = true ] && [ -n "$current_phase" ]; then
    _desc="$current_description"
    eval "PHASE_DESCRIPTION_${current_phase}=\"\${_desc}\""
  fi

  # Validate dependencies
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    local deps
    deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$i\"")
    if [ -n "$deps" ]; then
      for dep in $deps; do
        local dep_title
        dep_title=$(eval "echo \"\$PHASE_TITLE_$dep\"")
        if [ -z "$dep_title" ]; then
          echo "Error: Phase $i depends on non-existent Phase $dep" >&2
          return 1
        fi
        if [ "$dep" -ge "$i" ]; then
          echo "Error: Phase $i cannot depend on Phase $dep (forward or self dependency)" >&2
          return 1
        fi
      done
    fi
    i=$((i + 1))
  done

  if [ "$PHASE_COUNT" -eq 0 ]; then
    echo "Error: No phases found in plan file" >&2
    return 1
  fi

  return 0
}

# Get total number of phases
get_phase_count() {
  echo "$PHASE_COUNT"
}

# Get title of a specific phase
# Args: $1 - phase number
get_phase_title() {
  local phase_num="$1"
  eval "echo \"\$PHASE_TITLE_$phase_num\""
}

# Get description of a specific phase
# Args: $1 - phase number
get_phase_description() {
  local phase_num="$1"
  eval "echo \"\$PHASE_DESCRIPTION_$phase_num\""
}

# Get dependencies of a specific phase
# Args: $1 - phase number
# Returns: space-separated list of phase numbers
get_phase_dependencies() {
  local phase_num="$1"
  eval "echo \"\$PHASE_DEPENDENCIES_$phase_num\""
}

# Get all phase numbers
get_all_phases() {
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    echo "$i"
    i=$((i + 1))
  done
}
```

---

## Implementation: claudeloop (Main Script)

**Current issues:** `#!/opt/homebrew/bin/bash` shebang, `set -euo pipefail` (bash-specific `pipefail`), `${BASH_SOURCE[0]}` script dir detection, `source` commands, `[[ "$response" =~ ^[Nn]$ ]]` regex, `${PHASE_STATUS[$CURRENT_PHASE]:-}` array access, `PHASE_STATUS[$CURRENT_PHASE]="pending"` assignment, `PHASE_ATTEMPTS[$CURRENT_PHASE]=$((... - 1))` arithmetic, `${PHASE_TITLES[$phase_num]}` + `${PHASE_DESCRIPTIONS[$phase_num]}` access, `for i in $(seq ...)` loops with `${PHASE_STATUS[$i]}`, `${PHASE_ATTEMPTS[$next_phase]}` access

**Changes:**

- Line 1: Change shebang to `#!/bin/sh`
- Line 6: Replace `set -euo pipefail` with `set -eu` (`pipefail` is not POSIX)
- Line 9: Replace `${BASH_SOURCE[0]}` with `$0`
- Lines 12-16: Replace `source` with `.` (dot command)
- Line 55: Replace `[[ "$response" =~ ^[Nn]$ ]]` with `case`
- Lines 104-108: Replace array access in interrupt handler with eval
- Line 222: Replace `[[ ! "$response" =~ ^[Yy]$ ]]` with `case`
- Lines 238-239: Replace `${PHASE_TITLES[$phase_num]}` + `${PHASE_DESCRIPTIONS[$phase_num]}` with eval
- Lines 311-318: Replace `for i in $(seq ...)` + `${PHASE_STATUS[$i]}` with `while` + eval
- Line 341: Replace `${PHASE_ATTEMPTS[$next_phase]}` with eval

**Full rewrite of claudeloop:**

```sh
#!/bin/sh

# ClaudeLoop - Phase-by-Phase Execution Tool
# Executes multi-phase plans by spawning fresh Claude instances per phase

set -eu

# Script directory
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Source libraries
. "$SCRIPT_DIR/lib/parser.sh"
. "$SCRIPT_DIR/lib/dependencies.sh"
. "$SCRIPT_DIR/lib/progress.sh"
. "$SCRIPT_DIR/lib/retry.sh"
. "$SCRIPT_DIR/lib/ui.sh"

# Default configuration
PLAN_FILE="${PLAN_FILE:-PLAN.md}"
PROGRESS_FILE="${PROGRESS_FILE:-PROGRESS.md}"
STATE_FILE=".claudeloop/state/current.json"
LOCK_FILE=".claudeloop/lock"
RESET_PROGRESS=false
START_PHASE=""
DRY_RUN=false
INTERRUPTED=false
CURRENT_PHASE=""

# Save current state to state file
save_state() {
  mkdir -p "$(dirname "$STATE_FILE")"

  cat > "$STATE_FILE" << EOF
{
  "plan_file": "$PLAN_FILE",
  "progress_file": "$PROGRESS_FILE",
  "current_phase": "$CURRENT_PHASE",
  "interrupted": true,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Load state from state file
load_state() {
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi

  # Simple parsing of JSON (basic implementation)
  if grep -q '"interrupted": true' "$STATE_FILE"; then
    print_warning "Found interrupted session"
    printf 'Resume from last checkpoint? (Y/n) '
    read -r response
    case "$response" in
      [Nn])
        rm -f "$STATE_FILE"
        return 1
        ;;
    esac
    return 0
  fi

  return 1
}

# Clear state file
clear_state() {
  rm -f "$STATE_FILE"
}

# Create lock file
create_lock() {
  local lock_dir
  lock_dir="$(dirname "$LOCK_FILE")"
  mkdir -p "$lock_dir"

  if [ -f "$LOCK_FILE" ]; then
    local pid
    pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      print_error "Another instance is running (PID: $pid)"
      exit 1
    else
      print_warning "Removing stale lock file"
      rm -f "$LOCK_FILE"
    fi
  fi

  echo $$ > "$LOCK_FILE"
}

# Remove lock file
remove_lock() {
  rm -f "$LOCK_FILE"
}

# Signal handler for graceful shutdown
handle_interrupt() {
  INTERRUPTED=true
  echo ""
  print_warning "Interrupt received (Ctrl+C)"
  print_warning "Saving state and shutting down gracefully..."

  # Mark current phase as pending if it was in progress
  if [ -n "$CURRENT_PHASE" ]; then
    local _status
    _status=$(eval "echo \"\$PHASE_STATUS_$CURRENT_PHASE\"")
    if [ "$_status" = "in_progress" ]; then
      print_warning "Marking Phase $CURRENT_PHASE as pending for retry"
      eval "PHASE_STATUS_${CURRENT_PHASE}=pending"
      # Don't count this as an attempt since it was interrupted
      local _attempts
      _attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$CURRENT_PHASE\"")
      eval "PHASE_ATTEMPTS_${CURRENT_PHASE}=$((_attempts - 1))"
    fi
  fi

  # Save progress
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"

  # Save state for resume
  save_state

  # Cleanup
  remove_lock

  echo ""
  print_success "State saved successfully"
  print_success "Resume with: $0 --continue"
  exit 130
}

# Cleanup on exit
cleanup() {
  remove_lock
  if [ "$INTERRUPTED" = false ]; then
    clear_state
  fi
}

# Usage information
usage() {
  cat << EOF
ClaudeLoop - Phase-by-Phase Execution Tool

Usage: $(basename "$0") [OPTIONS]

Options:
  --plan <file>        Plan file to execute (default: PLAN.md)
  --progress <file>    Progress file (default: PROGRESS.md)
  --reset              Reset progress and start from beginning
  --continue           Continue from last checkpoint (default)
  --phase <n>          Start from specific phase number
  --dry-run            Validate plan without execution
  --max-retries <n>    Maximum retry attempts per phase (default: 3)
  --simple             Use simple output mode (no colors/fancy UI)
  --help               Show this help message

Examples:
  $(basename "$0") --plan my_plan.md
  $(basename "$0") --reset
  $(basename "$0") --phase 3 --continue

EOF
}

# Parse command-line arguments
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --plan)
        PLAN_FILE="$2"
        shift 2
        ;;
      --progress)
        PROGRESS_FILE="$2"
        shift 2
        ;;
      --reset)
        RESET_PROGRESS=true
        shift
        ;;
      --continue)
        # Default behavior
        shift
        ;;
      --phase)
        START_PHASE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --max-retries)
        MAX_RETRIES="$2"
        shift 2
        ;;
      --simple)
        SIMPLE_MODE=true
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Error: Unknown option $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

# Validate environment
validate_environment() {
  # Check if in git repository
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository. ClaudeLoop requires git for safety."
    exit 1
  fi

  # Check for uncommitted changes
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    print_warning "Uncommitted changes detected. Consider committing before starting."
    printf 'Continue anyway? (y/N) '
    read -r response
    case "$response" in
      [Yy]) ;;  # Continue
      *)
        echo "Aborted."
        exit 0
        ;;
    esac
  fi

  # Check if claude CLI is available
  if ! command -v claude > /dev/null 2>&1; then
    print_error "claude CLI not found. Please install it first."
    exit 1
  fi
}

# Execute a single phase
execute_phase() {
  local phase_num="$1"
  local title
  title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
  local description
  description=$(eval "echo \"\$PHASE_DESCRIPTION_$phase_num\"")
  local log_file=".claudeloop/logs/phase-$phase_num.log"

  # Set current phase for interrupt handler
  CURRENT_PHASE="$phase_num"

  # Create log directory
  mkdir -p ".claudeloop/logs"

  # Update status
  update_phase_status "$phase_num" "in_progress"
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"

  print_phase_exec_header "$phase_num"

  # Construct prompt for Claude
  local prompt="You are executing Phase $phase_num of a multi-phase plan.

## Phase $phase_num: $title

$description

## Context
- This is a fresh Claude instance dedicated to this phase only
- Previous phases have been completed and committed to git
- Review recent git history and existing code before implementing
- When done, ensure all changes are tested and working
- Commit your changes when complete

## Task
Implement the above phase completely. Make sure to:
1. Read relevant existing code
2. Implement required changes
3. Test your implementation thoroughly
4. Commit your changes when complete"

  # Execute claude
  echo "Executing Claude CLI..."
  if echo "$prompt" | claude --non-interactive 2>&1 | tee "$log_file"; then
    print_success "Phase $phase_num completed successfully"
    update_phase_status "$phase_num" "completed"
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"
    CURRENT_PHASE=""
    return 0
  else
    print_error "Phase $phase_num failed"
    update_phase_status "$phase_num" "failed"
    write_progress "$PROGRESS_FILE" "$PLAN_FILE"
    CURRENT_PHASE=""
    return 1
  fi
}

# Main execution loop
main_loop() {
  local continue_execution=true

  while $continue_execution; do
    # Check for interruption
    if $INTERRUPTED; then
      print_warning "Execution interrupted"
      return 130
    fi

    # Find next runnable phase
    local next_phase
    if ! next_phase=$(find_next_phase); then
      # No runnable phases - check why
      local has_pending=false
      local has_failed=false
      local i=1

      while [ "$i" -le "$PHASE_COUNT" ]; do
        local _status
        _status=$(eval "echo \"\$PHASE_STATUS_$i\"")
        if [ "$_status" = "pending" ]; then
          has_pending=true
        fi
        if [ "$_status" = "failed" ]; then
          has_failed=true
        fi
        i=$((i + 1))
      done

      if ! $has_pending && ! $has_failed; then
        # All phases completed
        print_success "All phases completed!"
        return 0
      elif $has_pending; then
        print_error "Remaining phases are blocked by dependencies"
        return 1
      else
        print_error "Some phases failed and no more phases can run"
        return 1
      fi
    fi

    # Execute the next phase
    if execute_phase "$next_phase"; then
      # Success - continue to next phase
      continue
    else
      # Failure - check if we should retry
      if should_retry_phase "$next_phase"; then
        local _attempts
        _attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$next_phase\"")
        local delay
        delay=$(calculate_backoff "$_attempts")
        print_warning "Retrying phase $next_phase after $delay seconds..."
        sleep "$delay"
        continue
      else
        print_error "Phase $next_phase failed after ${MAX_RETRIES} attempts"
        return 1
      fi
    fi
  done
}

# Main function
main() {
  # Set up signal handlers and cleanup
  trap handle_interrupt INT TERM
  trap cleanup EXIT

  # Parse arguments
  parse_args "$@"

  # Print header
  print_header "$PLAN_FILE"

  # Check if plan file exists
  if [ ! -f "$PLAN_FILE" ]; then
    print_error "Plan file not found: $PLAN_FILE"
    exit 1
  fi

  # Parse plan
  print_success "Parsing plan file: $PLAN_FILE"
  if ! parse_plan "$PLAN_FILE"; then
    print_error "Failed to parse plan file"
    exit 1
  fi

  echo "Found $PHASE_COUNT phases"
  echo ""

  # Validate environment (skip in dry-run)
  if ! $DRY_RUN; then
    validate_environment
  fi

  # Check for interrupted session (skip in dry-run and reset)
  if ! $DRY_RUN && ! $RESET_PROGRESS; then
    load_state || true
  fi

  # Initialize progress
  if $RESET_PROGRESS; then
    rm -f "$PROGRESS_FILE" "$STATE_FILE"
  fi

  init_progress "$PROGRESS_FILE"

  # Print phase list
  print_all_phases

  # Dry run mode
  if $DRY_RUN; then
    print_success "Dry run complete - plan is valid"
    exit 0
  fi

  # Create lock file to prevent concurrent runs
  create_lock

  print_warning "Press Ctrl+C at any time to stop (state will be saved)"
  echo ""

  # Execute phases
  main_loop
  local exit_code=$?

  # Final progress update
  write_progress "$PROGRESS_FILE" "$PLAN_FILE"

  # Clear state on successful completion
  if [ $exit_code -eq 0 ]; then
    clear_state
  fi

  # Print final summary
  echo ""
  print_header "$PLAN_FILE"
  print_all_phases

  exit $exit_code
}

# Run main function
main "$@"
```

---

## Verification

```sh
# 0. Write / update tests first, confirm they fail
bats tests/test_parser.sh

# 1. Implement, then confirm tests pass
bats tests/test_parser.sh tests/test_killswitch.sh

# 2. Full suite
./tests/run_all_tests.sh

# 3. Syntax check
shellcheck -s sh claudeloop lib/*.sh
```
