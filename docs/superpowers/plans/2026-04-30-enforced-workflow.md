# Enforced Workflow System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 11 Claude Code hooks that enforce a git-agnostic development workflow with hard gates.

**Architecture:** PreToolUse hooks intercept Edit/Write/ExitPlanMode/TaskUpdate tool calls. Each hook reads/writes state files in `.claude/workflow-state/`. Hooks return JSON with `permissionDecision: "deny"` to block or exit 0 to allow.

**Tech Stack:** POSIX shell scripts, jq for JSON parsing, Claude Code hooks API

**Spec:** `/Users/aleksi/.claude/plans/explain-simply-what-is-replicated-cloud.md`

---

## File Structure

```
.claude/
├── settings.json                    # Add hook definitions (modify)
├── hooks/
│   ├── branch-awareness.sh          # Gate 1 (new)
│   ├── planning-checklist.sh        # Gate 2 (new)
│   ├── plan-to-tasks.sh             # Gate 3 (new)
│   ├── tdd-enforcement.sh           # Gate 4 (new)
│   └── completion-bundle.sh         # Gates 5-11 (new)
├── workflow-state/                  # State directory (new, gitignored)
└── skills/
    ├── verify/SKILL.md              # Add visual-verified state (modify)
    └── workflow/SKILL.md            # New skill (new)

docs/
└── WORKFLOW.md                      # Full documentation (new)

.gitignore                           # Add workflow-state (modify)
CLAUDE.md                            # Add workflow rule (modify)
```

---

## Task 1: State Management Infrastructure

**Files:**
- Create: `.claude/workflow-state/.gitkeep`
- Modify: `.gitignore`

- [ ] **Step 1: Create workflow-state directory**

```bash
mkdir -p .claude/workflow-state
touch .claude/workflow-state/.gitkeep
```

- [ ] **Step 2: Add to .gitignore**

Add to `.gitignore`:
```
# Workflow state (session-specific)
.claude/workflow-state/*
!.claude/workflow-state/.gitkeep
```

- [ ] **Step 3: Verify directory exists and is ignored**

Run: `git status`
Expected: `.claude/workflow-state/` not shown (ignored)

- [ ] **Step 4: Commit**

```bash
git add .claude/workflow-state/.gitkeep .gitignore
git commit -m "chore: add workflow state directory infrastructure"
```

---

## Task 2: Branch Awareness Hook (Gate 1)

**Files:**
- Create: `.claude/hooks/branch-awareness.sh`
- Create: `tests/test_hook_branch_awareness.sh`

- [ ] **Step 1: Write failing test for branch awareness hook**

Create `tests/test_hook_branch_awareness.sh`:
```bash
#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"
    
    # Copy hook script
    cp .claude/hooks/branch-awareness.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/branch-awareness.sh"
    
    # Initialize git repo for branch detection
    cd "$TEST_DIR"
    git init -q
    git checkout -q -b test-branch
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "branch-awareness: denies first edit without confirmation" {
    # No branch-confirmed file exists
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"test.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/branch-awareness.sh'"
    
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "branch-awareness: allows edit after confirmation" {
    # Create branch-confirmed file
    echo "test-branch" > "$TEST_DIR/.claude/workflow-state/branch-confirmed"
    
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"test.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/branch-awareness.sh'"
    
    # Exit 0 with no output = allow
    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "branch-awareness: includes branch name in denial message" {
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"test.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/branch-awareness.sh'"
    
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("test-branch")'
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_hook_branch_awareness.sh`
Expected: FAIL (hook doesn't exist yet)

- [ ] **Step 3: Write branch awareness hook**

Create `.claude/hooks/branch-awareness.sh`:
```bash
#!/bin/sh
# Gate 1: Branch Awareness
# Blocks first Edit/Write until branch is confirmed
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
CONFIRMED_FILE="$STATE_DIR/branch-confirmed"

# Read JSON input from stdin
INPUT=$(cat)

# Check if already confirmed
if [ -f "$CONFIRMED_FILE" ]; then
    # Already confirmed, allow
    exit 0
fi

# Get current branch
BRANCH=$(git -C "${CLAUDE_PROJECT_DIR:-.}" branch --show-current 2>/dev/null || echo "unknown")

# Deny with branch info
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Branch confirmation required. Current branch: $BRANCH. Please confirm this is correct for your task, then I will set the confirmation state.",
    "additionalContext": "To proceed, acknowledge the branch is correct. The workflow will then allow edits."
  }
}
EOF
```

- [ ] **Step 4: Make hook executable**

```bash
chmod +x .claude/hooks/branch-awareness.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/test_hook_branch_awareness.sh`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/branch-awareness.sh tests/test_hook_branch_awareness.sh
git commit -m "feat: add branch awareness hook (gate 1)"
```

---

## Task 3: Planning Checklist Hook (Gate 2)

**Files:**
- Create: `.claude/hooks/planning-checklist.sh`
- Create: `tests/test_hook_planning_checklist.sh`

- [ ] **Step 1: Write failing test for planning checklist hook**

Create `tests/test_hook_planning_checklist.sh`:
```bash
#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"
    mkdir -p "$TEST_DIR/.claude/plans"
    
    cp .claude/hooks/planning-checklist.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/planning-checklist.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "planning-checklist: denies plan without all 8 sections" {
    # Create incomplete plan
    cat > "$TEST_DIR/.claude/plans/test-plan.md" <<'EOF'
# Test Plan

## Architecture Impact
Some content

## ADR
N/A - no architectural decisions
EOF
    
    INPUT='{"tool_name":"ExitPlanMode","tool_input":{}}'
    
    # Hook needs to find the plan file - we'll pass it via env or tool_input
    export PLAN_FILE="$TEST_DIR/.claude/plans/test-plan.md"
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/planning-checklist.sh'"
    
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "planning-checklist: allows complete plan with all sections" {
    cat > "$TEST_DIR/.claude/plans/test-plan.md" <<'EOF'
# Test Plan

## Architecture Impact
Some content

## ADR
N/A - no decisions

## Workflow / State Machines
N/A - no workflow changes

## Tests (unit, e2e, integration)
Unit tests needed

## Documentation
Update README

## Install / Uninstall
N/A - no install changes

## Release
N/A - not releasing

## README
Update with new feature
EOF
    
    INPUT='{"tool_name":"ExitPlanMode","tool_input":{}}'
    export PLAN_FILE="$TEST_DIR/.claude/plans/test-plan.md"
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/planning-checklist.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "planning-checklist: writes plan-requirements.json for non-N/A sections" {
    cat > "$TEST_DIR/.claude/plans/test-plan.md" <<'EOF'
# Test Plan

## Architecture Impact
Real changes here

## ADR
N/A - no decisions

## Workflow / State Machines
N/A - no workflow changes

## Tests (unit, e2e, integration)
Unit tests needed

## Documentation
N/A - no doc changes

## Install / Uninstall
N/A - no install changes

## Release
N/A - not releasing

## README
N/A - no readme changes
EOF
    
    INPUT='{"tool_name":"ExitPlanMode","tool_input":{}}'
    export PLAN_FILE="$TEST_DIR/.claude/plans/test-plan.md"
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/planning-checklist.sh'"
    
    [ -f "$TEST_DIR/.claude/workflow-state/plan-requirements.json" ]
    
    # Check that Architecture and Tests are marked as required
    jq -e '.architecture == true' "$TEST_DIR/.claude/workflow-state/plan-requirements.json"
    jq -e '.tests == true' "$TEST_DIR/.claude/workflow-state/plan-requirements.json"
    jq -e '.adr == false' "$TEST_DIR/.claude/workflow-state/plan-requirements.json"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_hook_planning_checklist.sh`
Expected: FAIL (hook doesn't exist)

- [ ] **Step 3: Write planning checklist hook**

Create `.claude/hooks/planning-checklist.sh`:
```bash
#!/bin/sh
# Gate 2: Planning Checklist
# Blocks ExitPlanMode unless all 8 sections are present
# Writes plan-requirements.json for gates 5-10
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
REQUIREMENTS_FILE="$STATE_DIR/plan-requirements.json"

# Required sections (must have content, "N/A - reason" allowed)
SECTIONS="Architecture Impact
ADR
Workflow / State Machines
Tests (unit, e2e, integration)
Documentation
Install / Uninstall
Release
README"

# Find plan file - check env var or find most recent .md in plans dir
if [ -n "${PLAN_FILE:-}" ] && [ -f "$PLAN_FILE" ]; then
    PLAN="$PLAN_FILE"
else
    PLANS_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/plans"
    if [ -d "$PLANS_DIR" ]; then
        PLAN=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1)
    fi
fi

if [ -z "${PLAN:-}" ] || [ ! -f "$PLAN" ]; then
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "No plan file found. Create a plan before exiting plan mode."
  }
}
EOF
    exit 0
fi

# Check each section exists and has content
MISSING=""
PLAN_CONTENT=$(cat "$PLAN")

# Initialize requirements JSON
REQ_ARCH="false"
REQ_ADR="false"
REQ_WORKFLOW="false"
REQ_TESTS="false"
REQ_DOCS="false"
REQ_INSTALL="false"
REQ_RELEASE="false"
REQ_README="false"

check_section() {
    section="$1"
    # Look for ## Section Name (case insensitive-ish)
    if ! echo "$PLAN_CONTENT" | grep -qi "^## *$section"; then
        MISSING="${MISSING}${MISSING:+, }$section"
        return 1
    fi
    
    # Extract content after heading until next ## or end
    # Check if it's just N/A
    section_content=$(echo "$PLAN_CONTENT" | awk -v sect="$section" '
        BEGIN { IGNORECASE=1; found=0 }
        /^## / { if (found) exit; if (index($0, sect)) found=1; next }
        found { print }
    ')
    
    if [ -z "$section_content" ] || [ "$(echo "$section_content" | tr -d '[:space:]')" = "" ]; then
        MISSING="${MISSING}${MISSING:+, }$section (empty)"
        return 1
    fi
    
    # Check if content is just N/A
    if echo "$section_content" | grep -qi "^N/A"; then
        return 0  # N/A is valid but doesn't require updates
    fi
    
    return 2  # Has real content, requires updates
}

# Check each section
check_section "Architecture Impact" && : || { [ $? -eq 2 ] && REQ_ARCH="true"; }
check_section "ADR" && : || { [ $? -eq 2 ] && REQ_ADR="true"; }
check_section "Workflow / State Machines" && : || { [ $? -eq 2 ] && REQ_WORKFLOW="true"; }
check_section "Tests" && : || { [ $? -eq 2 ] && REQ_TESTS="true"; }
check_section "Documentation" && : || { [ $? -eq 2 ] && REQ_DOCS="true"; }
check_section "Install / Uninstall" && : || { [ $? -eq 2 ] && REQ_INSTALL="true"; }
check_section "Release" && : || { [ $? -eq 2 ] && REQ_RELEASE="true"; }
check_section "README" && : || { [ $? -eq 2 ] && REQ_README="true"; }

if [ -n "$MISSING" ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Plan missing required sections: $MISSING. All 8 sections must be present (use 'N/A - reason' if not applicable)."
  }
}
EOF
    exit 0
fi

# Write requirements file for gates 5-10
mkdir -p "$STATE_DIR"
cat > "$REQUIREMENTS_FILE" <<EOF
{
  "architecture": $REQ_ARCH,
  "adr": $REQ_ADR,
  "workflow": $REQ_WORKFLOW,
  "tests": $REQ_TESTS,
  "documentation": $REQ_DOCS,
  "install": $REQ_INSTALL,
  "release": $REQ_RELEASE,
  "readme": $REQ_README
}
EOF

# Mark plan as exited
touch "$STATE_DIR/plan-exited"

# Clear tasks-created for fresh cycle
rm -f "$STATE_DIR/tasks-created"

# Allow ExitPlanMode
exit 0
```

- [ ] **Step 4: Make hook executable**

```bash
chmod +x .claude/hooks/planning-checklist.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/test_hook_planning_checklist.sh`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/planning-checklist.sh tests/test_hook_planning_checklist.sh
git commit -m "feat: add planning checklist hook (gate 2)"
```

---

## Task 4: Plan-to-Tasks Hook (Gate 3)

**Files:**
- Create: `.claude/hooks/plan-to-tasks.sh`
- Create: `tests/test_hook_plan_to_tasks.sh`

- [ ] **Step 1: Write failing test**

Create `tests/test_hook_plan_to_tasks.sh`:
```bash
#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"
    
    cp .claude/hooks/plan-to-tasks.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/plan-to-tasks.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "plan-to-tasks: allows edit when no plan-exited state" {
    # No plan-exited file = not in post-plan phase
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"test.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/plan-to-tasks.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "plan-to-tasks: denies first edit after plan without tasks" {
    # Plan exited but no tasks created
    touch "$TEST_DIR/.claude/workflow-state/plan-exited"
    
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"test.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/plan-to-tasks.sh'"
    
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "plan-to-tasks: allows edit after tasks created" {
    touch "$TEST_DIR/.claude/workflow-state/plan-exited"
    touch "$TEST_DIR/.claude/workflow-state/tasks-created"
    
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"test.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/plan-to-tasks.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_hook_plan_to_tasks.sh`
Expected: FAIL

- [ ] **Step 3: Write plan-to-tasks hook**

Create `.claude/hooks/plan-to-tasks.sh`:
```bash
#!/bin/sh
# Gate 3: Plan-to-Tasks
# Blocks first Edit/Write after ExitPlanMode until tasks are created
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"

# If no plan-exited state, we're not in post-plan phase
if [ ! -f "$STATE_DIR/plan-exited" ]; then
    exit 0
fi

# If tasks already created, allow
if [ -f "$STATE_DIR/tasks-created" ]; then
    exit 0
fi

# Deny - need to create tasks first
cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Create tasks from plan steps before implementation. Use TaskCreate for each implementation step, then this gate will allow edits.",
    "additionalContext": "The plan has been approved. Convert plan steps to tasks for tracking before writing code."
  }
}
EOF
```

- [ ] **Step 4: Make hook executable**

```bash
chmod +x .claude/hooks/plan-to-tasks.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/test_hook_plan_to_tasks.sh`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/plan-to-tasks.sh tests/test_hook_plan_to_tasks.sh
git commit -m "feat: add plan-to-tasks hook (gate 3)"
```

---

## Task 5: TDD Enforcement Hook (Gate 4)

**Files:**
- Create: `.claude/hooks/tdd-enforcement.sh`
- Create: `tests/test_hook_tdd_enforcement.sh`

- [ ] **Step 1: Write failing test**

Create `tests/test_hook_tdd_enforcement.sh`:
```bash
#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"
    mkdir -p "$TEST_DIR/lib"
    mkdir -p "$TEST_DIR/tests"
    
    cp .claude/hooks/tdd-enforcement.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/tdd-enforcement.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "tdd: allows editing test file first" {
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"tests/test_foo.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "tdd: denies editing impl file without test file first" {
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"lib/foo.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"
    
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "tdd: allows editing impl file after test file" {
    # Record that test file was edited
    echo "tests/test_foo.sh" >> "$TEST_DIR/.claude/workflow-state/edit-order"
    
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"lib/foo.sh"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tdd: allows editing non-impl files freely" {
    # Config files, docs, etc. are not subject to TDD
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"CLAUDE.md"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_hook_tdd_enforcement.sh`
Expected: FAIL

- [ ] **Step 3: Write TDD enforcement hook**

Create `.claude/hooks/tdd-enforcement.sh`:
```bash
#!/bin/sh
# Gate 4: TDD Enforcement
# Blocks editing implementation files until corresponding test file is edited
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
EDIT_ORDER_FILE="$STATE_DIR/edit-order"

# Read input
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Normalize path (remove leading ./ or project dir)
FILE_PATH=$(echo "$FILE_PATH" | sed "s|^${CLAUDE_PROJECT_DIR:-.}/||" | sed 's|^\./||')

# Check if this is a test file
is_test_file() {
    case "$1" in
        tests/*|test_*|*_test.sh|*.test.ts|*.test.js|*.spec.ts|*.spec.js)
            return 0
            ;;
    esac
    return 1
}

# Check if this is an implementation file that requires TDD
is_impl_file() {
    case "$1" in
        lib/*.sh|src/*.ts|src/*.js|src/*.py)
            return 0
            ;;
    esac
    return 1
}

# Get corresponding test file for an impl file
get_test_file() {
    impl="$1"
    case "$impl" in
        lib/*.sh)
            # lib/foo.sh -> tests/test_foo.sh
            base=$(basename "$impl" .sh)
            echo "tests/test_$base.sh"
            ;;
        src/*.ts)
            # src/foo.ts -> tests/foo.test.ts or src/__tests__/foo.test.ts
            base=$(basename "$impl" .ts)
            dir=$(dirname "$impl")
            echo "$dir/__tests__/$base.test.ts"
            ;;
        *)
            echo ""
            ;;
    esac
}

# If it's a test file, record it and allow
if is_test_file "$FILE_PATH"; then
    mkdir -p "$STATE_DIR"
    echo "$FILE_PATH" >> "$EDIT_ORDER_FILE"
    exit 0
fi

# If it's not an impl file, allow (docs, config, etc.)
if ! is_impl_file "$FILE_PATH"; then
    exit 0
fi

# It's an impl file - check if corresponding test was edited first
TEST_FILE=$(get_test_file "$FILE_PATH")

if [ -z "$TEST_FILE" ]; then
    # Can't determine test file, allow with warning
    exit 0
fi

# Check if test file was edited
if [ -f "$EDIT_ORDER_FILE" ] && grep -qF "$TEST_FILE" "$EDIT_ORDER_FILE"; then
    # Test file was edited, allow impl edit
    mkdir -p "$STATE_DIR"
    echo "$FILE_PATH" >> "$EDIT_ORDER_FILE"
    exit 0
fi

# Also check for alternative test file patterns
ALT_TESTS="tests/test_$(basename "$FILE_PATH" .sh).sh test_$(basename "$FILE_PATH")"
for alt in $ALT_TESTS; do
    if [ -f "$EDIT_ORDER_FILE" ] && grep -qF "$alt" "$EDIT_ORDER_FILE"; then
        mkdir -p "$STATE_DIR"
        echo "$FILE_PATH" >> "$EDIT_ORDER_FILE"
        exit 0
    fi
done

# Deny - need to edit test file first
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "TDD: Edit test file first. Expected: $TEST_FILE (or similar test file for $FILE_PATH)",
    "additionalContext": "Write the failing test before implementing. Edit the test file, run it to verify it fails, then implement."
  }
}
EOF
```

- [ ] **Step 4: Make hook executable**

```bash
chmod +x .claude/hooks/tdd-enforcement.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/test_hook_tdd_enforcement.sh`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/tdd-enforcement.sh tests/test_hook_tdd_enforcement.sh
git commit -m "feat: add TDD enforcement hook (gate 4)"
```

---

## Task 6: Completion Bundle Hook (Gates 5-11)

**Files:**
- Create: `.claude/hooks/completion-bundle.sh`
- Create: `tests/test_hook_completion_bundle.sh`

- [ ] **Step 1: Write failing test**

Create `tests/test_hook_completion_bundle.sh`:
```bash
#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"
    
    cp .claude/hooks/completion-bundle.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/completion-bundle.sh"
    
    # Initialize git for file tracking
    cd "$TEST_DIR"
    git init -q
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "completion: allows non-complete TaskUpdate" {
    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "completion: denies complete without simplify when impl files changed" {
    # Setup: plan requires tests, impl files were edited
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":true,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    
    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"
    
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("simplify")'
}

@test "completion: allows complete when all requirements met" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    
    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: accepts visual-skip-reason instead of visual-verified" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    echo "No UI changes in this task" > "$TEST_DIR/.claude/workflow-state/visual-skip-reason"
    
    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'
    
    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"
    
    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_hook_completion_bundle.sh`
Expected: FAIL

- [ ] **Step 3: Write completion bundle hook**

Create `.claude/hooks/completion-bundle.sh`:
```bash
#!/bin/sh
# Gates 5-11: Completion Bundle
# Blocks TaskUpdate to "completed" until all requirements are met
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
REQUIREMENTS_FILE="$STATE_DIR/plan-requirements.json"
EDIT_ORDER_FILE="$STATE_DIR/edit-order"

# Read input
INPUT=$(cat)
STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty')

# Only check on completion
if [ "$STATUS" != "completed" ]; then
    exit 0
fi

MISSING=""

# Check if impl files were edited (for simplify/review/visual checks)
has_impl_files() {
    if [ ! -f "$EDIT_ORDER_FILE" ]; then
        return 1
    fi
    grep -qE '^(lib/|src/)' "$EDIT_ORDER_FILE" 2>/dev/null
}

# Gate 5-8: Check plan requirements
if [ -f "$REQUIREMENTS_FILE" ]; then
    # Read requirements
    REQ_DOCS=$(jq -r '.documentation // false' "$REQUIREMENTS_FILE")
    REQ_WORKFLOW=$(jq -r '.workflow // false' "$REQUIREMENTS_FILE")
    REQ_ADR=$(jq -r '.adr // false' "$REQUIREMENTS_FILE")
    REQ_INSTALL=$(jq -r '.install // false' "$REQUIREMENTS_FILE")
    REQ_README=$(jq -r '.readme // false' "$REQUIREMENTS_FILE")
    
    # TODO: Check if required files were actually modified
    # For now, we trust that if the plan said N/A, it's false
    # Full implementation would check git diff
    
    if [ "$REQ_DOCS" = "true" ]; then
        # Check if doc files modified (simplified check)
        if ! git -C "${CLAUDE_PROJECT_DIR:-.}" diff --name-only HEAD 2>/dev/null | grep -qE '^docs/|\.md$'; then
            MISSING="${MISSING}${MISSING:+, }documentation updates"
        fi
    fi
    
    if [ "$REQ_ADR" = "true" ]; then
        if ! git -C "${CLAUDE_PROJECT_DIR:-.}" diff --name-only HEAD 2>/dev/null | grep -q '^docs/adr/'; then
            MISSING="${MISSING}${MISSING:+, }ADR document"
        fi
    fi
fi

# Gate 9: Simplify (for impl files)
if has_impl_files; then
    if [ ! -f "$STATE_DIR/simplify-complete" ]; then
        MISSING="${MISSING}${MISSING:+, }/simplify not run"
    fi
fi

# Gate 10: Code review (for any code files)
if has_impl_files; then
    if [ ! -f "$STATE_DIR/review-complete" ]; then
        MISSING="${MISSING}${MISSING:+, }code review not complete"
    fi
fi

# Gate 11: Visual verification (for impl/UI files)
if has_impl_files; then
    if [ ! -f "$STATE_DIR/visual-verified" ] && [ ! -f "$STATE_DIR/visual-skip-reason" ]; then
        MISSING="${MISSING}${MISSING:+, }visual verification (or skip justification)"
    fi
fi

if [ -n "$MISSING" ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Cannot complete task. Missing: $MISSING",
    "additionalContext": "Complete all workflow requirements before marking task done."
  }
}
EOF
    exit 0
fi

# All checks passed
exit 0
```

- [ ] **Step 4: Make hook executable**

```bash
chmod +x .claude/hooks/completion-bundle.sh
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/test_hook_completion_bundle.sh`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/completion-bundle.sh tests/test_hook_completion_bundle.sh
git commit -m "feat: add completion bundle hook (gates 5-11)"
```

---

## Task 7: Update /verify Skill

**Files:**
- Modify: `.claude/skills/verify/SKILL.md`

- [ ] **Step 1: Read current verify skill**

```bash
cat .claude/skills/verify/SKILL.md
```

- [ ] **Step 2: Add visual-verified state setting**

Add to the skill's completion section (after verification passes):

```markdown
## Post-Verification

After verification passes, set the visual verification state:

```bash
mkdir -p .claude/workflow-state
touch .claude/workflow-state/visual-verified
```

This satisfies Gate 11 of the enforced workflow.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/verify/SKILL.md
git commit -m "feat: update verify skill to set visual-verified state"
```

---

## Task 8: Create docs/WORKFLOW.md

**Files:**
- Create: `docs/WORKFLOW.md`

- [ ] **Step 1: Write workflow documentation**

Create `docs/WORKFLOW.md`:
```markdown
# Enforced Workflow System

This project uses Claude Code hooks to enforce a development workflow. These hooks create hard gates that block progress until workflow steps are completed.

## Workflow Overview

```
Branch confirm → Plan (8 sections) → Tasks → TDD → Updates → Simplify → Review → Verify
```

## Gates

| # | Gate | Trigger | Purpose |
|---|------|---------|---------|
| 1 | Branch awareness | First Edit/Write | Confirm branch before work |
| 2 | Planning checklist | ExitPlanMode | 8 sections required |
| 3 | Plan-to-tasks | Edit/Write (post-plan) | Tasks must exist |
| 4 | TDD | Edit (impl files) | Test file edited first |
| 5 | Documentation | TaskUpdate (complete) | Update if plan indicated |
| 6 | Workflow | TaskUpdate (complete) | Update skills/hooks/CLAUDE.md |
| 7 | Architecture | TaskUpdate (complete) | Create ADR if indicated |
| 8 | Install/README | TaskUpdate (complete) | Update if plan indicated |
| 9 | Simplify | TaskUpdate (complete) | Run /simplify for impl tasks |
| 10 | Code review | TaskUpdate (complete) | Review before task closes |
| 11 | Visual verification | TaskUpdate (complete) | Verify or justify skip |

## Planning Checklist (Gate 2)

Every plan must address these 8 sections (use "N/A - reason" if not applicable):

1. **Architecture Impact** - How does this affect system architecture?
2. **ADR** - Does this need an Architectural Decision Record?
3. **Workflow / State Machines** - Any workflow or state changes?
4. **Tests (unit, e2e, integration)** - What tests are needed?
5. **Documentation** - What docs need updating?
6. **Install / Uninstall** - Any installation changes?
7. **Release** - Release considerations?
8. **README** - README updates needed?

## TDD File Patterns (Gate 4)

| Implementation | Test |
|----------------|------|
| `lib/*.sh` | `tests/test_*.sh` |
| `src/*.ts` | `src/__tests__/*.test.ts` |
| `src/*.js` | `src/__tests__/*.test.js` |

## State Files

Located in `.claude/workflow-state/` (gitignored):

| File | Purpose | Set by |
|------|---------|--------|
| `branch-confirmed` | Branch acknowledged | User confirmation |
| `plan-exited` | ExitPlanMode called | Gate 2 |
| `plan-requirements.json` | Which sections need updates | Gate 2 |
| `tasks-created` | Tasks exist from plan | After TaskCreate |
| `edit-order` | Tracks file edit sequence | Gates 1, 4 |
| `simplify-complete` | /simplify was run | /simplify skill |
| `review-complete` | Code review done | Code review |
| `visual-verified` | Visual verification done | /verify skill |
| `visual-skip-reason` | Skip justification | Manual |

## Modifying the Workflow

| To change... | Edit... |
|--------------|---------|
| Planning checklist sections | `.claude/hooks/planning-checklist.sh` |
| TDD file patterns | `.claude/hooks/tdd-enforcement.sh` |
| Completion checks | `.claude/hooks/completion-bundle.sh` |
| Add new gate | `.claude/settings.json` + new hook |
| Disable gate temporarily | Comment out in `.claude/settings.json` |

## Troubleshooting

### Reset all state

```bash
rm -rf .claude/workflow-state/*
touch .claude/workflow-state/.gitkeep
```

### Disable all hooks temporarily

Add to `.claude/settings.json`:
```json
{
  "disableAllHooks": true
}
```

### Check current state

Run `/workflow` to see current workflow status.
```

- [ ] **Step 2: Commit**

```bash
git add docs/WORKFLOW.md
git commit -m "docs: add comprehensive workflow documentation"
```

---

## Task 9: Create /workflow Skill

**Files:**
- Create: `.claude/skills/workflow/SKILL.md`

- [ ] **Step 1: Create workflow skill**

```bash
mkdir -p .claude/skills/workflow
```

Create `.claude/skills/workflow/SKILL.md`:
```markdown
---
name: workflow
description: Show enforced workflow status and documentation
---

# Workflow Status

Show the current enforced workflow state and link to documentation.

## Check Current State

Run these commands to check workflow state:

```bash
# Branch confirmation
[ -f .claude/workflow-state/branch-confirmed ] && echo "Branch: $(cat .claude/workflow-state/branch-confirmed)" || echo "Branch: NOT CONFIRMED"

# Plan requirements
[ -f .claude/workflow-state/plan-requirements.json ] && cat .claude/workflow-state/plan-requirements.json || echo "No plan requirements"

# Completion state
echo "Simplify: $([ -f .claude/workflow-state/simplify-complete ] && echo 'done' || echo 'pending')"
echo "Review: $([ -f .claude/workflow-state/review-complete ] && echo 'done' || echo 'pending')"
echo "Visual: $([ -f .claude/workflow-state/visual-verified ] && echo 'done' || [ -f .claude/workflow-state/visual-skip-reason ] && echo 'skipped' || echo 'pending')"
```

## Documentation

Full workflow documentation: `docs/WORKFLOW.md`

## Quick Reference

| Gate | How to satisfy |
|------|---------------|
| Branch awareness | Confirm branch, then `echo "branch-name" > .claude/workflow-state/branch-confirmed` |
| Planning checklist | Include all 8 sections in plan |
| Plan-to-tasks | Use TaskCreate for plan steps |
| TDD | Edit test file before impl file |
| Documentation | Update docs if plan indicated |
| Workflow | Update skills/hooks if plan indicated |
| ADR | Create docs/adr/*.md if plan indicated |
| Install/README | Update if plan indicated |
| Simplify | Run /simplify, then `touch .claude/workflow-state/simplify-complete` |
| Code review | Complete review, then `touch .claude/workflow-state/review-complete` |
| Visual verification | Run /verify or `echo "reason" > .claude/workflow-state/visual-skip-reason` |
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/workflow/SKILL.md
git commit -m "feat: add workflow skill for status and docs"
```

---

## Task 10: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add enforced workflow rule**

Add to Rules section in `CLAUDE.md`:
```markdown
- Enforced workflow: 11 gates block progress until completed. See `docs/WORKFLOW.md` for details. Run `/workflow` for status.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add enforced workflow rule to CLAUDE.md"
```

---

## Task 11: Configure Hooks in settings.json

**Files:**
- Modify: `.claude/settings.json`

- [ ] **Step 1: Add hook configuration**

Add hooks section to `.claude/settings.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/branch-awareness.sh"
        }]
      },
      {
        "matcher": "ExitPlanMode",
        "hooks": [{
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/planning-checklist.sh"
        }]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [{
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/plan-to-tasks.sh"
        }]
      },
      {
        "matcher": "Edit",
        "hooks": [{
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/tdd-enforcement.sh"
        }]
      },
      {
        "matcher": "TaskUpdate",
        "hooks": [{
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/completion-bundle.sh"
        }]
      }
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add .claude/settings.json
git commit -m "feat: configure workflow enforcement hooks"
```

---

## Task 12: Integration Testing

- [ ] **Step 1: Test branch awareness gate**

Start new session, try to edit a file:
- Expected: Blocked with "Branch confirmation required"
- Confirm branch, retry edit
- Expected: Allowed

- [ ] **Step 2: Test planning checklist gate**

Create incomplete plan, try ExitPlanMode:
- Expected: Blocked with missing sections list
- Complete all 8 sections, retry
- Expected: Allowed

- [ ] **Step 3: Test plan-to-tasks gate**

After ExitPlanMode, try to edit without TaskCreate:
- Expected: Blocked with "Create tasks from plan"
- Create tasks, retry
- Expected: Allowed

- [ ] **Step 4: Test TDD gate**

Try to edit `lib/foo.sh` without editing `tests/test_foo.sh`:
- Expected: Blocked with "TDD: Edit test file first"
- Edit test file, retry impl edit
- Expected: Allowed

- [ ] **Step 5: Test completion bundle**

Try to mark task complete without running /simplify:
- Expected: Blocked with "/simplify not run"
- Run /simplify, /review, /verify, retry
- Expected: Allowed

- [ ] **Step 6: Full workflow test**

Run through complete workflow from start to finish:
1. Confirm branch
2. Create plan with all 8 sections
3. ExitPlanMode
4. Create tasks
5. TDD cycle (test → fail → impl → pass)
6. Run /simplify
7. Run code review
8. Run /verify
9. Mark task complete
- Expected: All gates pass, task completes

- [ ] **Step 7: Commit integration test results**

```bash
git commit --allow-empty -m "test: verify all workflow gates working"
```
