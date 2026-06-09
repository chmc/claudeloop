#!/bin/sh
# PostToolUse hook: mark tasks as created after TaskCreate
# Enables Gate 2 (planning-checklist) and Gate 3 (plan-to-tasks) to allow progress
set -eu

cat > /dev/null

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/tasks-created"

exit 0
