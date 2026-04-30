#!/usr/bin/env bash
# bats file_tags=hook

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"

    cp .claude/hooks/plan-to-tasks.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/plan-to-tasks.sh"
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
