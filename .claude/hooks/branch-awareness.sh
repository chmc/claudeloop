#!/bin/sh
# Gate 1: Branch Awareness
# Blocks first Edit/Write until branch is confirmed
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
CONFIRMED_FILE="$STATE_DIR/branch-confirmed"

# Check if already confirmed
if [ -f "$CONFIRMED_FILE" ]; then
    # Already confirmed, allow
    exit 0
fi

# Get current branch
BRANCH=$(git -C "${CLAUDE_PROJECT_DIR:-.}" branch --show-current 2>/dev/null || echo "unknown")

# Deny with branch info
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Branch confirmation required. Current branch: $BRANCH. Please confirm this is correct for your task, then I will set the confirmation state.",
    "additionalContext": "To proceed, acknowledge the branch is correct. The workflow will then allow edits."
  }
}
EOF
