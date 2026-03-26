#!/usr/bin/env bash
# bats file_tags=config

# Tests for lib/config.sh — bool_yn, load_config edge cases, run_config_wizard

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/config.sh"
  _tmpdir="$BATS_TEST_TMPDIR"
  MAX_RETRIES=10
  SKIP_PERMISSIONS=false
  VERIFY_PHASES=false
  _CLI_MAX_RETRIES=""
  _CLI_SKIP_PERMISSIONS=""
  _CLI_VERIFY_PHASES=""
  # Stub UI functions not available in test context
  print_success() { :; }
  print_warning() { :; }
  export -f print_success
  export -f print_warning
}

teardown() { :; }

# --- bool_yn() ---

@test "bool_yn: true returns y" {
  run bool_yn "true"
  [ "$status" -eq 0 ]
  [ "$output" = "y" ]
}

@test "bool_yn: false returns n" {
  run bool_yn "false"
  [ "$status" -eq 0 ]
  [ "$output" = "n" ]
}

@test "bool_yn: empty string returns n" {
  run bool_yn ""
  [ "$status" -eq 0 ]
  [ "$output" = "n" ]
}

@test "bool_yn: arbitrary string returns n" {
  run bool_yn "anything_else"
  [ "$status" -eq 0 ]
  [ "$output" = "n" ]
}

# --- write_config() gitignore guard ---

@test "write_config creates .gitignore with .claudeloop/ when none exists" {
  cd "$_tmpdir"
  DRY_RUN=false
  PLAN_FILE="test.md" PROGRESS_FILE="progress.md" SIMPLE_MODE=false
  SKIP_PERMISSIONS=false BASE_DELAY=5 STREAM_TRUNCATE_LEN=200
  MAX_PHASE_TIME=600 IDLE_TIMEOUT=120 VERIFY_TIMEOUT=300
  VERIFY_PHASES=false REFACTOR_PHASES=false
  rm -f .gitignore
  write_config
  grep -qF '.claudeloop/' .gitignore
}

@test "write_config appends .claudeloop/ to existing .gitignore" {
  cd "$_tmpdir"
  DRY_RUN=false
  PLAN_FILE="test.md" PROGRESS_FILE="progress.md" SIMPLE_MODE=false
  SKIP_PERMISSIONS=false BASE_DELAY=5 STREAM_TRUNCATE_LEN=200
  MAX_PHASE_TIME=600 IDLE_TIMEOUT=120 VERIFY_TIMEOUT=300
  VERIFY_PHASES=false REFACTOR_PHASES=false
  printf 'node_modules/\n' > .gitignore
  write_config
  grep -qF '.claudeloop/' .gitignore
  grep -qF 'node_modules/' .gitignore
}

@test "write_config preserves .gitignore when .claudeloop/ already present" {
  cd "$_tmpdir"
  DRY_RUN=false
  PLAN_FILE="test.md" PROGRESS_FILE="progress.md" SIMPLE_MODE=false
  SKIP_PERMISSIONS=false BASE_DELAY=5 STREAM_TRUNCATE_LEN=200
  MAX_PHASE_TIME=600 IDLE_TIMEOUT=120 VERIFY_TIMEOUT=300
  VERIFY_PHASES=false REFACTOR_PHASES=false
  printf '.claudeloop/\n' > .gitignore
  write_config
  count=$(grep -cF '.claudeloop/' .gitignore)
  [ "$count" -eq 1 ]
}

# --- load_config() edge cases ---

@test "load_config: returns 0 when conf file missing" {
  cd "$_tmpdir"
  run load_config
  [ "$status" -eq 0 ]
}

@test "load_config: skips comment lines" {
  mkdir -p "$_tmpdir/.claudeloop"
  printf '# This is a comment\nMAX_RETRIES=5\n' > "$_tmpdir/.claudeloop/.claudeloop.conf"
  cd "$_tmpdir"
  load_config
  [ "$MAX_RETRIES" = "5" ]
}

@test "load_config: skips blank lines" {
  mkdir -p "$_tmpdir/.claudeloop"
  printf '\n\nMAX_RETRIES=7\n\n' > "$_tmpdir/.claudeloop/.claudeloop.conf"
  cd "$_tmpdir"
  load_config
  [ "$MAX_RETRIES" = "7" ]
}

@test "load_config: ignores unknown keys" {
  mkdir -p "$_tmpdir/.claudeloop"
  printf 'UNKNOWN_KEY=some_value\nMAX_RETRIES=3\n' > "$_tmpdir/.claudeloop/.claudeloop.conf"
  cd "$_tmpdir"
  load_config
  [ "$MAX_RETRIES" = "3" ]
  # UNKNOWN_KEY should not be set as a global
  [ -z "${UNKNOWN_KEY:-}" ]
}

# --- run_config_wizard() ---

@test "run_config_wizard: all defaults (Enter×3) leaves globals unchanged" {
  printf '\n\n\n' > "$_tmpdir/input"
  run_config_wizard < "$_tmpdir/input" > /dev/null
  [ "$MAX_RETRIES" = "10" ]
  [ "$SKIP_PERMISSIONS" = "false" ]
  [ "$VERIFY_PHASES" = "false" ]
}

@test "run_config_wizard: custom MAX_RETRIES updates global" {
  printf '5\n\n\n' > "$_tmpdir/input"
  run_config_wizard < "$_tmpdir/input" > /dev/null
  [ "$MAX_RETRIES" = "5" ]
}

@test "run_config_wizard: _CLI_MAX_RETRIES set skips prompt and shows message" {
  _CLI_MAX_RETRIES=1
  MAX_RETRIES=20
  output=$(printf '\n\n' | run_config_wizard)
  [ "$MAX_RETRIES" = "20" ]
  [[ "$output" == *"using --max-retries"* ]]
}

# --- commit_gitignore() ---

# Helper: create a git repo in $_tmpdir with an initial commit
_init_git_repo() {
  git -C "$_tmpdir" init -q
  git -C "$_tmpdir" config user.email "test@test.com"
  git -C "$_tmpdir" config user.name "Test"
  printf 'init\n' > "$_tmpdir/README"
  git -C "$_tmpdir" add README
  git -C "$_tmpdir" commit -q -m "initial"
}

@test "commit_gitignore: commits when .gitignore is modified (tracked)" {
  cd "$_tmpdir"
  _init_git_repo
  # Create and commit a .gitignore, then modify it
  printf 'node_modules/\n' > .gitignore
  git add .gitignore && git commit -q -m "add gitignore"
  printf '\n# claudeloop runtime\n.claudeloop/\n' >> .gitignore
  # .gitignore should have uncommitted changes
  [ -n "$(git status --porcelain .gitignore)" ]
  commit_gitignore
  # After commit, .gitignore should be clean
  [ -z "$(git status --porcelain .gitignore)" ]
  git log --oneline -1 | grep -qF "chore: add .claudeloop/ to .gitignore"
}

@test "commit_gitignore: commits when .gitignore is new (untracked)" {
  cd "$_tmpdir"
  _init_git_repo
  printf '.claudeloop/\n' > .gitignore
  [ -n "$(git status --porcelain .gitignore)" ]
  commit_gitignore
  [ -z "$(git status --porcelain .gitignore)" ]
  git log --oneline -1 | grep -qF "chore: add .claudeloop/ to .gitignore"
}

@test "commit_gitignore: no-op when .gitignore has no changes" {
  cd "$_tmpdir"
  _init_git_repo
  printf '.claudeloop/\n' > .gitignore
  git add .gitignore && git commit -q -m "add gitignore"
  local before after
  before=$(git rev-parse HEAD)
  commit_gitignore
  after=$(git rev-parse HEAD)
  [ "$before" = "$after" ]
}

@test "commit_gitignore: non-fatal outside a git repo" {
  cd "$_tmpdir"
  # No git init — not a repo
  printf '.claudeloop/\n' > .gitignore
  run commit_gitignore
  [ "$status" -eq 0 ]
}

@test "commit_gitignore: does not crash on empty repo (no prior commits)" {
  cd "$_tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  printf '.claudeloop/\n' > .gitignore
  run commit_gitignore
  [ "$status" -eq 0 ]
  # Should have committed (first commit in repo)
  git log --oneline -1 | grep -qF "chore: add .claudeloop/ to .gitignore"
}

@test "commit_gitignore: does not disturb other staged files" {
  cd "$_tmpdir"
  _init_git_repo
  printf '.claudeloop/\n' > .gitignore
  printf 'other\n' > other.txt
  git add other.txt
  commit_gitignore
  # other.txt should still be staged (not committed)
  git status --porcelain other.txt | grep -q '^A'
}

# --- load_config() with custom path ---

@test "load_config: accepts custom conf path argument" {
  mkdir -p "$_tmpdir/custom"
  printf 'MAX_RETRIES=42\n' > "$_tmpdir/custom/my.conf"
  cd "$_tmpdir"
  load_config "$_tmpdir/custom/my.conf"
  [ "$MAX_RETRIES" = "42" ]
}

# --- load_config_from_latest_archive() ---

@test "load_config_from_latest_archive: loads from most recent archive" {
  mkdir -p "$_tmpdir/.claudeloop/archive/20260315-120000"
  printf 'MAX_RETRIES=3\n' > "$_tmpdir/.claudeloop/archive/20260315-120000/.claudeloop.conf"
  mkdir -p "$_tmpdir/.claudeloop/archive/20260316-120000"
  printf 'MAX_RETRIES=7\n' > "$_tmpdir/.claudeloop/archive/20260316-120000/.claudeloop.conf"
  cd "$_tmpdir"

  load_config_from_latest_archive

  [ "$MAX_RETRIES" = "7" ]
}

@test "load_config_from_latest_archive: no-op when no archives exist" {
  mkdir -p "$_tmpdir/.claudeloop"
  cd "$_tmpdir"
  MAX_RETRIES=10

  load_config_from_latest_archive

  [ "$MAX_RETRIES" = "10" ]
}

@test "load_config_from_latest_archive: no-op when latest archive has no conf" {
  mkdir -p "$_tmpdir/.claudeloop/archive/20260316-120000"
  # No .claudeloop.conf in this archive
  cd "$_tmpdir"
  MAX_RETRIES=10

  load_config_from_latest_archive

  [ "$MAX_RETRIES" = "10" ]
}

@test "load_config_from_latest_archive: no-op when no archive dir exists" {
  cd "$_tmpdir"
  MAX_RETRIES=10

  run load_config_from_latest_archive
  [ "$status" -eq 0 ]
}
