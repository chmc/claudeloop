#!/usr/bin/env bash
# bats file_tags=statusline

# Tests for examples/statusline-command.sh

SCRIPT="${BATS_TEST_DIRNAME}/../examples/statusline-command.sh"

# Helper: run the statusline script with JSON input
run_statusline() {
  printf '%s' "$1" | sh "$SCRIPT"
}

# --- Normal session (no worktree) ---

@test "statusline: normal session shows model, context, and branch from cwd" {
  # Use a real git dir so branch detection works
  local json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42},"cwd":"'"$(git rev-parse --show-toplevel)"'"}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus"* ]]
  [[ "$output" == *"ctx: 42%"* ]]
  # Should show some branch (we're in a git repo)
  [[ "$output" == *"|"* ]]
}

@test "statusline: normal session without context percentage shows dash" {
  local json='{"model":{"display_name":"Sonnet"},"cwd":"/tmp"}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sonnet"* ]]
  [[ "$output" == *"ctx: –"* ]]
}

# --- Worktree session (worktree.branch present) ---

@test "statusline: worktree session uses worktree.branch directly" {
  local json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":50},"cwd":"/some/wrong/path","worktree":{"branch":"wt/my-feature","path":"/tmp/wt-dir"}}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wt/my-feature"* ]]
  [[ "$output" == *"Opus"* ]]
  [[ "$output" == *"ctx: 50%"* ]]
}

@test "statusline: worktree.branch takes priority over cwd git" {
  # Even though cwd points to a real git repo, worktree.branch should win
  local json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10},"cwd":"'"$(git rev-parse --show-toplevel)"'","worktree":{"branch":"wt/override","path":"/tmp/fake"}}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wt/override"* ]]
}

# --- Hook-based worktree (worktree.path present, branch absent) ---

@test "statusline: hook-based worktree falls back to git from worktree.path" {
  # worktree.path points to a real git repo, branch is absent
  local json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30},"cwd":"/tmp/nonexistent","worktree":{"path":"'"$(git rev-parse --show-toplevel)"'"}}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus"* ]]
  # Should resolve branch from worktree.path (a real git dir)
  # The branch won't be empty because we're in a real repo
  [[ "$output" =~ \|.*\| ]]
}

# --- Detached HEAD worktree ---

@test "statusline: detached HEAD worktree omits branch" {
  # Both worktree.branch is empty and path points to a non-git dir
  local json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":20},"cwd":"/tmp","worktree":{"branch":"","path":"/tmp"}}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == "Opus | ctx: 20%" ]]
}

# --- Malformed worktree object ---

@test "statusline: malformed worktree object degrades to cwd" {
  # worktree exists but has no branch or path
  local json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":15},"cwd":"'"$(git rev-parse --show-toplevel)"'","worktree":{"name":"broken"}}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus"* ]]
  # Should fall through to git from cwd and find a branch
  [[ "$output" =~ \|.*\| ]]
}

# --- Older Claude Code (no worktree field at all) ---

@test "statusline: older Claude Code without worktree field uses cwd" {
  local json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":60},"cwd":"'"$(git rev-parse --show-toplevel)"'"}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus"* ]]
  [[ "$output" == *"ctx: 60%"* ]]
  # Should resolve branch from cwd
  [[ "$output" =~ \|.*\| ]]
}

# --- Output format ---

@test "statusline: output format is model | ctx | branch" {
  local json='{"model":{"display_name":"TestModel"},"context_window":{"used_percentage":75},"cwd":"/tmp","worktree":{"branch":"wt/test"}}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "TestModel | ctx: 75% | wt/test" ]
}

@test "statusline: non-git cwd without worktree shows model and ctx only" {
  local json='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":88},"cwd":"/tmp"}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "Opus | ctx: 88%" ]
}
