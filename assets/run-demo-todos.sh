#!/bin/bash
# Wrapper for VHS demo: sets up environment and runs claudeloop
eval "$(bash "$(dirname "$0")/setup-demo-todos.sh")"
exec claudeloop --plan PLAN.md
