#!/bin/bash
# Setup script for VHS demo recording.
# Creates a temp environment and prints eval-able commands.
# Usage: eval "$(bash assets/setup-demo.sh)"

DEMO_DIR=$(mktemp -d)
FAKE_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDELOOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create a 5-phase plan (matches README Quick Start)
mkdir -p "$DEMO_DIR/.claudeloop"
cat > "$DEMO_DIR/.claudeloop/ai-parsed-plan.md" << 'PLAN'
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

## Phase 3: CRUD Model
**Depends on:** Phase 2

Implement Todo model with create, findAll, findById, update, and delete.
Use prepared statements and error handling.

## Phase 4: REST Endpoints
**Depends on:** Phase 3

Implement REST endpoints:
- GET /todos, POST /todos, PUT /todos/:id, DELETE /todos/:id
Include validation and error handling.

## Phase 5: Tests
**Depends on:** Phase 3, Phase 4

Write tests for model and API layers.
Aim for >90% coverage.
PLAN

# Initialize git repo (required by claudeloop)
cd "$DEMO_DIR"
git init -q
git add .
git commit -q -m "init"

# Create .claudeloop config pointing to the ai-parsed plan
cat > "$DEMO_DIR/.claudeloop/.claudeloop.conf" << 'CONF'
PLAN_FILE=.claudeloop/ai-parsed-plan.md
AI_PARSE=false
VERIFY_PHASES=false
REFACTOR_PHASES=false
SKIP_PERMISSIONS=true
CONF

# Put our custom fake-claude on PATH
FAKE_CLAUDE_BIN=$(mktemp -d)
cp "$SCRIPT_DIR/fake-claude-execution" "$FAKE_CLAUDE_BIN/claude"
chmod +x "$FAKE_CLAUDE_BIN/claude"

# Output eval-able commands
echo "cd $DEMO_DIR"
echo "export FAKE_CLAUDE_DIR=$FAKE_DIR"
echo "export PATH=$FAKE_CLAUDE_BIN:\$PATH"
echo "export PATH=$CLAUDELOOP_DIR:\$PATH"
