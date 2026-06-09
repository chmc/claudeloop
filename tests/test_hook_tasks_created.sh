#!/usr/bin/env bats
# bats file_tags=hook

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"

    cp .claude/hooks/tasks-created.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/tasks-created.sh"
}

@test "tasks-created: sets state even without plan-exited" {
    # No plan-exited file — should still set tasks-created
    run bash -c "echo '{}' | '$TEST_DIR/.claude/hooks/tasks-created.sh'"

    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/.claude/workflow-state/tasks-created" ]
}

@test "tasks-created: sets state when plan-exited exists" {
    touch "$TEST_DIR/.claude/workflow-state/plan-exited"

    run bash -c "echo '{}' | '$TEST_DIR/.claude/hooks/tasks-created.sh'"

    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/.claude/workflow-state/tasks-created" ]
}

@test "tasks-created: creates state dir if missing" {
    rm -rf "$TEST_DIR/.claude/workflow-state"

    run bash -c "echo '{}' | '$TEST_DIR/.claude/hooks/tasks-created.sh'"

    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/.claude/workflow-state/tasks-created" ]
}
