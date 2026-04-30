#!/usr/bin/env bats
# bats file_tags=hook

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR"
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/.claude/workflow-state"
    mkdir -p "$TEST_DIR/.claude/hooks"

    cp .claude/hooks/completion-bundle.sh "$TEST_DIR/.claude/hooks/"
    chmod +x "$TEST_DIR/.claude/hooks/completion-bundle.sh"

    # Initialize git for diff checks
    cd "$TEST_DIR"
    git init -q
}

@test "completion: allows non-complete TaskUpdate" {
    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "completion: denies complete without simplify when impl files changed" {
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

@test "completion: denies without review-complete" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    # Note: review-complete is missing

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("review")'
}

@test "completion: denies when documentation required but not done" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":true,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("documentation")'
}

@test "completion: allows when documentation done" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":true,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/docs-complete"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: denies when ADR required but not done" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":true,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("ADR")'
}

@test "completion: allows when ADR done" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":true,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/adr-complete"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: denies when workflow required but not done" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":true,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("workflow")'
}

@test "completion: allows when workflow done" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":true,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/workflow-complete"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: denies when install required but not done" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":true,"release":false,"readme":false}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("install")'
}

@test "completion: denies when readme required but not done" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":true}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("readme")'
}

@test "completion: ignores other tools" {
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"foo.sh"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "completion: ignores TaskUpdate with other fields" {
    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","subject":"New subject"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "completion: no simplify required when no impl files changed" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    # edit-order has only test files
    echo "tests/test_foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: collects multiple missing requirements in reason" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":true,"workflow":true,"tests":false,"documentation":true,"install":false,"release":false,"readme":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    # Nothing is complete

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    # Should mention multiple issues
    reason=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
    echo "$reason" | grep -q "documentation"
    echo "$reason" | grep -q "ADR"
    echo "$reason" | grep -q "workflow"
}
