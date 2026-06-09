#!/usr/bin/env bats
# bats file_tags=hook

# Full plan template used by multiple tests
FULL_PLAN_TEMPLATE='# Test Plan

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

## Critic
Reviewed from multiple angles

## Verification
- Verify the feature works
- Check edge cases'

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"
    mkdir -p "$TEST_DIR/.claude/plans"

    cp .claude/hooks/planning-checklist.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/planning-checklist.sh"
}

@test "planning-checklist: denies plan without all 9 sections" {
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

@test "planning-checklist: allows complete plan with tasks created" {
    printf '%s\n' "$FULL_PLAN_TEMPLATE" > "$TEST_DIR/.claude/plans/test-plan.md"

    # tasks-created must exist and be newer than plan file
    sleep 0.1
    touch "$TEST_DIR/.claude/workflow-state/tasks-created"

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

## Critic
N/A - small change

## Verification
N/A - no verification steps
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

@test "planning-checklist: denies plan with empty section" {
    cat > "$TEST_DIR/.claude/plans/test-plan.md" <<'EOF'
# Test Plan

## Architecture Impact

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

## Critic
Reviewed

## Verification
N/A - no verification
EOF

    INPUT='{"tool_name":"ExitPlanMode","tool_input":{}}'
    export PLAN_FILE="$TEST_DIR/.claude/plans/test-plan.md"

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/planning-checklist.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("Architecture Impact (empty)")'
}

@test "planning-checklist: denies when tasks not created (Verification section present)" {
    printf '%s\n' "$FULL_PLAN_TEMPLATE" > "$TEST_DIR/.claude/plans/test-plan.md"
    # No tasks-created file

    INPUT='{"tool_name":"ExitPlanMode","tool_input":{}}'
    export PLAN_FILE="$TEST_DIR/.claude/plans/test-plan.md"

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/planning-checklist.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("task|Task")'
}

@test "planning-checklist: denies when tasks-created is stale (older than plan file)" {
    # Create tasks-created with explicit past timestamp, plan file is current
    printf '%s\n' "$FULL_PLAN_TEMPLATE" > "$TEST_DIR/.claude/plans/test-plan.md"
    touch -t 202001010000 "$TEST_DIR/.claude/workflow-state/tasks-created"

    INPUT='{"tool_name":"ExitPlanMode","tool_input":{}}'
    export PLAN_FILE="$TEST_DIR/.claude/plans/test-plan.md"

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/planning-checklist.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "planning-checklist: allows when Verification section is N/A (no tasks required)" {
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

## Critic
Reviewed from multiple angles

## Verification
N/A - no verification steps needed
EOF
    # No tasks-created file — should still be allowed

    INPUT='{"tool_name":"ExitPlanMode","tool_input":{}}'
    export PLAN_FILE="$TEST_DIR/.claude/plans/test-plan.md"

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/planning-checklist.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "planning-checklist: allows when Verification section is absent (no tasks required)" {
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

## Critic
Reviewed from multiple angles
EOF
    # No tasks-created file — should still be allowed

    INPUT='{"tool_name":"ExitPlanMode","tool_input":{}}'
    export PLAN_FILE="$TEST_DIR/.claude/plans/test-plan.md"

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/planning-checklist.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}
