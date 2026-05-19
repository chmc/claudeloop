#!/bin/sh
# PostToolUse: ExitPlanMode — prompt Claude to create tasks from Verification section
set -eu

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
[ "$tool_name" = "ExitPlanMode" ] || exit 0

PLAN_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/plans"
PLAN_FILE=$(find "$PLAN_DIR" -name "*.md" -type f -mmin -5 2>/dev/null | head -1)
[ -f "$PLAN_FILE" ] || exit 0

# Extract Verification items (stops at next ## or EOF)
ITEMS=$(awk '/^## Verification/{p=1;next} /^## /{p=0} p' "$PLAN_FILE" \
    | grep -E '^\s*[-*0-9]+\.|^\s*- \[' \
    | sed 's/^[[:space:]]*[-*0-9.]*[[:space:]]*//' \
    | sed 's/^- \[.\] //' \
    | grep -v '^$' \
    | head -10)

[ -n "$ITEMS" ] || exit 0

ITEMS_ESCAPED=$(printf '%s' "$ITEMS" | awk '{printf "%s\\n", $0}')

cat <<EOF
{
  "additionalContext": "REQUIRED: Use TaskCreate for each Verification item before writing any code:\n${ITEMS_ESCAPED}"
}
EOF
