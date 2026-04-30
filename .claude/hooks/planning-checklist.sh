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

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Helper: check if section is empty (no content after heading, before next section heading)
# Returns 0 (true) if section is EMPTY
# Returns 1 (false) if section has content
is_empty_section() {
    section_name="$1"
    # Get content between this section and next ## heading
    # Use grep -i for case-insensitive matching
    section_start=$(grep -in "^## $section_name" "$plan_file" | head -1 | cut -d: -f1) || return 1
    if [ -z "$section_start" ]; then
        return 1
    fi
    # Get next few lines after heading, stop at next section heading
    tail_start="$((section_start + 1))"
    content=$(tail -n +"$tail_start" "$plan_file" | head -20)
    # Find first section heading (^## )
    next_section=$(echo "$content" | grep -n '^## ' | head -1 | cut -d: -f1)

    # If there's a next section, take only lines before it
    if [ -n "$next_section" ]; then
        # Remove one from next_section to get last line before it
        last_line="$((next_section - 1))"
        if [ "$last_line" -gt 0 ]; then
            content=$(echo "$content" | head -"$last_line")
        else
            content=""
        fi
    fi

    # Check if first non-empty line exists
    first_content=$(echo "$content" | grep -v '^$' | head -1)

    # If no content found (empty section)
    if [ -z "$first_content" ]; then
        return 0  # IS empty
    fi

    return 1  # NOT empty
}

# Helper: check if section starts with N/A
# Returns 0 (true) if section starts with N/A
# Returns 1 (false) otherwise
is_na_section() {
    section_name="$1"
    section_start=$(grep -in "^## $section_name" "$plan_file" | head -1 | cut -d: -f1) || return 1
    if [ -z "$section_start" ]; then
        return 1
    fi
    # Get next few lines after heading, stop at next section heading
    tail_start="$((section_start + 1))"
    content=$(tail -n +"$tail_start" "$plan_file" | head -20)
    # Find first section heading (^## )
    next_section=$(echo "$content" | grep -n '^## ' | head -1 | cut -d: -f1)

    # If there's a next section, take only lines before it
    if [ -n "$next_section" ]; then
        # Remove one from next_section to get last line before it
        last_line="$((next_section - 1))"
        if [ "$last_line" -gt 0 ]; then
            content=$(echo "$content" | head -"$last_line")
        else
            content=""
        fi
    fi

    # Get first non-empty line
    first_content=$(echo "$content" | grep -v '^$' | head -1 | tr '[:upper:]' '[:lower:]')

    if echo "$first_content" | grep -qE '^n/?a[[:space:]]|^n/?a$|^n/?a[[:space:]]*-'; then
        return 0  # IS N/A
    fi
    return 1  # NOT N/A
}

# Required sections (check case-insensitive)
# Each section must appear as a heading (## Section Name)
missing=""

# Check Architecture Impact
if ! echo "$plan_content" | grep -q "^## architecture impact"; then
    missing="$missing Architecture Impact (missing),"
elif is_empty_section "Architecture Impact" || is_empty_section "architecture impact"; then
    # Empty section detected
    missing="$missing Architecture Impact (empty),"
fi

# Check ADR
if ! echo "$plan_content" | grep -q "^## adr"; then
    missing="$missing ADR (missing),"
elif is_empty_section "ADR" || is_empty_section "adr"; then
    # Empty section detected
    missing="$missing ADR (empty),"
fi

# Check Workflow / State Machines
if ! echo "$plan_content" | grep -q "^## workflow"; then
    missing="$missing Workflow / State Machines (missing),"
elif is_empty_section "Workflow" || is_empty_section "workflow"; then
    # Empty section detected
    missing="$missing Workflow / State Machines (empty),"
fi

# Check Tests (with various formats)
if ! echo "$plan_content" | grep -qE "^## tests"; then
    missing="$missing Tests (missing),"
elif is_empty_section "Tests" || is_empty_section "tests"; then
    # Empty section detected
    missing="$missing Tests (empty),"
fi

# Check Documentation
if ! echo "$plan_content" | grep -q "^## documentation"; then
    missing="$missing Documentation (missing),"
elif is_empty_section "Documentation" || is_empty_section "documentation"; then
    # Empty section detected
    missing="$missing Documentation (empty),"
fi

# Check Install / Uninstall
if ! echo "$plan_content" | grep -q "^## install"; then
    missing="$missing Install / Uninstall (missing),"
elif is_empty_section "Install" || is_empty_section "install"; then
    # Empty section detected
    missing="$missing Install / Uninstall (empty),"
fi

# Check Release
if ! echo "$plan_content" | grep -q "^## release"; then
    missing="$missing Release (missing),"
elif is_empty_section "Release" || is_empty_section "release"; then
    # Empty section detected
    missing="$missing Release (empty),"
fi

# Check README
if ! echo "$plan_content" | grep -q "^## readme"; then
    missing="$missing README (missing),"
elif is_empty_section "README" || is_empty_section "readme"; then
    # Empty section detected
    missing="$missing README (empty),"
fi

# If any missing or empty, deny
if [ -n "$missing" ]; then
    # Remove trailing comma
    missing=$(echo "$missing" | sed 's/,$//')
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Plan missing or empty sections:$missing",
    "additionalContext": "All 8 sections required with non-empty content. Use 'N/A - reason' for sections that don't apply."
  }
}
EOF
    exit 0
fi

# All sections present - now check which have non-N/A content
# Extract section content and check if it starts with N/A

# Build requirements JSON
# Check each section case-insensitively (work required if NOT N/A)
arch_req="false"
if ! is_na_section "architecture impact" && ! is_na_section "Architecture Impact"; then
    arch_req="true"
fi

adr_req="false"
if ! is_na_section "adr" && ! is_na_section "ADR"; then
    adr_req="true"
fi

workflow_req="false"
if ! is_na_section "workflow" && ! is_na_section "Workflow"; then
    workflow_req="true"
fi

tests_req="false"
if ! is_na_section "tests" && ! is_na_section "Tests"; then
    tests_req="true"
fi

docs_req="false"
if ! is_na_section "documentation" && ! is_na_section "Documentation"; then
    docs_req="true"
fi

install_req="false"
if ! is_na_section "install" && ! is_na_section "Install"; then
    install_req="true"
fi

release_req="false"
if ! is_na_section "release" && ! is_na_section "Release"; then
    release_req="true"
fi

readme_req="false"
if ! is_na_section "readme" && ! is_na_section "README"; then
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

# Clean up tasks-created for fresh workflow cycle
rm -f "$STATE_DIR/tasks-created"

# Allow (exit 0 with no output)
exit 0
