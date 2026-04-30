#!/bin/sh
# Gate 4: TDD Enforcement
# Blocks impl file edits until corresponding test file is edited first
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
EDIT_ORDER_FILE="$STATE_DIR/edit-order"

# Read stdin JSON
input=$(cat)

# Extract tool_name (handle multiline strings gracefully)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""

# Only check Edit tool
if [ "$tool_name" != "Edit" ]; then
    exit 0
fi

# Extract file_path
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""

if [ -z "$file_path" ]; then
    exit 0
fi

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Helper: Check if file is a test file
is_test_file() {
    path="$1"
    case "$path" in
        tests/*|test_*|*_test.sh|*.test.ts|*.test.js|*.test.py|*_test.go|*_test.rs)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Helper: Check if file is an implementation file subject to TDD
is_impl_file() {
    path="$1"
    case "$path" in
        lib/*.sh|src/*.ts|src/*.js|src/*.py|src/*.go|src/*.rs)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Helper: Get expected test file pattern for an impl file
# lib/foo.sh -> tests/test_foo.sh
# src/utils.ts -> src/utils.test.ts
get_test_pattern() {
    path="$1"
    case "$path" in
        lib/*.sh)
            # lib/foo.sh -> foo
            basename=$(echo "$path" | sed 's|^lib/||; s|\.sh$||')
            echo "tests/test_${basename}.sh"
            ;;
        src/*.ts)
            # src/utils.ts -> src/utils.test.ts
            base=$(echo "$path" | sed 's|\.ts$||')
            echo "${base}.test.ts"
            ;;
        src/*.js)
            base=$(echo "$path" | sed 's|\.js$||')
            echo "${base}.test.js"
            ;;
        src/*.py)
            base=$(echo "$path" | sed 's|\.py$||')
            echo "${base}_test.py"
            ;;
        src/*.go)
            base=$(echo "$path" | sed 's|\.go$||')
            echo "${base}_test.go"
            ;;
        src/*.rs)
            # For Rust, tests are often in the same file or a tests/ directory
            base=$(echo "$path" | sed 's|\.rs$||')
            echo "${base}_test.rs"
            ;;
        *)
            echo ""
            ;;
    esac
}

# If editing a test file, record it and allow
if is_test_file "$file_path"; then
    echo "$file_path" >> "$EDIT_ORDER_FILE"
    exit 0
fi

# If not an impl file, allow (docs, config, etc.)
if ! is_impl_file "$file_path"; then
    exit 0
fi

# It's an impl file - check if corresponding test was edited first
test_pattern=$(get_test_pattern "$file_path")

if [ -z "$test_pattern" ]; then
    # Could not determine test pattern, allow
    exit 0
fi

# Check if test file was edited (exists in edit-order)
if [ -f "$EDIT_ORDER_FILE" ] && grep -qF "$test_pattern" "$EDIT_ORDER_FILE"; then
    # Test was edited first, record impl edit and allow
    echo "$file_path" >> "$EDIT_ORDER_FILE"
    exit 0
fi

# Deny - test file not edited first
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "TDD required: Edit test file first. Expected: $test_pattern",
    "additionalContext": "Write tests before implementation. Edit $test_pattern before $file_path."
  }
}
EOF
