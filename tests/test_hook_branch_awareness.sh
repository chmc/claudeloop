#!/usr/bin/env bats
# bats file_tags=hook

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
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

    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("test-branch")'
}
