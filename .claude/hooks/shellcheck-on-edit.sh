#!/bin/sh
set -eu

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$tool_name" in Edit|Write) ;; *) exit 0 ;; esac

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$file_path" ] || exit 0

# Skip test files — run-edited-tests.sh already handles them with bats
case "$file_path" in
  *tests/test_*.sh) exit 0 ;;
esac

# Match .sh files or extensionless files with #!/bin/sh shebang
case "$file_path" in
  *.sh) ;;
  *)
    [ -f "$file_path" ] || exit 0
    first_line=$(head -1 "$file_path" 2>/dev/null) || exit 0
    case "$first_line" in
      '#!/bin/sh'*|'#!/bin/bash'*|'#!/usr/bin/env sh'*|'#!/usr/bin/env bash'*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

[ -f "$file_path" ] || exit 0
shellcheck -s sh -e SC3043 "$file_path" 2>&1 || true
