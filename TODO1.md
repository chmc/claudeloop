# ClaudeLoop POSIX Rewrite - Part 1: lib/retry.sh + lib/ui.sh

## Context

ClaudeLoop currently uses bash-specific features (associative arrays, `**` exponentiation, `$RANDOM`, `echo -e`, `[[ ]]`) which are causing compatibility issues. The goal is to rewrite using pure POSIX shell features.

**Outcome:** `lib/retry.sh` and `lib/ui.sh` converted to POSIX-compatible shell.

---

## POSIX Compatibility Requirements

**Shell Requirements:**
- Must have `/bin/sh` or compatible POSIX shell (dash, bash, ksh, zsh, busybox sh)
- Must support `local` keyword (not strictly POSIX but supported by all modern shells)

**Required Commands (all POSIX):**
- `sed`, `grep`, `date`, `od`, `tr`, `printf`
- Optional but recommended: `/dev/urandom` for better randomness

---

## Data Model Transformation

### Associative Arrays → Numbered Variables

```
PHASE_STATUS[1]         → PHASE_STATUS_1
PHASE_ATTEMPTS[1]       → PHASE_ATTEMPTS_1
```

### Access Pattern

```sh
# Old (bash):
title="${PHASE_TITLES[$phase_num]}"

# New (POSIX):
title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")

# Set value:
eval "PHASE_TITLE_${phase_num}='value'"
```

---

## Key Technical Patterns

### Power Function (replaces `**`)

```sh
power() {
  base="$1"
  exp="$2"
  result=1
  i=0
  while [ "$i" -lt "$exp" ]; do
    result=$((result * base))
    i=$((i + 1))
  done
  echo "$result"
}
```

### Random Function (replaces `$RANDOM`)

```sh
get_random() {
  max="$1"
  if [ -r /dev/urandom ]; then
    random_bytes=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
    echo $((random_bytes % max))
  else
    seed=$(($(date +%s) + $$))
    echo $((seed % max))
  fi
}
```

### printf instead of echo -e

```sh
# Old:
echo -e "${COLOR_BLUE}message${COLOR_RESET}"

# New:
printf '%b\n' "${COLOR_BLUE}message${COLOR_RESET}"
```

---

## Implementation: lib/retry.sh

**Current issues:** `#!/opt/homebrew/bin/bash` shebang, `**` exponentiation, `$RANDOM`, associative array access `${PHASE_ATTEMPTS[$phase_num]}`

**Changes:**

- Line 1: Change shebang to `#!/bin/sh`
- Line 16: Replace `2 ** (attempt - 1)` exponentiation with `power` function call
- Line 23: Replace `$RANDOM` with `get_random` function call
- Line 32: Replace `${PHASE_ATTEMPTS[$phase_num]}` with eval-based access

**Full rewrite of lib/retry.sh:**

```sh
#!/bin/sh

# Retry Logic Library
# Handles retry attempts and exponential backoff

# Configuration
MAX_RETRIES="${MAX_RETRIES:-3}"
BASE_DELAY="${BASE_DELAY:-5}"
MAX_DELAY="${MAX_DELAY:-60}"

# Calculate integer power: base^exp
power() {
  base="$1"
  exp="$2"
  result=1
  i=0
  while [ "$i" -lt "$exp" ]; do
    result=$((result * base))
    i=$((i + 1))
  done
  echo "$result"
}

# Get a random integer in [0, max)
get_random() {
  max="$1"
  if [ -r /dev/urandom ]; then
    random_bytes=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
    echo $((random_bytes % max))
  else
    seed=$(($(date +%s) + $$))
    echo $((seed % max))
  fi
}

# Calculate backoff delay
# Args: $1 - attempt number
# Returns: delay in seconds (stdout)
calculate_backoff() {
  local attempt="$1"
  local exp_value
  exp_value=$(power 2 $((attempt - 1)))
  local delay=$((BASE_DELAY * exp_value))

  if [ "$delay" -gt "$MAX_DELAY" ]; then
    delay=$MAX_DELAY
  fi

  # Add jitter (0-25% of delay)
  local jitter
  jitter=$(get_random $((delay / 4 + 1)))
  echo $((delay + jitter))
}

# Check if phase should be retried
# Args: $1 - phase number
# Returns: 0 if should retry, 1 if max retries exceeded
should_retry_phase() {
  local phase_num="$1"
  local attempts
  attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")

  if [ "$attempts" -lt "$MAX_RETRIES" ]; then
    return 0
  else
    return 1
  fi
}
```

---

## Implementation: lib/ui.sh

**Current issues:** `#!/opt/homebrew/bin/bash` shebang, `${PHASE_STATUS[$i]}` array access, `${PHASE_TITLES[$phase_num]}` array access, `${PHASE_ATTEMPTS[$phase_num]}` array access, `echo -e` usage, `$(seq ...)` loops

**Changes:**

- Line 1: Change shebang to `#!/bin/sh`
- Line 22: Replace `for i in $(seq 1 "$PHASE_COUNT")` with `while` loop
- Line 23: Replace `${PHASE_STATUS[$i]:-pending}` with eval access + default
- Line 40: Replace `${PHASE_STATUS[$phase_num]:-pending}` with eval access
- Line 41: Replace `${PHASE_TITLES[$phase_num]:-Unknown}` with eval access
- Line 64, 84, 86, 88, 95, 101, 107: Replace all `echo -e` with `printf '%b\n'`
- Line 70: Replace `for i in $(seq 1 "$PHASE_COUNT")` with `while` loop
- Line 79: Replace `${PHASE_TITLES[$phase_num]}` with eval access
- Line 80: Replace `${PHASE_ATTEMPTS[$phase_num]}` with eval access

**Full rewrite of lib/ui.sh:**

```sh
#!/bin/sh

# Terminal UI Library
# Handles terminal output and progress display

# Colors
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# Simple mode flag (no fancy UI)
SIMPLE_MODE="${SIMPLE_MODE:-false}"

# Print header
print_header() {
  local plan_file="$1"
  local completed=0
  local i=1
  local status

  while [ "$i" -le "$PHASE_COUNT" ]; do
    status=$(eval "echo \"\$PHASE_STATUS_$i\"")
    status="${status:-pending}"
    if [ "$status" = "completed" ]; then
      completed=$((completed + 1))
    fi
    i=$((i + 1))
  done

  echo "═══════════════════════════════════════════════════════════"
  echo "ClaudeLoop - Phase-by-Phase Execution"
  echo "═══════════════════════════════════════════════════════════"
  echo "Plan: $plan_file"
  echo "Progress: $completed/$PHASE_COUNT phases completed"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
}

# Print phase status
print_phase_status() {
  local phase_num="$1"
  local status
  status=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")
  status="${status:-pending}"
  local title
  title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
  title="${title:-Unknown}"
  local icon="⏳"
  local color="$COLOR_RESET"

  case "$status" in
    completed)
      icon="✅"
      color="$COLOR_GREEN"
      ;;
    in_progress)
      icon="🔄"
      color="$COLOR_YELLOW"
      ;;
    failed)
      icon="❌"
      color="$COLOR_RED"
      ;;
    pending)
      icon="⏳"
      color="$COLOR_RESET"
      ;;
  esac

  printf '%b\n' "${color}${icon} Phase $phase_num: $title${COLOR_RESET}"
}

# Print all phases
print_all_phases() {
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    print_phase_status "$i"
    i=$((i + 1))
  done
  echo ""
}

# Print phase execution header
print_phase_exec_header() {
  local phase_num="$1"
  local title
  title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
  local attempt
  attempt=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")

  echo ""
  echo "───────────────────────────────────────────────────────────"
  printf '%b\n' "${COLOR_BLUE}▶ Executing Phase $phase_num: $title${COLOR_RESET}"
  if [ "$attempt" -gt 1 ]; then
    printf '%b\n' "${COLOR_YELLOW}Attempt $attempt/$MAX_RETRIES${COLOR_RESET}"
  fi
  echo "───────────────────────────────────────────────────────────"
  echo ""
}

# Print success message
print_success() {
  local message="$1"
  printf '%b\n' "${COLOR_GREEN}✓ $message${COLOR_RESET}"
}

# Print error message
print_error() {
  local message="$1"
  printf '%b\n' "${COLOR_RED}✗ $message${COLOR_RESET}" >&2
}

# Print warning message
print_warning() {
  local message="$1"
  printf '%b\n' "${COLOR_YELLOW}⚠ $message${COLOR_RESET}"
}
```

---

## Verification

After implementing:

```sh
# 1. Syntax check
shellcheck -s sh lib/retry.sh lib/ui.sh

# 2. Basic parse test
/bin/sh claudeloop --plan examples/PLAN.md.example --dry-run
```

Expected: no errors, plan parses and phases display correctly.
