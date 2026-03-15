#!/bin/bash
# Setup script for auto-refactor demo GIF.
# Creates a temp environment with verification + refactoring enabled.
# Usage: eval "$(bash assets/setup-demo-refactor.sh)"

DEMO_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDELOOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Single-phase plan
cat > "$DEMO_DIR/PLAN.md" << 'PLAN'
# Caching Layer

## Phase 1: Implement Caching Layer
Create an in-memory cache module with TTL expiration.
Implement get, set, clear, and stats functions.
PLAN

# Initialize git repo
cd "$DEMO_DIR"
git init -q
git add .
git commit -q -m "init"

# Config: verification ON, refactoring ON (1 attempt for demo brevity)
mkdir -p "$DEMO_DIR/.claudeloop"
cat > "$DEMO_DIR/.claudeloop/.claudeloop.conf" << 'CONF'
AI_PARSE=false
VERIFY_PHASES=true
REFACTOR_PHASES=true
REFACTOR_MAX_RETRIES=1
SKIP_PERMISSIONS=true
CONF

# Set up fake-claude-dir for call counting
FAKE_DIR=$(mktemp -d)
printf '0' > "$FAKE_DIR/call_count"

# Put our custom fake-claude on PATH
FAKE_CLAUDE_BIN=$(mktemp -d)
cp "$SCRIPT_DIR/fake-claude-refactor" "$FAKE_CLAUDE_BIN/claude"
chmod +x "$FAKE_CLAUDE_BIN/claude"

# Output eval-able commands
echo "cd $DEMO_DIR"
echo "export FAKE_CLAUDE_DIR=$FAKE_DIR"
echo "export PATH=$FAKE_CLAUDE_BIN:\$PATH"
echo "export PATH=$CLAUDELOOP_DIR:\$PATH"
