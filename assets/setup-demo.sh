#!/bin/bash
# Setup script for VHS demo recording.
# Creates a temp environment and prints eval-able commands.
# Usage: eval "$(bash assets/setup-demo.sh)"

DEMO_DIR=$(mktemp -d)
FAKE_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDELOOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create a simple 3-phase plan
cat > "$DEMO_DIR/PLAN.md" << 'PLAN'
# Todo API

## Phase 1: Project Setup
Create a new Node.js project with Express.
Initialize npm, install express and sqlite3.
Create src/ and tests/ directories.

## Phase 2: Database Schema
**Depends on:** Phase 1

Create SQLite schema for todos table:
- id, title, completed, created_at
Add migration script.

## Phase 3: API Routes
**Depends on:** Phase 2

Implement REST endpoints:
- GET /todos, POST /todos, PUT /todos/:id, DELETE /todos/:id
Include validation and error handling.
PLAN

# Initialize git repo (required by claudeloop)
cd "$DEMO_DIR"
git init -q
git add .
git commit -q -m "init"

# Create .claudeloop config to disable AI parsing, verification, and refactoring
mkdir -p "$DEMO_DIR/.claudeloop"
cat > "$DEMO_DIR/.claudeloop/.claudeloop.conf" << 'CONF'
AI_PARSE=false
VERIFY_PHASES=false
REFACTOR_PHASES=false
SKIP_PERMISSIONS=true
CONF

# Copy fake-claude custom outputs
cp "$SCRIPT_DIR/demo-execution-output/custom_output_1" "$FAKE_DIR/custom_output_1"
cp "$SCRIPT_DIR/demo-execution-output/custom_output_2" "$FAKE_DIR/custom_output_2"
cp "$SCRIPT_DIR/demo-execution-output/custom_output_3" "$FAKE_DIR/custom_output_3"
printf 'custom\n' > "$FAKE_DIR/scenario"

# Put fake-claude on PATH
FAKE_CLAUDE_BIN=$(mktemp -d)
cp "$SCRIPT_DIR/../tests/fake_claude" "$FAKE_CLAUDE_BIN/claude"
chmod +x "$FAKE_CLAUDE_BIN/claude"

# Output eval-able commands
echo "cd $DEMO_DIR"
echo "export FAKE_CLAUDE_DIR=$FAKE_DIR"
echo "export PATH=$FAKE_CLAUDE_BIN:\$PATH"
echo "export FAKE_CLAUDE_THINK=0.5"
echo "export PATH=$CLAUDELOOP_DIR:\$PATH"
