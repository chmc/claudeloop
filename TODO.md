# ClaudeLoop POSIX Rewrite Plan (UPDATED)

## Context

ClaudeLoop currently uses zsh-specific features (BASH_REMATCH, associative arrays, KSH_ARRAYS option) which are causing compatibility issues even within zsh itself when combined with strict mode (`set -u`). The goal is to rewrite it using pure POSIX shell features that work reliably in any POSIX-compatible shell, including zsh.

**Why this is needed:**
- Current zsh implementation hits "bad substitution" errors due to complex interactions between zsh options and parameter expansions
- POSIX shell is more portable and predictable
- POSIX scripts work perfectly when executed from zsh terminal
- Eliminates dependency on bash/zsh-specific features

**Outcome:** A fully POSIX-compatible ClaudeLoop that can be executed from any terminal (zsh, bash, sh) and works reliably across different systems.

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
PHASE_TITLES[1]         → PHASE_TITLE_1
PHASE_TITLES[2]         → PHASE_TITLE_2
PHASE_DESCRIPTIONS[1]   → PHASE_DESCRIPTION_1
PHASE_DEPENDENCIES[1]   → PHASE_DEPENDENCIES_1
PHASE_STATUS[1]         → PHASE_STATUS_1
PHASE_ATTEMPTS[1]       → PHASE_ATTEMPTS_1
PHASE_START_TIME[1]     → PHASE_START_TIME_1
PHASE_END_TIME[1]       → PHASE_END_TIME_1
```

### Access Pattern

```sh
# Old (zsh):
title="${PHASE_TITLES[$phase_num]}"

# New (POSIX):
title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")

# Set value:
eval "PHASE_TITLE_${phase_num}='value'"
```

---

## Approach

Convert all files from zsh-specific syntax to pure POSIX shell by:

1. **Replace associative arrays** → Use numbered variables with eval
2. **Replace BASH_REMATCH regex** → Use sed/grep/case for pattern matching
3. **Replace bash arithmetic** → Implement power function for exponentiation
4. **Replace $RANDOM** → Use /dev/urandom or date-based random
5. **Replace `source`** → Use `.` (dot command)
6. **Simplify all syntax** → Use only POSIX `[ ]` tests, `case` statements, basic expansions

---

## Key Technical Patterns

### Variable Indirection with eval

```sh
# Set simple value
eval "PHASE_TITLE_${phase_num}='value'"

# Get value
title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")

# Set value with quotes - escape single quotes
phase_title_escaped=$(printf '%s' "$phase_title" | sed "s/'/'\\\\''/g")
eval "PHASE_TITLE_${phase_num}='${phase_title_escaped}'"
# This replaces ' with '\'' (close quote, literal quote, open quote)
```

### Multi-line String Storage

```sh
# Using eval with direct assignment (preferred for safety)
# Store multi-line in temp variable first
_desc="$current_description"
eval "PHASE_DESCRIPTION_${phase_num}=\"\${_desc}\""

# Alternative: heredoc (if content is already in variable)
eval "PHASE_DESCRIPTION_${phase_num}=\"\$(cat <<'EOFMARKER'
$multiline_content
EOFMARKER
)\""
```

### Pattern Matching

```sh
# Use case instead of [[]]
case "$line" in
  "## Phase "*)
    # It's a phase header
    ;;
esac

# Use grep for testing
if echo "$line" | grep -qE '^pattern'; then
  # Matches
fi

# Use sed for extraction
value=$(echo "$line" | sed -n 's/^pattern \(capture\).*/\1/p')
```

### Portable Loops

```sh
# Replace: for i in $(seq 1 $PHASE_COUNT); do
i=1
while [ "$i" -le "$PHASE_COUNT" ]; do
  # Process $i
  i=$((i + 1))
done

# For looping over array keys (like dependencies)
# Old: for phase_num in "${!PHASE_DEPENDENCIES[@]}"; do
# New: Loop through all phases and check
i=1
while [ "$i" -le "$PHASE_COUNT" ]; do
  deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$i\"")
  if [ -n "$deps" ]; then
    # Process dependencies for phase $i
  fi
  i=$((i + 1))
done
```

---

## Implementation Order

### 1. lib/retry.sh (Simplest - Start Here)

**Current issues:** Uses `**` exponentiation and `$RANDOM`

**Changes:**

```sh
# Line 1: Change shebang
#!/bin/sh

# Lines 7-8: Remove setopt
# DELETE: setopt BASH_REMATCH KSH_ARRAYS
# DELETE: unsetopt CASE_MATCH

# Add power function (after line 13)
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

# Add random function (after power function)
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

# Line 20: Replace exponentiation
# OLD: local delay=$((BASE_DELAY * (2 ** (attempt - 1))))
exp_value=$(power 2 $((attempt - 1)))
delay=$((BASE_DELAY * exp_value))

# Line 27: Replace $RANDOM
# OLD: local jitter=$((RANDOM % (delay / 4 + 1)))
jitter=$(get_random $((delay / 4 + 1)))

# Line 36: Replace array access
# OLD: local attempts="${PHASE_ATTEMPTS[$phase_num]}"
attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")
```

**Critical lines:** 1, 7-8, 20, 27, 36

---

### 2. lib/ui.sh (Minimal Changes)

**Current issues:** Array access, `echo -e` usage

**Changes:**

```sh
# Line 1: Change shebang
#!/bin/sh

# Lines 7-8: Remove setopt
# DELETE: setopt BASH_REMATCH KSH_ARRAYS
# DELETE: unsetopt CASE_MATCH

# Line 27: Replace array access in print_header
# OLD: if [ "${PHASE_STATUS[$i]:-pending}" = "completed" ]; then
status=$(eval "echo \"\$PHASE_STATUS_$i\"")
status="${status:-pending}"
if [ "$status" = "completed" ]; then

# Lines 44-45: Replace array access in print_phase_status
# OLD: local status="${PHASE_STATUS[$phase_num]:-pending}"
# OLD: local title="${PHASE_TITLES[$phase_num]:-Unknown}"
status=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")
status="${status:-pending}"
title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
title="${title:-Unknown}"

# Line 68: Replace echo -e with printf
# OLD: echo -e "${color}${icon} Phase $phase_num: $title${COLOR_RESET}"
printf '%b\n' "${color}${icon} Phase $phase_num: $title${COLOR_RESET}"

# Line 84: Replace array access in print_phase_exec_header
# OLD: local title="${PHASE_TITLES[$phase_num]}"
# OLD: local attempt="${PHASE_ATTEMPTS[$phase_num]}"
title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
attempt=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")

# Lines 88, 90, 99, 103, 111: Replace all echo -e with printf
# OLD: echo -e "${COLOR_BLUE}..."
printf '%b\n' "${COLOR_BLUE}..."
```

**Critical lines:** 1, 7-8, 27, 44-45, 68, 84, 88, 90, 99, 103, 111

---

### 3. lib/dependencies.sh (Array Operations)

**Current issues:** Array operations for cycle detection, membership testing

**Changes:**

```sh
# Line 1: Change shebang
#!/bin/sh

# Lines 7-8: Remove setopt
# DELETE: setopt BASH_REMATCH KSH_ARRAYS
# DELETE: unsetopt CASE_MATCH

# Line 16: Replace array access in is_phase_runnable
# OLD: local status="${PHASE_STATUS[$phase_num]}"
status=$(eval "echo \"\$PHASE_STATUS_$phase_num\"")

# Lines 24, 26: Replace array access for dependencies check
# OLD: local deps="${PHASE_DEPENDENCIES[$phase_num]}"
# OLD: if [ "${PHASE_STATUS[$dep]}" != "completed" ]; then
deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase_num\"")
for dep in $deps; do
  dep_status=$(eval "echo \"\$PHASE_STATUS_$dep\"")
  if [ "$dep_status" != "completed" ]; then

# Lines 52-53: Replace array initialization with space-separated strings
# OLD: local visited=()
# OLD: local rec_stack=()
visited=""
rec_stack=""

# Line 71: Replace array membership check
# OLD: if [[ " ${rec_stack[*]} " == *" $phase "* ]]; then
case " $rec_stack " in
  *" $phase "*)
    echo "Error: Circular dependency detected involving Phase $phase" >&2
    return 1
    ;;
esac

# Line 77: Replace array membership check
# OLD: if [[ " ${visited[*]} " == *" $phase "* ]]; then
case " $visited " in
  *" $phase "*) return 0 ;;
esac

# Line 81: Replace array append
# OLD: rec_stack+=("$phase")
rec_stack="$rec_stack $phase"

# Line 84: Replace array access
# OLD: local deps="${PHASE_DEPENDENCIES[$phase]}"
deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase\"")

# Lines 93-98: Replace array filter operation
# OLD: local new_stack=()
# OLD: for item in "${rec_stack[@]}"; do
# OLD:   [ "$item" != "$phase" ] && new_stack+=("$item")
# OLD: done
# OLD: rec_stack=("${new_stack[@]}")
# OLD: visited+=("$phase")
new_stack=""
for item in $rec_stack; do
  [ "$item" != "$phase" ] && new_stack="$new_stack $item"
done
rec_stack="$new_stack"
visited="$visited $phase"

# Lines 113-114: Replace array access and pattern matching
# OLD: local deps="${PHASE_DEPENDENCIES[$phase]}"
# OLD: if [[ " $deps " == *" $blocker_phase "* ]]; then
deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$phase\"")
case " $deps " in
  *" $blocker_phase "*)
    blocked="$blocked $phase"
    ;;
esac
```

**Critical lines:** 1, 7-8, 16, 24, 26, 52-53, 71, 77, 81, 84, 93-98, 113-114

---

### 4. lib/progress.sh (Regex + Array Access)

**Current issues:** Multiple BASH_REMATCH regex patterns, associative array declarations and access

**Changes:**

```sh
# Line 1: Change shebang
#!/bin/sh

# Lines 7-8: Remove setopt
# DELETE: setopt BASH_REMATCH KSH_ARRAYS
# DELETE: unsetopt CASE_MATCH

# Lines 11-14: Remove typeset declarations
# DELETE: typeset -A PHASE_STATUS
# DELETE: typeset -A PHASE_START_TIME
# DELETE: typeset -A PHASE_END_TIME
# DELETE: typeset -A PHASE_ATTEMPTS

# Lines 23-27: Replace for loop with while
# OLD: for i in $(seq 1 "$PHASE_COUNT"); do
i=1
while [ "$i" -le "$PHASE_COUNT" ]; do
  eval "PHASE_STATUS_${i}=pending"
  eval "PHASE_ATTEMPTS_${i}=0"
  eval "PHASE_START_TIME_${i}=''"
  eval "PHASE_END_TIME_${i}=''"
  i=$((i + 1))
done

# Lines 48-57: Replace regex parsing with grep + sed
# OLD: if [[ "$line" =~ "^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+([0-9]+):" ]]; then
# OLD:   current_phase="${BASH_REMATCH[1]}"
# OLD: elif [ -n "$current_phase" ] && [[ "$line" =~ "^Status:[[:space:]]+(.+)" ]]; then
# OLD:   PHASE_STATUS[$current_phase]="${BASH_REMATCH[1]}"
# ... etc

if echo "$line" | grep -qE '^###[[:space:]]+[^[:space:]]+[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
  current_phase=$(echo "$line" | sed -n 's/^###[[:space:]]*[^[:space:]]*[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
fi

if [ -n "$current_phase" ]; then
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

# Lines 99-106: Replace for loop and array access
# OLD: for i in $(seq 1 "$PHASE_COUNT"); do
# OLD:   case "${PHASE_STATUS[$i]}" in
i=1
while [ "$i" -le "$PHASE_COUNT" ]; do
  status=$(eval "echo \"\$PHASE_STATUS_$i\"")
  case "$status" in
    completed) completed=$((completed + 1)) ;;
    in_progress) in_progress=$((in_progress + 1)) ;;
    pending) pending=$((pending + 1)) ;;
    failed) failed=$((failed + 1)) ;;
  esac
  i=$((i + 1))
done

# Lines 118-161: Replace all array access in generate_phase_details
# OLD: for i in $(seq 1 "$PHASE_COUNT"); do
# OLD:   local status="${PHASE_STATUS[$i]}"
# OLD:   local title="${PHASE_TITLES[$i]}"
i=1
while [ "$i" -le "$PHASE_COUNT" ]; do
  status=$(eval "echo \"\$PHASE_STATUS_$i\"")
  title=$(eval "echo \"\$PHASE_TITLE_$i\"")
  # ... rest of logic ...
  start_time=$(eval "echo \"\$PHASE_START_TIME_$i\"")
  end_time=$(eval "echo \"\$PHASE_END_TIME_$i\"")
  attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$i\"")
  deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$i\"")

  # For dependency status check:
  for dep in $deps; do
    dep_status=$(eval "echo \"\$PHASE_STATUS_$dep\"")
    # ... check dep_status ...
  done

  i=$((i + 1))
done

# Lines 170, 175: Replace array access in update_phase_status
# OLD: PHASE_STATUS[$phase_num]="$new_status"
# OLD: PHASE_START_TIME[$phase_num]="$(date '+%Y-%m-%d %H:%M:%S')"
# OLD: PHASE_ATTEMPTS[$phase_num]=$((${PHASE_ATTEMPTS[$phase_num]} + 1))
# OLD: PHASE_END_TIME[$phase_num]="$(date '+%Y-%m-%d %H:%M:%S')"
eval "PHASE_STATUS_${phase_num}='$new_status'"

case "$new_status" in
  in_progress)
    eval "PHASE_START_TIME_${phase_num}='$(date '+%Y-%m-%d %H:%M:%S')'"
    attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$phase_num\"")
    eval "PHASE_ATTEMPTS_${phase_num}=$((attempts + 1))"
    ;;
  completed|failed)
    eval "PHASE_END_TIME_${phase_num}='$(date '+%Y-%m-%d %H:%M:%S')'"
    ;;
esac
```

**Critical lines:** 1, 7-8, 11-14, 23-27, 48-57, 99-106, 118-161, 170, 175

---

### 5. lib/parser.sh (Most Complex - Regex Heavy)

**Current issues:** Heavy regex usage with BASH_REMATCH, associative array storage

**Changes:**

```sh
# Line 1: Change shebang
#!/bin/sh

# Lines 7-9: Remove setopt
# DELETE: setopt BASH_REMATCH KSH_ARRAYS
# DELETE: unsetopt CASE_MATCH

# Lines 12-14: Remove typeset declarations
# DELETE: typeset -A PHASE_TITLES
# DELETE: typeset -A PHASE_DESCRIPTIONS
# DELETE: typeset -A PHASE_DEPENDENCIES

# Lines 29-31: Remove array reset (no longer needed)
# DELETE: PHASE_TITLES=()
# DELETE: PHASE_DESCRIPTIONS=()
# DELETE: PHASE_DEPENDENCIES=()

# Lines 44-46: Replace phase header regex with grep + sed
# OLD: if [[ "$line" =~ "^##[[:space:]]+Phase[[:space:]]+([0-9]+):[[:space:]]*(.*)" ]]; then
# OLD:   local phase_num="${BASH_REMATCH[1]}"
# OLD:   local phase_title="${BASH_REMATCH[2]}"

case "$line" in
  "## Phase "*)
    if echo "$line" | grep -qE '^##[[:space:]]+Phase[[:space:]]+[0-9]+:'; then
      phase_num=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*\([0-9][0-9]*\):.*/\1/p')
      phase_title=$(echo "$line" | sed -n 's/^##[[:space:]]*Phase[[:space:]]*[0-9][0-9]*:[[:space:]]*\(.*\)/\1/p')

      # ... rest of phase header logic ...
    fi
    ;;
esac

# Line 50: Store description (when saving previous phase)
# OLD: PHASE_DESCRIPTIONS[$current_phase]="$current_description"
_desc="$current_description"
eval "PHASE_DESCRIPTION_${current_phase}=\"\${_desc}\""

# Line 60: Check for existing phase
# OLD: if [ -n "${PHASE_TITLES[$phase_num]:-}" ]; then
existing_title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
if [ -n "$existing_title" ]; then

# Line 66: Store phase title
# OLD: PHASE_TITLES[$phase_num]="$phase_title"
phase_title_escaped=$(printf '%s' "$phase_title" | sed "s/'/'\\\\''/g")
eval "PHASE_TITLE_${phase_num}='${phase_title_escaped}'"

# Lines 75-79: Replace dependency regex
# OLD: if [[ "$line" =~ "^\*\*Depends[[:space:]]+on:\*\*[[:space:]]+(.*)" ]]; then
# OLD:   local deps_line="${BASH_REMATCH[1]}"
# OLD:   local deps
# OLD:   deps=$(echo "$deps_line" | sed 's/Phase //g' | grep -oE '[0-9]+' | xargs echo)
# OLD:   PHASE_DEPENDENCIES[$current_phase]="$deps"

case "$line" in
  "**Depends on:**"*)
    deps_line=$(echo "$line" | sed 's/^\*\*Depends[[:space:]]*on:[[:space:]]*\*\*[[:space:]]*//')
    deps=$(echo "$deps_line" | sed 's/Phase //g' | grep -oE '[0-9]+' | xargs echo)
    eval "PHASE_DEPENDENCIES_${current_phase}='$deps'"
    ;;
esac

# Line 82: This is in the else branch for description accumulation
# OLD: PHASE_DEPENDENCIES[$current_phase]="$deps"
# (Already handled above)

# Lines 85-88: Safe multi-line description concatenation
# OLD: if [ -n "$current_description" ]; then
# OLD:   current_description+=$'\n'
# OLD: fi
# OLD: current_description+="$line"
if [ -n "$current_description" ]; then
  current_description="${current_description}
${line}"
else
  current_description="$line"
fi

# Line 95: Store last phase description
# OLD: PHASE_DESCRIPTIONS[$current_phase]="$current_description"
_desc="$current_description"
eval "PHASE_DESCRIPTION_${current_phase}=\"\${_desc}\""

# Line 99: Loop over phases for validation
# OLD: for phase_num in "${!PHASE_DEPENDENCIES[@]}"; do
# OLD:   local deps="${PHASE_DEPENDENCIES[$phase_num]}"
i=1
while [ "$i" -le "$PHASE_COUNT" ]; do
  deps=$(eval "echo \"\$PHASE_DEPENDENCIES_$i\"")
  if [ -n "$deps" ]; then
    for dep in $deps; do
      # Line 102: Check if dependency exists
      # OLD: if [ -z "${PHASE_TITLES[$dep]:-}" ]; then
      dep_title=$(eval "echo \"\$PHASE_TITLE_$dep\"")
      if [ -z "$dep_title" ]; then
        echo "Error: Phase $i depends on non-existent Phase $dep" >&2
        return 1
      fi
      # Line 106: Check for forward/self dependency
      if [ "$dep" -ge "$i" ]; then
        echo "Error: Phase $i cannot depend on Phase $dep (forward or self dependency)" >&2
        return 1
      fi
    done
  fi
  i=$((i + 1))
done

# Lines 130, 135, 145: Replace array access in getter functions
# OLD: echo "${PHASE_TITLES[$phase_num]}"
# OLD: echo "${PHASE_DESCRIPTIONS[$phase_num]}"
# OLD: echo "${PHASE_DEPENDENCIES[$phase_num]}"
eval "echo \"\$PHASE_TITLE_$phase_num\""
eval "echo \"\$PHASE_DESCRIPTION_$phase_num\""
eval "echo \"\$PHASE_DEPENDENCIES_$phase_num\""
```

**Critical lines:** 1, 7-9, 12-14, 29-31, 44-46, 50, 60, 66, 75-79, 82, 85-88, 95, 99, 102, 106, 130, 135, 145

---

### 6. claudeloop (Main Script)

**Current issues:** Script dir detection, `source` command, regex, array access

**Changes:**

```sh
# Line 1: Change shebang
#!/bin/sh

# Lines 7-8: Remove setopt
# DELETE: setopt BASH_REMATCH KSH_ARRAYS
# DELETE: unsetopt CASE_MATCH

# Line 12: Replace script directory detection
# OLD: SCRIPT_DIR="${0:A:h}"  # zsh-specific
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Lines 16-20: Replace source with . (dot command)
# OLD: source "$SCRIPT_DIR/lib/parser.sh"
# OLD: source "$SCRIPT_DIR/lib/dependencies.sh"
# OLD: source "$SCRIPT_DIR/lib/progress.sh"
# OLD: source "$SCRIPT_DIR/lib/retry.sh"
# OLD: source "$SCRIPT_DIR/lib/ui.sh"
. "$SCRIPT_DIR/lib/parser.sh"
. "$SCRIPT_DIR/lib/dependencies.sh"
. "$SCRIPT_DIR/lib/progress.sh"
. "$SCRIPT_DIR/lib/retry.sh"
. "$SCRIPT_DIR/lib/ui.sh"

# Line 60: Replace regex with case for Y/N response
# OLD: if [[ "$response" =~ ^[Nn]$ ]]; then
case "$response" in
  [Nn])
    rm -f "$STATE_FILE"
    return 1
    ;;
esac
return 0

# Lines 109-113: Replace array access in interrupt handler
# OLD: if [ -n "$CURRENT_PHASE" ] && [ "${PHASE_STATUS[$CURRENT_PHASE]:-}" = "in_progress" ]; then
# OLD:   PHASE_STATUS[$CURRENT_PHASE]="pending"
# OLD:   PHASE_ATTEMPTS[$CURRENT_PHASE]=$((${PHASE_ATTEMPTS[$CURRENT_PHASE]} - 1))
if [ -n "$CURRENT_PHASE" ]; then
  status=$(eval "echo \"\$PHASE_STATUS_$CURRENT_PHASE\"")
  if [ "$status" = "in_progress" ]; then
    eval "PHASE_STATUS_${CURRENT_PHASE}=pending"
    attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$CURRENT_PHASE\"")
    eval "PHASE_ATTEMPTS_${CURRENT_PHASE}=$((attempts - 1))"
  fi
fi

# Line 227: Replace regex with case for Y/N response
# OLD: if [[ ! "$response" =~ ^[Yy]$ ]]; then
# OLD:   echo "Aborted."
# OLD:   exit 0
# OLD: fi
case "$response" in
  [Yy]) ;;  # Continue
  *)
    echo "Aborted."
    exit 0
    ;;
esac

# Lines 243-244: Replace array access in execute_phase
# OLD: local title="${PHASE_TITLES[$phase_num]}"
# OLD: local description="${PHASE_DESCRIPTIONS[$phase_num]}"
title=$(eval "echo \"\$PHASE_TITLE_$phase_num\"")
description=$(eval "echo \"\$PHASE_DESCRIPTION_$phase_num\"")

# Lines 317-318: Replace for loop with while
# OLD: for i in $(seq 1 "$PHASE_COUNT"); do
# OLD:   if [ "${PHASE_STATUS[$i]}" = "pending" ]; then
i=1
while [ "$i" -le "$PHASE_COUNT" ]; do
  status=$(eval "echo \"\$PHASE_STATUS_$i\"")
  if [ "$status" = "pending" ]; then
    has_pending=true
  fi
  status=$(eval "echo \"\$PHASE_STATUS_$i\"")
  if [ "$status" = "failed" ]; then
    has_failed=true
  fi
  i=$((i + 1))
done

# Line 347: Replace array access in retry logic
# OLD: delay=$(calculate_backoff "${PHASE_ATTEMPTS[$next_phase]}")
attempts=$(eval "echo \"\$PHASE_ATTEMPTS_$next_phase\"")
delay=$(calculate_backoff "$attempts")
```

**Critical lines:** 1, 7-8, 12, 16-20, 60, 109-113, 227, 243-244, 317-318, 347

---

## Verification Steps

After implementation:

### 1. Syntax Check
```sh
shellcheck -s sh claudeloop lib/*.sh
```
Should pass with no errors (may have some warnings about `local` not being POSIX, which is acceptable).

### 2. Dry-run Test
```sh
./claudeloop --plan examples/PLAN.md.example --dry-run
```
Should parse successfully without errors.

### 3. Shell Compatibility
Test with different shells:
```sh
/bin/sh claudeloop --plan examples/PLAN.md.example --dry-run
dash claudeloop --plan examples/PLAN.md.example --dry-run
busybox sh claudeloop --plan examples/PLAN.md.example --dry-run
```

### 4. Quote and Special Character Handling
Create test plan with:
- Phase title with single quotes: `## Phase 1: Install 'foo' package`
- Phase title with double quotes: `## Phase 2: Set "DEBUG" flag`
- Phase description with dollar signs: `$VAR` and `${VAR}`
- Phase description with command substitution syntax: `$(command)` and `` `command` ``
- Phase description with backslashes: `C:\path\to\file`
- Multi-line descriptions with blank lines
- Empty phase descriptions
- Very long phase titles (>200 chars)

### 5. Dependency Edge Cases
- Phase depending on multiple phases
- Multiple phases depending on same phase
- Circular dependency detection
- Forward dependency detection

### 6. Functionality Test
Run full execution with a small test plan (3-5 phases).

### 7. Interrupt Test
Start execution, press Ctrl+C during phase 2:
- Verify state is saved
- Verify PROGRESS.md shows phase 1 completed, phase 2 pending
- Resume and verify it continues from phase 2
- Verify attempt count is correct (not incremented for interrupted phase)

### 8. Retry Logic Test
Create a phase that fails:
- Verify it retries with exponential backoff
- Verify attempt count increments correctly
- Verify it stops after MAX_RETRIES

### 9. State Persistence Test
- Interrupt during various phases
- Verify resume works correctly
- Test with corrupt PROGRESS.md file

---

## Expected Outcomes

- ✅ ClaudeLoop works when executed from zsh terminal (or any terminal)
- ✅ Uses only POSIX shell features (except `local` which is universally supported)
- ✅ No "bad substitution" errors
- ✅ Same functionality as before
- ✅ PLAN.md and PROGRESS.md formats unchanged
- ✅ Works on macOS, Linux, BSD
- ✅ No dependency on bash 5+ or zsh-specific features
- ✅ Passes shellcheck with `-s sh` option

---

## Implementation Notes

### All Files
- Change shebang from `#!/usr/bin/env zsh` to `#!/bin/sh`
- Remove all `setopt`/`unsetopt` commands
- Replace all `typeset -A` declarations (just remove them)
- Replace `source` with `.` (dot command)
- Replace `for i in $(seq ...)` with while loops
- Replace associative array access with eval pattern

### Performance Impact
- Expected ~10-20% slower due to eval overhead
- For a 20-phase plan: ~0.5s → ~0.6s (dry-run)
- Acceptable for typical use

### Code Verbosity
- Code becomes slightly more verbose due to eval pattern
- Trade-off for significantly better portability
- More explicit about what's happening (arguably better)

### Security Note
- eval is used extensively with content from PLAN.md files
- Quote escaping helps prevent injection
- PLAN.md is assumed to be trusted (user-created)
- Test with phase titles containing command substitution syntax to verify escaping

---

## Risk Assessment

### High Risk (Requires Careful Testing)
1. **Multi-line description parsing** - Test with quotes, special chars, newlines
2. **eval with dynamic content** - Verify quote escaping works correctly
3. **Regex to sed/case conversion** - Verify pattern matching behavior is identical

### Medium Risk
1. **State persistence** - Must survive interrupts correctly
2. **Dependency cycle detection** - Array-to-string conversion edge cases
3. **Retry logic** - Attempt counting during interrupts

### Low Risk
1. **UI/color output** - Straightforward printf conversion
2. **Lock file handling** - Pure POSIX operations
3. **Power/random functions** - Simple arithmetic

---

## Estimated Implementation Time

- **lib/retry.sh**: 30 minutes
- **lib/ui.sh**: 30 minutes
- **lib/dependencies.sh**: 1 hour
- **lib/progress.sh**: 1.5 hours
- **lib/parser.sh**: 2 hours
- **claudeloop**: 1 hour
- **Testing**: 2 hours

**Total: 8-10 hours** for careful conversion and thorough testing

---

## Post-Implementation Updates

After successful conversion, update documentation:

1. **README.md** - Add POSIX compatibility section
2. **CONTRIBUTING.md** - Note about POSIX-only syntax
3. **Error messages** - Remove any references to "zsh" or "bash"
4. **Commit message** - Document the conversion and why it was needed
