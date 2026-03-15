#!/bin/bash
# Setup script for verification demo GIF.
# Creates a temp environment with verification enabled.
# Usage: eval "$(bash assets/setup-demo-verify.sh)"

DEMO_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDELOOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Single-phase plan
cat > "$DEMO_DIR/PLAN.md" << 'PLAN'
# Input Validation

## Phase 1: Add Input Validation
Add request validation middleware to the Express API routes.
Use express-validator for POST/PUT endpoints, return 400 on invalid input.
PLAN

# Initialize git repo
cd "$DEMO_DIR"
git init -q
git add .
git commit -q -m "init"

# Config: verification ON, no refactoring
mkdir -p "$DEMO_DIR/.claudeloop"
cat > "$DEMO_DIR/.claudeloop/.claudeloop.conf" << 'CONF'
AI_PARSE=false
VERIFY_PHASES=true
REFACTOR_PHASES=false
SKIP_PERMISSIONS=true
CONF

# Set up fake-claude-dir for call counting
FAKE_DIR=$(mktemp -d)
printf '0' > "$FAKE_DIR/call_count"

# Put our custom fake-claude on PATH
FAKE_CLAUDE_BIN=$(mktemp -d)
cp "$SCRIPT_DIR/fake-claude-verify" "$FAKE_CLAUDE_BIN/claude"
chmod +x "$FAKE_CLAUDE_BIN/claude"

# Output eval-able commands
echo "cd $DEMO_DIR"
echo "export FAKE_CLAUDE_DIR=$FAKE_DIR"
echo "export PATH=$FAKE_CLAUDE_BIN:\$PATH"
echo "export PATH=$CLAUDELOOP_DIR:\$PATH"
