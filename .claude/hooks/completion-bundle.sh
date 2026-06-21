#!/bin/sh
# Gates 5-11: Completion Bundle Hook
# Blocks TaskUpdate to completed until all requirements are met
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
if [ ! -d "$STATE_DIR" ] && [ -d ".claude/workflow-state" ]; then
    STATE_DIR=".claude/workflow-state"
fi
REQUIREMENTS_FILE="$STATE_DIR/plan-requirements.json"
EDIT_ORDER_FILE="$STATE_DIR/edit-order"

# Read stdin JSON
input=$(cat)

# Extract tool_name (handle multiline strings gracefully)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""

# Only check TaskUpdate tool
if [ "$tool_name" != "TaskUpdate" ]; then
    exit 0
fi

# Extract status from tool_input
status=$(printf '%s' "$input" | jq -r '.tool_input.status // empty' 2>/dev/null) || status=""

# Only check status: completed
if [ "$status" != "completed" ]; then
    exit 0
fi

# Dry-run mode: list missing gates without denying (usage: COMPLETION_DRY_RUN=1 sh hook.sh)
if [ "${COMPLETION_DRY_RUN:-}" = "1" ]; then
    _dry_run=true
else
    _dry_run=false
fi

# Collect missing requirements
missing=""

# Helper: Add to missing list
add_missing() {
    if [ -z "$missing" ]; then
        missing="$1"
    else
        missing="$missing, $1"
    fi
}

# Helper: Check if impl files were edited
has_impl_files() {
    if [ ! -f "$EDIT_ORDER_FILE" ]; then
        return 1
    fi
    # Check for lib/*.sh, src/* files
    grep -qE '^(lib/|src/)' "$EDIT_ORDER_FILE" 2>/dev/null
}

# Read plan requirements (if exists)
if [ -f "$REQUIREMENTS_FILE" ]; then
    # Gate 5: Documentation
    docs_required=$(jq -r '.documentation // false' "$REQUIREMENTS_FILE")
    if [ "$docs_required" = "true" ]; then
        if [ ! -f "$STATE_DIR/docs-complete" ]; then
            add_missing "documentation not updated"
        fi
    fi

    # Gate 6: Workflow/Skills
    workflow_required=$(jq -r '.workflow // false' "$REQUIREMENTS_FILE")
    if [ "$workflow_required" = "true" ]; then
        if [ ! -f "$STATE_DIR/workflow-complete" ]; then
            add_missing "workflow/skills not updated"
        fi
    fi

    # Gate 7: ADR
    adr_required=$(jq -r '.adr // false' "$REQUIREMENTS_FILE")
    if [ "$adr_required" = "true" ]; then
        if [ ! -f "$STATE_DIR/adr-complete" ]; then
            add_missing "ADR not created"
        fi
    fi

    # Gate 8: Install
    install_required=$(jq -r '.install // false' "$REQUIREMENTS_FILE")
    if [ "$install_required" = "true" ]; then
        if [ ! -f "$STATE_DIR/install-complete" ]; then
            add_missing "install.sh not updated"
        fi
    fi

    # Gate 8: README
    readme_required=$(jq -r '.readme // false' "$REQUIREMENTS_FILE")
    if [ "$readme_required" = "true" ]; then
        if [ ! -f "$STATE_DIR/readme-complete" ]; then
            add_missing "readme not updated"
        fi
    fi
fi

# Gate 9: Simplify
if has_impl_files; then
    if [ ! -f "$STATE_DIR/simplify-complete" ]; then
        add_missing "/simplify not run"
    fi
fi

# Gate 9.5: Feature registry (plan-driven path takes precedence over heuristic)
features_required="false"
if [ -f "$REQUIREMENTS_FILE" ]; then
    features_required=$(jq -r '.features // false' "$REQUIREMENTS_FILE")
fi
if [ "$features_required" = "true" ]; then
    if [ ! -f "$STATE_DIR/features-reviewed" ]; then
        add_missing "features update planned but docs/FEATURES.md not updated"
    fi
elif has_impl_files; then
    if [ ! -f "$STATE_DIR/features-reviewed" ]; then
        if [ ! -f "$STATE_DIR/features-no-impact" ] || \
           ! grep -q '[^[:space:]]' "$STATE_DIR/features-no-impact" 2>/dev/null; then
            add_missing "feature registry not reviewed (update docs/FEATURES.md or echo reason > .claude/workflow-state/features-no-impact)"
        fi
    fi
fi

# Gate 8b: README auto-detect for impl changes
if has_impl_files; then
    if [ ! -f "$STATE_DIR/readme-complete" ] && [ ! -f "$STATE_DIR/readme-no-user-impact" ]; then
        add_missing "README not reviewed (impl files changed — update README.md or touch .claude/workflow-state/readme-no-user-impact)"
    fi
fi

# Gate 10: Code review with test validation
_review_pass=false
for _session in "${CLAUDE_PROJECT_DIR:-.}"/.claude/review-sessions/*/README.md; do
    [ -f "$_session" ] || continue
    if grep -q "^result: PASS" "$_session"; then
        _session_dir=$(dirname "$_session")
        _test_log="$_session_dir/test-results.log"
        if [ -f "$_test_log" ] && grep -q "^FAIL:" "$_test_log"; then
            add_missing "review marked PASS but tests failed (check $_test_log)"
        else
            _review_pass=true
        fi
        break
    fi
done
if [ "$_review_pass" = false ] && [ ! -f "$STATE_DIR/review-complete" ]; then
    add_missing "code review not completed"
fi

# Gate 11: Visual verification (auto-skip for docs-only changes)
_docs_only=false
if [ ! -f "$EDIT_ORDER_FILE" ]; then
    _docs_only=true
elif ! grep -qE '^(lib/|src/|claudeloop$|install\.sh$|uninstall\.sh$)' "$EDIT_ORDER_FILE" 2>/dev/null; then
    _docs_only=true
fi
if [ "$_docs_only" = "false" ]; then
    if [ ! -f "$STATE_DIR/visual-verified" ] && [ ! -f "$STATE_DIR/visual-skip-reason" ]; then
        add_missing "visual verification not done (or no skip reason provided)"
    fi
fi

# If any missing, deny completion (or print in dry-run mode)
if [ -n "$missing" ]; then
    if [ "$_dry_run" = "true" ]; then
        printf 'Missing gates: %s\n' "$missing"
        exit 0
    fi
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Completion blocked: $missing",
    "additionalContext": "Complete all requirements before marking task as completed."
  }
}
EOF
fi
