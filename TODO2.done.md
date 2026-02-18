# ClaudeLoop POSIX Rewrite - Part 2: lib/dependencies.sh + lib/progress.sh

## Context

ClaudeLoop currently uses bash-specific features (associative arrays, `[[ ]]`, `BASH_REMATCH`, `declare -A`) which are causing compatibility issues. The goal is to rewrite using pure POSIX shell features.

**Outcome:** `lib/dependencies.sh` and `lib/progress.sh` converted to POSIX-compatible shell.

**Prerequisite:** TODO1.md (lib/retry.sh + lib/ui.sh) must be completed first, as the data model patterns established there are used here.

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
PHASE_STATUS[1]         → PHASE_STATUS_1
PHASE_START_TIME[1]     → PHASE_START_TIME_1
PHASE_END_TIME[1]       → PHASE_END_TIME_1
PHASE_ATTEMPTS[1]       → PHASE_ATTEMPTS_1
PHASE_DEPENDENCIES[1]   → PHASE_DEPENDENCIES_1
PHASE_TITLES[1]         → PHASE_TITLE_1
```

### Access Pattern

```sh
# Get value:
status=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")

# Set value:
eval "PHASE_STATUS_${phase_num}='value'"
```

### Space-separated Strings (replaces arrays for visited/rec_stack)

```sh
# Old (bash arrays):
local visited=()
visited+=("$phase")
if [[ " ${visited[*]} " == *" $phase "* ]]; then

# New (POSIX space-separated strings):
visited=""
visited="$visited $phase"
case " $visited " in
  *" $phase "*) # found ;;
esac
```

---

## Key Technical Patterns

### Membership Test in Space-separated List

```sh
case " $list " in
  *" $item "*) echo "found" ;;
  *) echo "not found" ;;
esac
```

### Remove Item from Space-separated List

```sh
new_list=""
for item in $list; do
  [ "$item" != "$to_remove" ] && new_list="$new_list $item"
done
list="$new_list"
```

### Regex → grep + sed

```sh
# Old:
if [[ "$line" =~ ^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+([0-9]+): ]]; then
  current_phase="${BASH_REMATCH[1]}"

# New:
if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
  current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
fi
```

---

## TDD Workflow

**Steps:**

1. Create `tests/test_dependencies.sh` and `tests/test_progress.sh` with the content below.
2. Run `bats tests/test_dependencies.sh tests/test_progress.sh` — all tests should **fail** (red).
3. Implement `lib/dependencies.sh` and `lib/progress.sh` per the Implementation sections below.
4. Run the tests again — all tests should **pass** (green).

### tests/test_dependencies.sh

```bash
#!/usr/bin/env bash
# bats file_tags=dependencies

# Tests for lib/dependencies.sh POSIX-compatible implementation

setup() {
  . "${BATS_TEST_DIRNAME}/../lib/dependencies.sh"
  # 3-phase chain: 1 (no deps), 2 (dep: 1), 3 (deps: 1 2)
  PHASE_COUNT=3
  PHASE_STATUS_1="pending"
  PHASE_STATUS_2="pending"
  PHASE_STATUS_3="pending"
  PHASE_DEPENDENCIES_1=""
  PHASE_DEPENDENCIES_2="1"
  PHASE_DEPENDENCIES_3="1 2"
}

# --- is_phase_runnable() ---

@test "is_phase_runnable: pending phase with no deps is runnable" {
  run is_phase_runnable 1
  [ "$status" -eq 0 ]
}

@test "is_phase_runnable: failed phase with no deps is runnable" {
  PHASE_STATUS_1="failed"
  run is_phase_runnable 1
  [ "$status" -eq 0 ]
}

@test "is_phase_runnable: completed phase is not runnable" {
  PHASE_STATUS_1="completed"
  run is_phase_runnable 1
  [ "$status" -eq 1 ]
}

@test "is_phase_runnable: in_progress phase is not runnable" {
  PHASE_STATUS_1="in_progress"
  run is_phase_runnable 1
  [ "$status" -eq 1 ]
}

@test "is_phase_runnable: phase with incomplete dep is not runnable" {
  run is_phase_runnable 2
  [ "$status" -eq 1 ]
}

@test "is_phase_runnable: phase with all deps completed is runnable" {
  PHASE_STATUS_1="completed"
  run is_phase_runnable 2
  [ "$status" -eq 0 ]
}

# --- find_next_phase() ---

@test "find_next_phase: returns first runnable phase number" {
  run find_next_phase
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "find_next_phase: skips completed phases" {
  PHASE_STATUS_1="completed"
  run find_next_phase
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "find_next_phase: returns exit code 1 when no runnable phase exists" {
  PHASE_STATUS_1="in_progress"
  PHASE_STATUS_2="completed"
  PHASE_STATUS_3="completed"
  run find_next_phase
  [ "$status" -eq 1 ]
}

# --- detect_dependency_cycles() ---

@test "detect_dependency_cycles: acyclic graph returns 0" {
  run detect_dependency_cycles
  [ "$status" -eq 0 ]
}

@test "detect_dependency_cycles: cycle returns 1 with error message" {
  PHASE_COUNT=2
  PHASE_DEPENDENCIES_1="2"
  PHASE_DEPENDENCIES_2="1"
  run detect_dependency_cycles
  [ "$status" -eq 1 ]
  [ -n "$output" ]
}

# --- get_blocked_phases() ---

@test "get_blocked_phases: returns phases that depend on the given phase" {
  run get_blocked_phases 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
  [[ "$output" == *"3"* ]]
}

@test "get_blocked_phases: returns empty string when no dependents" {
  run get_blocked_phases 3
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
```

### tests/test_progress.sh

```bash
#!/usr/bin/env bash
# bats file_tags=progress

# Tests for lib/progress.sh POSIX-compatible implementation

setup() {
  export TEST_DIR="$(mktemp -d)"
  . "${BATS_TEST_DIRNAME}/../lib/progress.sh"
  . "${BATS_TEST_DIRNAME}/../lib/parser.sh"
  PHASE_COUNT=3
  PHASE_TITLE_1="Phase One"
  PHASE_TITLE_2="Phase Two"
  PHASE_TITLE_3="Phase Three"
  PHASE_DEPENDENCIES_1=""
  PHASE_DEPENDENCIES_2=""
  PHASE_DEPENDENCIES_3=""
}

teardown() {
  rm -rf "$TEST_DIR"
}

# --- init_progress() ---

@test "init_progress: sets all phases to pending" {
  init_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "pending" ]
  [ "$PHASE_STATUS_2" = "pending" ]
  [ "$PHASE_STATUS_3" = "pending" ]
}

@test "init_progress: sets all attempt counts to 0" {
  init_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_ATTEMPTS_1" = "0" ]
  [ "$PHASE_ATTEMPTS_2" = "0" ]
  [ "$PHASE_ATTEMPTS_3" = "0" ]
}

@test "init_progress: reads existing file when present" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Attempts: 1

### ⏳ Phase 2: Phase Two
Status: pending

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  init_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "pending" ]
}

# --- read_progress() ---

@test "read_progress: restores phase status" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed

### ❌ Phase 2: Phase Two
Status: failed

### ⏳ Phase 3: Phase Three
Status: pending
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "failed" ]
  [ "$PHASE_STATUS_3" = "pending" ]
}

@test "read_progress: restores start and end times" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ✅ Phase 1: Phase One
Status: completed
Started: 2026-02-18 10:00:00
Completed: 2026-02-18 10:05:00
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_START_TIME_1" = "2026-02-18 10:00:00" ]
  [ "$PHASE_END_TIME_1" = "2026-02-18 10:05:00" ]
}

@test "read_progress: restores attempt count" {
  cat > "$TEST_DIR/PROGRESS.md" << 'EOF'
### ❌ Phase 1: Phase One
Status: failed
Attempts: 3
EOF
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_ATTEMPTS_1" = "3" ]
}

@test "read_progress: returns 0 when file does not exist" {
  run read_progress "$TEST_DIR/nonexistent.md"
  [ "$status" -eq 0 ]
}

# --- write_progress() ---

@test "write_progress: creates the progress file" {
  PHASE_STATUS_1="pending"   PHASE_ATTEMPTS_1=0
  PHASE_STATUS_2="pending"   PHASE_ATTEMPTS_2=0
  PHASE_STATUS_3="pending"   PHASE_ATTEMPTS_3=0
  write_progress "$TEST_DIR/PROGRESS.md" "PLAN.md"
  [ -f "$TEST_DIR/PROGRESS.md" ]
}

@test "write_progress: does not leave .tmp file behind (atomic write)" {
  PHASE_STATUS_1="pending"   PHASE_ATTEMPTS_1=0
  PHASE_STATUS_2="pending"   PHASE_ATTEMPTS_2=0
  PHASE_STATUS_3="pending"   PHASE_ATTEMPTS_3=0
  write_progress "$TEST_DIR/PROGRESS.md" "PLAN.md"
  [ ! -f "$TEST_DIR/PROGRESS.md.tmp" ]
}

@test "write_progress: round-trip with read_progress is stable" {
  PHASE_STATUS_1="completed" PHASE_ATTEMPTS_1=1
  PHASE_STATUS_2="failed"    PHASE_ATTEMPTS_2=2
  PHASE_STATUS_3="pending"   PHASE_ATTEMPTS_3=0
  write_progress "$TEST_DIR/PROGRESS.md" "PLAN.md"
  PHASE_STATUS_1="pending" PHASE_STATUS_2="pending" PHASE_STATUS_3="pending"
  PHASE_ATTEMPTS_1=0 PHASE_ATTEMPTS_2=0 PHASE_ATTEMPTS_3=0
  read_progress "$TEST_DIR/PROGRESS.md"
  [ "$PHASE_STATUS_1" = "completed" ]
  [ "$PHASE_STATUS_2" = "failed" ]
  [ "$PHASE_ATTEMPTS_2" = "2" ]
}

# --- update_phase_status() ---

@test "update_phase_status: sets status" {
  PHASE_STATUS_1="pending" PHASE_ATTEMPTS_1=0
  update_phase_status 1 "in_progress"
  [ "$PHASE_STATUS_1" = "in_progress" ]
}

@test "update_phase_status: sets PHASE_START_TIME for in_progress" {
  PHASE_ATTEMPTS_1=0 PHASE_START_TIME_1=""
  update_phase_status 1 "in_progress"
  [ -n "$PHASE_START_TIME_1" ]
}

@test "update_phase_status: sets PHASE_END_TIME for completed" {
  PHASE_ATTEMPTS_1=0 PHASE_END_TIME_1=""
  update_phase_status 1 "completed"
  [ -n "$PHASE_END_TIME_1" ]
}

@test "update_phase_status: sets PHASE_END_TIME for failed" {
  PHASE_ATTEMPTS_1=0 PHASE_END_TIME_1=""
  update_phase_status 1 "failed"
  [ -n "$PHASE_END_TIME_1" ]
}

@test "update_phase_status: increments PHASE_ATTEMPTS for in_progress" {
  PHASE_ATTEMPTS_1=0
  update_phase_status 1 "in_progress"
  [ "$PHASE_ATTEMPTS_1" = "1" ]
}

@test "update_phase_status: increments PHASE_ATTEMPTS on second attempt" {
  PHASE_ATTEMPTS_1=1
  update_phase_status 1 "in_progress"
  [ "$PHASE_ATTEMPTS_1" = "2" ]
}
```

---

## Implementation: lib/dependencies.sh

**Current issues:** `#!/opt/homebrew/bin/bash` shebang, `${PHASE_STATUS[$phase_num]}` array access, `${PHASE_DEPENDENCIES[$phase_num]}` array access, `[[ ]]` pattern matching, bash array operations (`visited=()`, `rec_stack+=()`, `${rec_stack[@]/$phase}`), `$(seq ...)` loops

**Changes:**

- Line 1: Change shebang to `#!/bin/sh`
- Line 12: Replace `${PHASE_STATUS[$phase_num]}` with eval access
- Line 20: Replace `${PHASE_DEPENDENCIES[$phase_num]}` with eval access
- Line 22: Replace `${PHASE_STATUS[$dep]}` with eval access
- Lines 35, 52: Replace `for i in $(seq 1 "$PHASE_COUNT")` with `while` loops
- Lines 48-49: Replace `local visited=()` and `local rec_stack=()` with empty strings
- Line 67: Replace `[[ " ${rec_stack[*]} " == *" $phase "* ]]` with `case`
- Line 73: Replace `[[ " ${visited[*]} " == *" $phase "* ]]` with `case`
- Line 77: Replace `rec_stack+=("$phase")` with string append
- Line 80: Replace `${PHASE_DEPENDENCIES[$phase]}` with eval access
- Lines 87-90: Replace array filter with string-based filter
- Line 102: Replace `${PHASE_DEPENDENCIES[$phase]}` with eval access
- Line 104: Replace `[[ " $deps " == *" $blocker_phase "* ]]` with `case`

**Full rewrite of lib/dependencies.sh:**

```sh
#!/bin/sh

# Dependency Resolution Library
# Handles phase dependency checking, cycle detection, and execution order

# Check if a phase is runnable (all dependencies completed)
# Args: $1 - phase number
# Uses global: PHASE_DEPENDENCIES_N, PHASE_STATUS_N
# Returns: 0 if runnable, 1 if not
is_phase_runnable() {
  local phase_num="$1"
  local status
  status=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")

  # Phase must be pending or failed (not completed or in_progress)
  if [ "$status" != "pending" ] && [ "$status" != "failed" ]; then
    return 1
  fi

  # Check all dependencies are completed
  local deps
  deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase_num\"")
  for dep in $deps; do
    local dep_status
    dep_status=$(eval "echo \"\$PHASE_STATUS_$dep\"")
    if [ "$dep_status" != "completed" ]; then
      return 1
    fi
  done

  return 0
}

# Find next runnable phase
# Uses global: PHASE_COUNT, PHASE_STATUS_N
# Returns: phase number (stdout) or empty if none
find_next_phase() {
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    if is_phase_runnable "$i"; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# Detect circular dependencies
# Returns: 0 if no cycles, 1 if cycle detected (with error message)
detect_dependency_cycles() {
  local visited=""
  local rec_stack=""

  # DFS-based cycle detection
  local phase=1
  while [ "$phase" -le "$PHASE_COUNT" ]; do
    if ! _dfs_cycle_check "$phase"; then
      return 1
    fi
    phase=$((phase + 1))
  done

  return 0
}

# Helper: DFS for cycle detection
# Args: $1 - current phase
# Uses/modifies outer scope: visited, rec_stack (space-separated strings)
_dfs_cycle_check() {
  local phase="$1"

  # Check if already on recursion stack (cycle detected)
  case " $rec_stack " in
    *" $phase "*)
      echo "Error: Circular dependency detected involving Phase $phase" >&2
      return 1
      ;;
  esac

  # Skip if already fully processed
  case " $visited " in
    *" $phase "*) return 0 ;;
  esac

  rec_stack="$rec_stack $phase"

  # Check all dependencies
  local deps
  deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase\"")
  for dep in $deps; do
    if ! _dfs_cycle_check "$dep"; then
      return 1
    fi
  done

  # Remove from recursion stack, add to visited
  local new_stack=""
  for item in $rec_stack; do
    [ "$item" != "$phase" ] && new_stack="$new_stack $item"
  done
  rec_stack="$new_stack"
  visited="$visited $phase"

  return 0
}

# Get all phases that are blocked by a given phase
# Args: $1 - phase number
# Returns: space-separated list of blocked phase numbers
get_blocked_phases() {
  local blocker_phase="$1"
  local blocked=""
  local phase=1

  while [ "$phase" -le "$PHASE_COUNT" ]; do
    local deps
    deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase\"")
    case " $deps " in
      *" $blocker_phase "*)
        blocked="$blocked $phase"
        ;;
    esac
    phase=$((phase + 1))
  done

  echo "${blocked# }"
}
```

---

## Implementation: lib/progress.sh

**Current issues:** `#!/opt/homebrew/bin/bash` shebang, `declare -A` declarations, `${PHASE_STATUS[$i]}` array access throughout, `[[ ]]` with `BASH_REMATCH` for regex matching, `${PHASE_ATTEMPTS[$phase_num]}` arithmetic, `$(seq ...)` loops, `echo -n` (use `printf` instead for portability)

**Changes:**

- Line 1: Change shebang to `#!/bin/sh`
- Lines 7-10: Remove all `declare -A` declarations
- Lines 19-24: Replace `for i in $(seq ...)` + array assignment with `while` + eval
- Lines 44-54: Replace `[[ "$line" =~ ... ]]` + `BASH_REMATCH` with `grep` + `sed` + `case`
- Lines 95-102: Replace `for i in $(seq ...)` + `${PHASE_STATUS[$i]}` with `while` + eval
- Lines 114-157: Replace all array access in `generate_phase_details` with eval + while loops
- Lines 143, 152: Replace `echo -n` with `printf`
- Lines 166, 170-176: Replace all array access in `update_phase_status` with eval

**Full rewrite of lib/progress.sh:**

```sh
#!/bin/sh

# Progress Tracking Library
# Manages PROGRESS.md file and tracks execution state

# Initialize progress tracking
# Args: $1 - progress file path
init_progress() {
  local progress_file="$1"

  # Initialize status for all phases as pending
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    eval "PHASE_STATUS_${i}=pending"
    eval "PHASE_ATTEMPTS_${i}=0"
    eval "PHASE_START_TIME_${i}=''"
    eval "PHASE_END_TIME_${i}=''"
    i=$((i + 1))
  done

  # Read existing progress if file exists
  if [ -f "$progress_file" ]; then
    read_progress "$progress_file"
  fi
}

# Read progress from PROGRESS.md
read_progress() {
  local progress_file="$1"

  if [ ! -f "$progress_file" ]; then
    return 0
  fi

  # Parse PROGRESS.md to restore state
  local current_phase=""
  while IFS= read -r line; do
    # Match phase headers: ### ✅ Phase 1: Title
    if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
      current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
    elif [ -n "$current_phase" ]; then
      case "$line" in
        "Status: "*)
          status_value=$(echo "$line" | sed 's/^Status:[[:space:]]*//')
          eval "PHASE_STATUS_${current_phase}='$status_value'"
          ;;
        "Started: "*)
          time_value=$(echo "$line" | sed 's/^Started:[[:space:]]*//')
          eval "PHASE_START_TIME_${current_phase}='$time_value'"
          ;;
        "Completed: "*)
          time_value=$(echo "$line" | sed 's/^Completed:[[:space:]]*//')
          eval "PHASE_END_TIME_${current_phase}='$time_value'"
          ;;
        "Attempts: "*)
          attempts_value=$(echo "$line" | sed 's/^Attempts:[[:space:]]*//')
          eval "PHASE_ATTEMPTS_${current_phase}=$attempts_value"
          ;;
      esac
    fi
  done < "$progress_file"

  return 0
}

# Write/update PROGRESS.md
# Args: $1 - progress file path, $2 - plan file path
write_progress() {
  local progress_file="$1"
  local plan_file="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  local temp_file="${progress_file}.tmp"

  cat > "$temp_file" << EOF
# Progress for $plan_file
Last updated: $timestamp

## Status Summary
$(generate_status_summary)

## Phase Details

$(generate_phase_details)
EOF

  # Atomic update
  mv "$temp_file" "$progress_file"
}

# Generate status summary section
generate_status_summary() {
  local total=$PHASE_COUNT
  local completed=0
  local in_progress=0
  local pending=0
  local failed=0

  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    local status
    status=$(eval "echo \"\$PHASE_STATUS_$i\"")
    case "$status" in
      completed)   completed=$((completed + 1)) ;;
      in_progress) in_progress=$((in_progress + 1)) ;;
      pending)     pending=$((pending + 1)) ;;
      failed)      failed=$((failed + 1)) ;;
    esac
    i=$((i + 1))
  done

  echo "- Total phases: $total"
  echo "- Completed: $completed"
  echo "- In progress: $in_progress"
  echo "- Pending: $pending"
  echo "- Failed: $failed"
}

# Generate phase details section
generate_phase_details() {
  local i=1
  while [ "$i" -le "$PHASE_COUNT" ]; do
    local status
    status=$(eval "echo \"\$PHASE_STATUS_$i\"")
    local title
    title=$(eval "echo \"\$PHASE_TITLE_$i\"")
    local icon="⏳"

    case "$status" in
      completed)   icon="✅" ;;
      in_progress) icon="🔄" ;;
      failed)      icon="❌" ;;
      pending)     icon="⏳" ;;
    esac

    echo "### $icon Phase $i: $title"
    echo "Status: $status"

    local start_time
    start_time=$(eval "echo \"\$PHASE_START_TIME_$i\"")
    if [ -n "$start_time" ]; then
      echo "Started: $start_time"
    fi

    local end_time
    end_time=$(eval "echo \"\$PHASE_END_TIME_$i\"")
    if [ -n "$end_time" ]; then
      echo "Completed: $end_time"
    fi

    local attempts
    attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$i\"")
    if [ "$attempts" -gt 0 ]; then
      echo "Attempts: $attempts"
    fi

    local deps
    deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$i\"")
    if [ -n "$deps" ]; then
      printf 'Depends on:'
      for dep in $deps; do
        local dep_status
        dep_status=$(eval "echo \"\$PHASE_STATUS_$dep\"")
        local dep_icon="⏳"
        case "$dep_status" in
          completed) dep_icon="✅" ;;
          failed)    dep_icon="❌" ;;
        esac
        printf ' Phase %s %s' "$dep" "$dep_icon"
      done
      echo ""
    fi

    echo ""
    i=$((i + 1))
  done
}

# Update phase status
# Args: $1 - phase number, $2 - new status
update_phase_status() {
  local phase_num="$1"
  local new_status="$2"

  eval "PHASE_STATUS_${phase_num}='$new_status'"

  case "$new_status" in
    in_progress)
      eval "PHASE_START_TIME_${phase_num}='$(date '+%Y-%m-%d %H:%M:%S')'"
      local attempts
      attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")
      eval "PHASE_ATTEMPTS_${phase_num}=$((attempts + 1))"
      ;;
    completed|failed)
      eval "PHASE_END_TIME_${phase_num}='$(date '+%Y-%m-%d %H:%M:%S')'"
      ;;
  esac
}
```

---

## Verification

```sh
# 0. Write tests first, confirm they fail
bats tests/test_dependencies.sh tests/test_progress.sh

# 1. Implement, then confirm tests pass
bats tests/test_dependencies.sh tests/test_progress.sh

# 2. Syntax check
shellcheck -s sh lib/dependencies.sh lib/progress.sh
```
