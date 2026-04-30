#!/usr/bin/env bats
# bats file_tags=hook

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"
    mkdir -p "$TEST_DIR/.claude/plans"

    cp .claude/hooks/planning-checklist.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/planning-checklist.sh"
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
