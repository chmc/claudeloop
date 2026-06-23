#!/bin/bash
# Wrapper for VHS demo: sets up environment and runs expect-driven nudge flow
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
eval "$(bash "$SCRIPT_DIR/setup-demo-nudge.sh")"
exec expect "$SCRIPT_DIR/demo-nudge.expect"
