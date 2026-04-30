#!/bin/sh
# PostToolUse hook: mark tasks as created after TaskCreate
# Enables Gate 3 (plan-to-tasks) to allow edits
set -eu

# Read input (required, but we don't need to parse it)
cat > /dev/null

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"

# Only create if plan-exited exists (we're in post-plan phase)
if [ -f "$STATE_DIR/plan-exited" ]; then
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/tasks-created"
fi

exit 0
