#!/usr/bin/env bash
# bats file_tags=release

# Test release.sh functions (beta support)
# These tests are written FIRST (TDD approach)

setup() {
  export TEST_DIR="$(mktemp -d)"

  # Extract functions from release.sh (can't source directly due to imperative code)
  # Use sed to extract function bodies between markers
  RELEASE_SH="${BATS_TEST_DIRNAME}/../release.sh"

  eval "$(sed -n '/^strip_prerelease()/,/^}/p' "$RELEASE_SH")"
  eval "$(sed -n '/^get_beta_num()/,/^}/p' "$RELEASE_SH")"
  eval "$(sed -n '/^next_version()/,/^}/p' "$RELEASE_SH")"
  eval "$(sed -n '/^compute_release_version()/,/^}/p' "$RELEASE_SH")"

  # die() is needed by compute_release_version
  die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

  # parse_release_args: test the arg parsing loop from release.sh
  parse_release_args() {
    beta_flag=false
    bump=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --beta) beta_flag=true; shift ;;
        major|minor|patch) bump="$1"; shift ;;
        *) printf 'Error: Unknown argument '\''%s'\''\n' "$1" >&2; return 1 ;;
      esac
    done
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── strip_prerelease ──────────────────────────────────────────────────────────

@test "strip_prerelease: removes beta suffix" {
  result=$(strip_prerelease "0.14.0-beta.1")
  [ "$result" = "0.14.0" ]
}

@test "strip_prerelease: no-op on stable version" {
  result=$(strip_prerelease "0.14.0")
  [ "$result" = "0.14.0" ]
}

@test "strip_prerelease: handles higher beta numbers" {
  result=$(strip_prerelease "1.2.3-beta.15")
  [ "$result" = "1.2.3" ]
}

# ── get_beta_num ──────────────────────────────────────────────────────────────

@test "get_beta_num: extracts beta number" {
  result=$(get_beta_num "0.14.0-beta.1")
  [ "$result" = "1" ]
}

@test "get_beta_num: extracts higher beta number" {
  result=$(get_beta_num "0.14.0-beta.12")
  [ "$result" = "12" ]
}

@test "get_beta_num: returns empty for stable version" {
  result=$(get_beta_num "0.14.0")
  [ -z "$result" ]
}

# ── next_version (existing behavior preserved) ───────────────────────────────

@test "next_version: patch bump" {
  result=$(next_version "0.13.1" "patch")
  [ "$result" = "0.13.2" ]
}

@test "next_version: minor bump" {
  result=$(next_version "0.13.1" "minor")
  [ "$result" = "0.14.0" ]
}

@test "next_version: major bump" {
  result=$(next_version "0.13.1" "major")
  [ "$result" = "1.0.0" ]
}

@test "next_version: strips prerelease before bumping" {
  result=$(next_version "0.14.0-beta.1" "patch")
  [ "$result" = "0.14.1" ]
}

# ── compute_release_version (state machine) ──────────────────────────────────

@test "compute_release_version: stable + patch = stable bump (existing behavior)" {
  result=$(compute_release_version "0.13.1" "patch" "false")
  [ "$result" = "0.13.2" ]
}

@test "compute_release_version: stable + minor = stable bump" {
  result=$(compute_release_version "0.13.1" "minor" "false")
  [ "$result" = "0.14.0" ]
}

@test "compute_release_version: stable + patch + --beta = beta.1" {
  result=$(compute_release_version "0.13.1" "patch" "true")
  [ "$result" = "0.13.2-beta.1" ]
}

@test "compute_release_version: stable + minor + --beta = beta.1" {
  result=$(compute_release_version "0.13.1" "minor" "true")
  [ "$result" = "0.14.0-beta.1" ]
}

@test "compute_release_version: beta + --beta = increment beta counter" {
  result=$(compute_release_version "0.14.0-beta.1" "" "true")
  [ "$result" = "0.14.0-beta.2" ]
}

@test "compute_release_version: beta + no flag = promote to stable" {
  result=$(compute_release_version "0.14.0-beta.2" "" "false")
  [ "$result" = "0.14.0" ]
}

@test "compute_release_version: beta + major + --beta = new beta series" {
  result=$(compute_release_version "0.14.0-beta.1" "major" "true")
  [ "$result" = "1.0.0-beta.1" ]
}

@test "compute_release_version: beta + minor + --beta = new beta series" {
  result=$(compute_release_version "0.14.0-beta.1" "minor" "true")
  [ "$result" = "0.15.0-beta.1" ]
}

# ── parse_release_args ────────────────────────────────────────────────────────

@test "parse_release_args: no args" {
  parse_release_args
  [ "$beta_flag" = "false" ]
  [ -z "$bump" ]
}

@test "parse_release_args: --beta only" {
  parse_release_args --beta
  [ "$beta_flag" = "true" ]
  [ -z "$bump" ]
}

@test "parse_release_args: minor only" {
  parse_release_args minor
  [ "$beta_flag" = "false" ]
  [ "$bump" = "minor" ]
}

@test "parse_release_args: minor --beta" {
  parse_release_args minor --beta
  [ "$beta_flag" = "true" ]
  [ "$bump" = "minor" ]
}

@test "parse_release_args: --beta patch" {
  parse_release_args --beta patch
  [ "$beta_flag" = "true" ]
  [ "$bump" = "patch" ]
}

@test "parse_release_args: invalid arg fails" {
  run parse_release_args --invalid
  [ "$status" -ne 0 ]
}

@test "parse_release_args: unknown bump type fails" {
  run parse_release_args hotfix
  [ "$status" -ne 0 ]
}
