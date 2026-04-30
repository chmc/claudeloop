#!/bin/sh
# Gate 3: Plan-to-Tasks
# Blocks first Edit/Write after ExitPlanMode until tasks are created
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"

# If no plan-exited state, we're not in post-plan phase
if [ ! -f "$STATE_DIR/plan-exited" ]; then
    exit 0
fi

# If tasks already created, allow
if [ -f "$STATE_DIR/tasks-created" ]; then
    exit 0
fi

# Deny - need to create tasks first
cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Create tasks from plan steps before implementation. Use TaskCreate for each implementation step, then this gate will allow edits.",
    "additionalContext": "The plan has been approved. Convert plan steps to tasks for tracking before writing code."
  }
}
EOF
