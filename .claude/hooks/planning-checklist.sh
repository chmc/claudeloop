#!/bin/sh
# Gate 2: Planning Checklist
# Blocks ExitPlanMode unless plan has all 8 required sections
# See docs/WORKFLOW.md for details

set -eu

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/workflow-state"
PLANS_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/plans"

# Read stdin (hook input, not used but must consume)
cat > /dev/null

# Find plan file
if [ -n "${PLAN_FILE:-}" ] && [ -f "$PLAN_FILE" ]; then
    plan_file="$PLAN_FILE"
else
    # Find most recent .md in plans directory
    plan_file=""
    if [ -d "$PLANS_DIR" ]; then
        # shellcheck disable=SC2012
        plan_file=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1) || true
    fi
fi

if [ -z "$plan_file" ] || [ ! -f "$plan_file" ]; then
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "No plan file found. Create a plan in .claude/plans/ before exiting plan mode.",
    "additionalContext": "Plans must be stored in .claude/plans/ directory."
  }
}
EOF
    exit 0
fi

# Read plan content (lowercase for case-insensitive matching)
plan_content=$(cat "$plan_file" | tr '[:upper:]' '[:lower:]')

# Required sections (check case-insensitive)
# Each section must appear as a heading (## Section Name)
missing=""

# Check Architecture Impact
if ! echo "$plan_content" | grep -q "^## architecture impact"; then
    missing="$missing Architecture Impact,"
fi

# Check ADR
if ! echo "$plan_content" | grep -q "^## adr"; then
    missing="$missing ADR,"
fi

# Check Workflow / State Machines
if ! echo "$plan_content" | grep -q "^## workflow"; then
    missing="$missing Workflow / State Machines,"
fi

# Check Tests (with various formats)
if ! echo "$plan_content" | grep -qE "^## tests"; then
    missing="$missing Tests,"
fi

# Check Documentation
if ! echo "$plan_content" | grep -q "^## documentation"; then
    missing="$missing Documentation,"
fi

# Check Install / Uninstall
if ! echo "$plan_content" | grep -q "^## install"; then
    missing="$missing Install / Uninstall,"
fi

# Check Release
if ! echo "$plan_content" | grep -q "^## release"; then
    missing="$missing Release,"
fi

# Check README
if ! echo "$plan_content" | grep -q "^## readme"; then
    missing="$missing README,"
fi

# If any missing, deny
if [ -n "$missing" ]; then
    # Remove trailing comma
    missing=$(echo "$missing" | sed 's/,$//')
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Plan missing required sections:$missing",
    "additionalContext": "All 8 sections required: Architecture Impact, ADR, Workflow / State Machines, Tests, Documentation, Install / Uninstall, Release, README. Use 'N/A - reason' for sections that don't apply."
  }
}
EOF
    exit 0
fi

# All sections present - now check which have non-N/A content
# Extract section content and check if it starts with N/A

# Helper: check if section content is N/A
# Returns true (0) if content is NOT N/A (i.e., work required)
check_non_na() {
    section_name="$1"
    # Get content between this section and next ## heading
    # This is simplified - just checks if line after heading starts with n/a
    section_start=$(grep -n "^## $section_name" "$plan_file" | head -1 | cut -d: -f1) || return 1
    if [ -z "$section_start" ]; then
        return 1
    fi
    # Get next few lines after heading
    content=$(tail -n +"$((section_start + 1))" "$plan_file" | head -5)
    # Check if first non-empty line is N/A
    first_content=$(echo "$content" | grep -v '^$' | head -1 | tr '[:upper:]' '[:lower:]')
    if echo "$first_content" | grep -qE '^n/?a[[:space:]]|^n/?a$|^n/?a[[:space:]]*-'; then
        return 1  # Is N/A, no work required
    fi
    return 0  # Non-N/A, work required
}

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Build requirements JSON
# Check each section case-insensitively
arch_req="false"
if check_non_na "architecture impact" || check_non_na "Architecture Impact"; then
    arch_req="true"
fi

adr_req="false"
if check_non_na "adr" || check_non_na "ADR"; then
    adr_req="true"
fi

workflow_req="false"
if check_non_na "workflow" || check_non_na "Workflow"; then
    workflow_req="true"
fi

tests_req="false"
if check_non_na "tests" || check_non_na "Tests"; then
    tests_req="true"
fi

docs_req="false"
if check_non_na "documentation" || check_non_na "Documentation"; then
    docs_req="true"
fi

install_req="false"
if check_non_na "install" || check_non_na "Install"; then
    install_req="true"
fi

release_req="false"
if check_non_na "release" || check_non_na "Release"; then
    release_req="true"
fi

readme_req="false"
if check_non_na "readme" || check_non_na "README"; then
    readme_req="true"
fi

# Write requirements file
cat > "$STATE_DIR/plan-requirements.json" <<EOF
{
  "architecture": $arch_req,
  "adr": $adr_req,
  "workflow": $workflow_req,
  "tests": $tests_req,
  "documentation": $docs_req,
  "install": $install_req,
  "release": $release_req,
  "readme": $readme_req,
  "plan_file": "$plan_file"
}
EOF

# Touch plan-exited state file
touch "$STATE_DIR/plan-exited"

# Allow (exit 0 with no output)
exit 0
