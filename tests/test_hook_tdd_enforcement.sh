#!/usr/bin/env bats
# bats file_tags=hook

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"
    mkdir -p "$TEST_DIR/lib"
    mkdir -p "$TEST_DIR/tests"

    cp .claude/hooks/tdd-enforcement.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/tdd-enforcement.sh"
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

@test "tdd: records test file edits in edit-order" {
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"tests/test_bar.sh"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"

    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/.claude/workflow-state/edit-order" ]
    grep -q "tests/test_bar.sh" "$TEST_DIR/.claude/workflow-state/edit-order"
}

@test "tdd: matches lib/*.sh to tests/test_*.sh" {
    # Edit test_parser.sh first
    echo "tests/test_parser.sh" >> "$TEST_DIR/.claude/workflow-state/edit-order"

    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"lib/parser.sh"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tdd: denies lib/parser.sh when tests/test_other.sh was edited" {
    # Edit a different test file
    echo "tests/test_other.sh" >> "$TEST_DIR/.claude/workflow-state/edit-order"

    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"lib/parser.sh"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "tdd: denial message mentions TDD and test file" {
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"lib/foo.sh"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("test")'
}

@test "tdd: handles src/*.ts impl files" {
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"src/utils.ts"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "tdd: allows src/*.ts after corresponding test edited" {
    # Edit test file first
    echo "src/utils.test.ts" >> "$TEST_DIR/.claude/workflow-state/edit-order"

    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"src/utils.ts"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tdd: ignores Write tool (only checks Edit)" {
    INPUT='{"tool_name":"Write","tool_input":{"file_path":"lib/new.sh"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/tdd-enforcement.sh'"

    # Write is allowed (hook only checks Edit)
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
