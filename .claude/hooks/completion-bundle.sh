#!/bin/sh
# Gates 5-11: Completion Bundle Hook
# Blocks TaskUpdate to completed until all requirements are met
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
REQUIREMENTS_FILE="$STATE_DIR/plan-requirements.json"
EDIT_ORDER_FILE="$STATE_DIR/edit-order"

# Read stdin JSON
input=$(cat)

# Extract tool_name
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

# Only check TaskUpdate tool
if [ "$tool_name" != "TaskUpdate" ]; then
    exit 0
fi

# Extract status from tool_input
status=$(echo "$input" | jq -r '.tool_input.status // empty')

# Only check status: completed
if [ "$status" != "completed" ]; then
    exit 0
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

# Gate 9: Simplify (if impl files were edited)
if has_impl_files; then
    if [ ! -f "$STATE_DIR/simplify-complete" ]; then
        add_missing "/simplify not run"
    fi
fi

# Gate 10: Code review
if [ ! -f "$STATE_DIR/review-complete" ]; then
    add_missing "code review not completed"
fi

# Gate 11: Visual verification
if [ ! -f "$STATE_DIR/visual-verified" ] && [ ! -f "$STATE_DIR/visual-skip-reason" ]; then
    add_missing "visual verification not done (or no skip reason provided)"
fi

# If any missing, deny completion
if [ -n "$missing" ]; then
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
