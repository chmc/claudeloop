#!/usr/bin/env bash
# bats file_tags=install

REPO_DIR=$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)

setup() {
  TMP_ROOT=$(mktemp -d)
  export INSTALL_DIR_OVERRIDE="$TMP_ROOT/lib/claudeloop"
  export BIN_DIR_OVERRIDE="$TMP_ROOT/bin"
}

teardown() {
  rm -rf "$TMP_ROOT"
}

run_installer() {
  run sh "$REPO_DIR/install.sh"
}

run_uninstaller() {
  run sh "$REPO_DIR/uninstall.sh"
}

# --- install.sh (local mode) ---

@test "install: exits successfully" {
  run_installer
  [ "$status" -eq 0 ]
}

@test "install: creates INSTALL_DIR" {
  run_installer
  [ -d "$INSTALL_DIR_OVERRIDE" ]
}

@test "install: copies claudeloop to INSTALL_DIR" {
  run_installer
  [ -f "$INSTALL_DIR_OVERRIDE/claudeloop" ]
}

@test "install: claudeloop in INSTALL_DIR is executable" {
  run_installer
  [ -x "$INSTALL_DIR_OVERRIDE/claudeloop" ]
}

@test "install: copies lib/*.sh to INSTALL_DIR/lib" {
  run_installer
  [ -d "$INSTALL_DIR_OVERRIDE/lib" ]
  lib_count=$(ls "$INSTALL_DIR_OVERRIDE/lib/"*.sh 2>/dev/null | wc -l | tr -d ' ')
  [ "$lib_count" -gt 0 ]
}

@test "install: creates BIN_DIR" {
  run_installer
  [ -d "$BIN_DIR_OVERRIDE" ]
}

@test "install: creates wrapper script at BIN_DIR/claudeloop" {
  run_installer
  [ -f "$BIN_DIR_OVERRIDE/claudeloop" ]
}

@test "install: wrapper script is executable" {
  run_installer
  [ -x "$BIN_DIR_OVERRIDE/claudeloop" ]
}

@test "install: wrapper script execs INSTALL_DIR/claudeloop" {
  run_installer
  grep -q "exec.*$INSTALL_DIR_OVERRIDE/claudeloop" "$BIN_DIR_OVERRIDE/claudeloop"
}

@test "install: prints installed message with version" {
  run_installer
  echo "$output" | grep -q "claudeloop v.*installed"
}

@test "install: prints INSTALL_DIR in output" {
  run_installer
  echo "$output" | grep -q "$INSTALL_DIR_OVERRIDE"
}

@test "install: warns when BIN_DIR is not in PATH" {
  run_installer
  echo "$output" | grep -q "not in your PATH"
}

@test "install: no PATH warning when BIN_DIR already in PATH" {
  export PATH="$BIN_DIR_OVERRIDE:$PATH"
  run_installer
  ! echo "$output" | grep -q "not in your PATH"
}

# --- PATH auto-configuration ---

@test "install: writes export line to profile when BIN_DIR not in PATH" {
  local tmp_home
  tmp_home=$(mktemp -d)
  export HOME="$tmp_home"
  export SHELL="/bin/zsh"
  run_installer
  grep -q "export PATH=" "$tmp_home/.zshrc"
  rm -rf "$tmp_home"
}

@test "install: writes begin marker to profile when BIN_DIR not in PATH" {
  local tmp_home
  tmp_home=$(mktemp -d)
  export HOME="$tmp_home"
  export SHELL="/bin/zsh"
  run_installer
  grep -qF "# >>> claudeloop PATH begin <<<" "$tmp_home/.zshrc"
  rm -rf "$tmp_home"
}

@test "install: writes end marker to profile when BIN_DIR not in PATH" {
  local tmp_home
  tmp_home=$(mktemp -d)
  export HOME="$tmp_home"
  export SHELL="/bin/zsh"
  run_installer
  grep -qF "# >>> claudeloop PATH end <<<" "$tmp_home/.zshrc"
  rm -rf "$tmp_home"
}

@test "install: marker block appears exactly once when run twice (idempotent)" {
  local tmp_home
  tmp_home=$(mktemp -d)
  export HOME="$tmp_home"
  export SHELL="/bin/zsh"
  run_installer
  run_installer
  count=$(grep -cF "# >>> claudeloop PATH begin <<<" "$tmp_home/.zshrc")
  [ "$count" -eq 1 ]
  rm -rf "$tmp_home"
}

@test "install: does not touch profile when BIN_DIR already in PATH" {
  local tmp_home
  tmp_home=$(mktemp -d)
  export HOME="$tmp_home"
  export SHELL="/bin/zsh"
  export PATH="$BIN_DIR_OVERRIDE:$PATH"
  run_installer
  [ ! -f "$tmp_home/.zshrc" ]
  rm -rf "$tmp_home"
}

# --- uninstall.sh ---

@test "uninstall: exits successfully" {
  run_installer
  run_uninstaller
  [ "$status" -eq 0 ]
}

@test "uninstall: removes INSTALL_DIR" {
  run_installer
  run_uninstaller
  [ ! -d "$INSTALL_DIR_OVERRIDE" ]
}

@test "uninstall: removes wrapper from BIN_DIR" {
  run_installer
  run_uninstaller
  [ ! -f "$BIN_DIR_OVERRIDE/claudeloop" ]
}

@test "uninstall: prints uninstalled message" {
  run_installer
  run_uninstaller
  echo "$output" | grep -q "uninstalled"
}

@test "uninstall: succeeds when nothing is installed" {
  run_uninstaller
  [ "$status" -eq 0 ]
}

@test "uninstall: prints uninstalled message when nothing was installed" {
  run_uninstaller
  echo "$output" | grep -q "uninstalled"
}

# --- uninstall PATH cleanup ---

@test "uninstall: removes marker block from profile after install" {
  local tmp_home
  tmp_home=$(mktemp -d)
  export HOME="$tmp_home"
  export SHELL="/bin/zsh"
  run_installer
  run_uninstaller
  ! grep -qF "# >>> claudeloop PATH begin <<<" "$tmp_home/.zshrc"
  rm -rf "$tmp_home"
}

@test "uninstall: succeeds when marker block was never written" {
  local tmp_home
  tmp_home=$(mktemp -d)
  export HOME="$tmp_home"
  export SHELL="/bin/zsh"
  run_uninstaller
  [ "$status" -eq 0 ]
  rm -rf "$tmp_home"
}

@test "uninstall: prints 'Removed PATH entry' message" {
  local tmp_home
  tmp_home=$(mktemp -d)
  export HOME="$tmp_home"
  export SHELL="/bin/zsh"
  run_installer
  run_uninstaller
  echo "$output" | grep -q "Removed PATH entry"
  rm -rf "$tmp_home"
}
