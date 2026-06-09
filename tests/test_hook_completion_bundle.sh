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

@test "completion: denies when impl files changed but feature registry not reviewed" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    # No features-reviewed or features-no-impact

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("feature registry")'
}

@test "completion: allows when features-reviewed exists" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/features-reviewed"
    touch "$TEST_DIR/.claude/workflow-state/readme-no-user-impact"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: allows when features-no-impact exists" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    echo "Refactoring only, no new features" > "$TEST_DIR/.claude/workflow-state/features-no-impact"
    touch "$TEST_DIR/.claude/workflow-state/readme-no-user-impact"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: denies when impl files changed but README not reviewed" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/features-reviewed"
    # No readme-complete or readme-no-user-impact

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("README")'
}

@test "completion: allows when readme-complete exists" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/features-reviewed"
    touch "$TEST_DIR/.claude/workflow-state/readme-complete"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: allows when readme-no-user-impact exists" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/features-reviewed"
    echo "internal change only" > "$TEST_DIR/.claude/workflow-state/readme-no-user-impact"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: no features check when only test files changed" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    echo "tests/test_foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    # No features-reviewed, no simplify-complete (not needed for tests-only)

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: denies when features-no-impact is empty (touch only)" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false,"features":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/readme-no-user-impact"
    touch "$TEST_DIR/.claude/workflow-state/features-no-impact"
    # features-no-impact is 0 bytes — should be denied

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("feature registry")'
}

@test "completion: denies when features-no-impact contains only whitespace" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false,"features":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/readme-no-user-impact"
    printf '\n   \n' > "$TEST_DIR/.claude/workflow-state/features-no-impact"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("feature registry")'
}

@test "completion: allows when features-no-impact has real content" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false,"features":false}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/readme-no-user-impact"
    echo "Bug fix only, no user-facing feature changes" > "$TEST_DIR/.claude/workflow-state/features-no-impact"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: denies when plan features:true but only features-no-impact exists" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false,"features":true}
EOF
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    echo "no feature changes" > "$TEST_DIR/.claude/workflow-state/features-no-impact"
    # features-reviewed is missing — plan says features: true, skip not allowed

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("features update planned")'
}

@test "completion: allows when plan features:true and features-reviewed exists" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false,"features":true}
EOF
    echo "lib/foo.sh" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    touch "$TEST_DIR/.claude/workflow-state/readme-no-user-impact"
    touch "$TEST_DIR/.claude/workflow-state/features-reviewed"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: denies when plan features:true with no impl files and no features-reviewed" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false,"features":true}
EOF
    # No edit-order file (no impl files changed)
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/visual-verified"
    # features: true should fire even without impl files (plan-driven)

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("features update planned")'
}

@test "completion: docs-only edit-order skips visual verification requirement" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    # Only .md files edited — docs-only change
    echo "CLAUDE.md" > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    # No visual-verified, no visual-skip-reason

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: no edit-order file skips visual verification requirement" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    # No edit-order at all (pure docs/discussion session)
    touch "$TEST_DIR/.claude/workflow-state/review-complete"

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    [ -z "$output" ] || ! echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "completion: impl file in edit-order still requires visual verification" {
    cat > "$TEST_DIR/.claude/workflow-state/plan-requirements.json" <<'EOF'
{"architecture":false,"adr":false,"workflow":false,"tests":false,"documentation":false,"install":false,"release":false,"readme":false}
EOF
    printf 'CLAUDE.md\nlib/foo.sh\n' > "$TEST_DIR/.claude/workflow-state/edit-order"
    touch "$TEST_DIR/.claude/workflow-state/simplify-complete"
    touch "$TEST_DIR/.claude/workflow-state/review-complete"
    touch "$TEST_DIR/.claude/workflow-state/features-reviewed"
    touch "$TEST_DIR/.claude/workflow-state/readme-no-user-impact"
    # No visual-verified

    INPUT='{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'

    run bash -c "echo '$INPUT' | '$TEST_DIR/.claude/hooks/completion-bundle.sh'"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("visual verification")'
}
