#!/bin/sh
# Shared utilities for fake_claude and fake_opencode test simulators.
# Source this file after setting FAKE_PROVIDER_DIR to the config directory.

# --- Call counting & capture ---
# Sets: count (call number), creates prompts/ and args/ directories
fake_provider_init() {
  count=$(cat "$FAKE_PROVIDER_DIR/call_count" 2>/dev/null || echo 0)
  count=$((count + 1))
  printf '%s' "$count" > "$FAKE_PROVIDER_DIR/call_count"
  mkdir -p "$FAKE_PROVIDER_DIR/prompts" "$FAKE_PROVIDER_DIR/args"
}

# Handle --version flag
# Args: version_string, "$@"
fake_provider_check_version() {
  local version_str="$1"
  shift
  for _arg in "$@"; do
    if [ "$_arg" = "--version" ]; then
      echo "$version_str"
      exit 0
    fi
  done
}

# Capture prompt from stdin
# Args: mode ("plain" or "stream-json")
fake_provider_capture_prompt() {
  local mode="${1:-plain}"
  if [ "$mode" = "stream-json" ]; then
    IFS= read -r _raw_input 2>/dev/null || _raw_input=""
    printf '%s' "$_raw_input" > "$FAKE_PROVIDER_DIR/prompts/prompt_$count"
  else
    cat > "$FAKE_PROVIDER_DIR/prompts/prompt_$count"
  fi
}

# Capture CLI args
fake_provider_capture_args() {
  printf '%s\n' "$@" > "$FAKE_PROVIDER_DIR/args/args_$count"
}

# --- Scenario selection ---
# Sets: scenario
fake_provider_select_scenario() {
  scenario=""
  if [ -f "$FAKE_PROVIDER_DIR/scenarios" ]; then
    scenario=$(sed -n "${count}p" "$FAKE_PROVIDER_DIR/scenarios" 2>/dev/null)
  fi
  [ -z "$scenario" ] && scenario=$(cat "$FAKE_PROVIDER_DIR/scenario" 2>/dev/null)
  [ -z "$scenario" ] && scenario="success"
}

# --- Prompt auto-detection ---
is_ai_parse_prompt() {
  local prompt_file="$FAKE_PROVIDER_DIR/prompts/prompt_$count"
  [ -f "$prompt_file" ] && grep -q 'plan extraction assistant' "$prompt_file"
}

is_verify_prompt() {
  local prompt_file="$FAKE_PROVIDER_DIR/prompts/prompt_$count"
  [ -f "$prompt_file" ] && grep -q 'DECOMPOSED' "$prompt_file"
}

is_phase_verify_prompt() {
  local prompt_file="$FAKE_PROVIDER_DIR/prompts/prompt_$count"
  [ -f "$prompt_file" ] && grep -qi 'verification' "$prompt_file"
}

# Write a file to CWD so git detects changes after phase execution.
_write_fake_file() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

# --- Exit code handling ---
# Args: default_exit
fake_provider_exit() {
  local default_exit="${1:-0}"
  local exit_code=""
  if [ -f "$FAKE_PROVIDER_DIR/exit_codes" ]; then
    exit_code=$(sed -n "${count}p" "$FAKE_PROVIDER_DIR/exit_codes" 2>/dev/null)
  fi
  exit "${exit_code:-$default_exit}"
}
