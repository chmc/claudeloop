#!/bin/sh
set -eu

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$tool_name" in Edit|Write) ;; *) exit 0 ;; esac

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
case "$file_path" in
  */tests/test_*.sh) ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0
bats "$file_path" 2>&1 | tail -20
