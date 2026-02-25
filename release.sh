#!/bin/sh
# release.sh — detect conventional commit bump, update VERSION, commit, tag
# Usage: ./release.sh [major|minor|patch] [--beta]
set -eu

# ── libraries ─────────────────────────────────────────────────────────────────

. "$(dirname "$0")/lib/release_notes.sh"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

strip_prerelease() { printf '%s' "$1" | sed 's/-.*//'; }
get_beta_num() { printf '%s' "$1" | sed -n 's/.*-beta\.\([0-9]*\)/\1/p'; }

# Compute next semver given current and bump type (strips prerelease first)
next_version() {
  base=$(strip_prerelease "$1"); bump="$2"
  major=$(printf '%s' "$base" | cut -d. -f1)
  minor=$(printf '%s' "$base" | cut -d. -f2)
  patch=$(printf '%s' "$base" | cut -d. -f3)
  case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

# Core state machine for computing the next release version
# Args: $1=current_version, $2=bump (may be empty), $3=beta_flag (true/false)
compute_release_version() {
  current="$1"; bump="${2:-}"; beta_flag="${3:-false}"
  current_beta_num=$(get_beta_num "$current")
  base=$(strip_prerelease "$current")

  if [ -n "$current_beta_num" ]; then
    # Currently on a beta
    if [ "$beta_flag" = "true" ]; then
      if [ -n "$bump" ]; then
        # Explicit bump with --beta while on beta: start new beta series
        new_base=$(next_version "$base" "$bump")
        printf '%s-beta.1\n' "$new_base"
      else
        # No bump: increment beta counter
        new_num=$((current_beta_num + 1))
        printf '%s-beta.%s\n' "$base" "$new_num"
      fi
    else
      # No --beta flag: promote to stable
      printf '%s\n' "$base"
    fi
  else
    # Currently on stable
    if [ -z "$bump" ]; then
      die "bump type required for stable release"
    fi
    new_base=$(next_version "$current" "$bump")
    if [ "$beta_flag" = "true" ]; then
      printf '%s-beta.1\n' "$new_base"
    else
      printf '%s\n' "$new_base"
    fi
  fi
}

# ── arg parsing ───────────────────────────────────────────────────────────────

beta_flag=false
bump=""
while [ $# -gt 0 ]; do
  case "$1" in
    --beta) beta_flag=true; shift ;;
    major|minor|patch) bump="$1"; shift ;;
    *) die "Unknown argument '$1'" ;;
  esac
done

# ── resolve current version from claudeloop ───────────────────────────────────

current=$(grep '^VERSION=' ./claudeloop | head -1 | sed 's/VERSION="\(.*\)"/\1/')
[ -z "$current" ] && die "Could not read VERSION from ./claudeloop"

current_beta_num=$(get_beta_num "$current")

# ── determine tag references ─────────────────────────────────────────────────

last_stable_tag=$(git tag -l 'v*' | grep -v '-' | sort -V | tail -1)
last_tag=$(git tag -l 'v*' | sort -V | tail -1)

# For commit range, use last_stable_tag when transitioning from beta
# (so release notes cover the full beta series)
if [ -n "$current_beta_num" ]; then
  range_tag="$last_stable_tag"
else
  range_tag="$last_tag"
fi

if [ -z "$range_tag" ]; then
  # First release — use all commits
  log=$(git log --format='%s')
else
  log=$(git log "${range_tag}..HEAD" --format='%s')
fi

# ── guard: nothing to release ─────────────────────────────────────────────────

if [ -z "$log" ]; then
  printf 'No commits since %s — nothing to release.\n' "${range_tag:-beginning}"
  exit 0
fi

# ── detect bump type (only when not transitioning from beta) ──────────────────

skip_bump_detection=false
if [ -n "$current_beta_num" ]; then
  # beta→stable or beta→beta+1: skip auto-detection
  skip_bump_detection=true
fi

if [ -n "$bump" ]; then
  # Explicit override provided — use it
  :
elif [ "$skip_bump_detection" = "true" ]; then
  # Transitioning from beta — bump is not needed
  :
else
  # Auto-detect bump from conventional commits
  found_major=0; found_minor=0
  while IFS= read -r subject; do
    if printf '%s' "$subject" | grep -qE '^[a-z]+!:'; then found_major=1; fi
    if printf '%s' "$subject" | grep -qE '^feat:';     then found_minor=1; fi
  done << EOF
$log
EOF
  if [ "$found_major" -eq 1 ]; then
    bump="major"
  elif [ "$found_minor" -eq 1 ]; then
    bump="minor"
  else
    bump="patch"
  fi
fi

# ── compute next version ──────────────────────────────────────────────────────

# For first release (no tags at all), always start at 0.1.0
if [ -z "$last_tag" ]; then
  if [ "$beta_flag" = "true" ]; then
    next="0.1.0-beta.1"
  else
    next="0.1.0"
  fi
else
  next=$(compute_release_version "$current" "$bump" "$beta_flag")
fi

printf 'Detected bump: %s  (%s → %s)\n' "${bump:-none}" "$current" "$next"

# ── update VERSION in claudeloop ──────────────────────────────────────────────

tmp=$(mktemp)
sed "s|^VERSION=.*|VERSION=\"${next}\"|" ./claudeloop > "$tmp" && mv "$tmp" ./claudeloop

# ── commit and tag ────────────────────────────────────────────────────────────

git add claudeloop
git commit -m "chore: release v${next}"
git tag -a "v${next}" -m "chore: release v${next}"

repo_url=$(git remote get-url origin | sed 's|\.git$||' | sed 's|git@github.com:|https://github.com/|')
# For beta→stable, use last_stable_tag for full changelog coverage
notes_from_tag="${range_tag:-}"
format_release_notes "$log" "$notes_from_tag" "v${next}" "$repo_url" > release_notes.md
printf 'Release notes written to release_notes.md\n'

printf 'Released v%s. In CI: push and gh release create follow automatically.\n' "$next"
