#!/bin/sh
# PostToolUse hook: sync global plans to project directory
# Runs automatically after Write/Edit - no permission prompt needed
set -eu

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

case "$file_path" in
    "$HOME/.claude/plans/"*.md)
        mkdir -p "$CLAUDE_PROJECT_DIR/.claude/plans"
        cp "$file_path" "$CLAUDE_PROJECT_DIR/.claude/plans/"
        ;;
esac

exit 0
