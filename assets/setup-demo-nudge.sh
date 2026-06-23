#!/bin/bash
# Setup script for nudge demo GIF.
# Creates a temp environment with a 2-phase plan.
# Usage: eval "$(bash assets/setup-demo-nudge.sh)"

DEMO_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDELOOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$DEMO_DIR/.claudeloop"
cat > "$DEMO_DIR/PLAN.md" << 'PLAN'
# Todo App

## Phase 1: Project Setup
Initialize npm project, create src/ directory, add src/db.js with SQLite connection.

## Phase 2: Query Implementation
**Depends on:** Phase 1

Implement CRUD queries for the todos table in src/queries.js.
PLAN

cd "$DEMO_DIR"
git init -q
git add .
git commit -q -m "init"

cat > "$DEMO_DIR/.claudeloop/.claudeloop.conf" << 'CONF'
AI_PARSE=false
VERIFY_PHASES=false
REFACTOR_PHASES=false
SKIP_PERMISSIONS=true
BASE_DELAY=1
CONF

FAKE_DIR=$(mktemp -d)
printf '0' > "$FAKE_DIR/call_count"

FAKE_CLAUDE_BIN=$(mktemp -d)
cp "$SCRIPT_DIR/fake-claude-nudge" "$FAKE_CLAUDE_BIN/claude"
chmod +x "$FAKE_CLAUDE_BIN/claude"

echo "cd $DEMO_DIR"
echo "export FAKE_CLAUDE_DIR=$FAKE_DIR"
echo "export PATH=$FAKE_CLAUDE_BIN:\$PATH"
echo "export PATH=$CLAUDELOOP_DIR:\$PATH"
