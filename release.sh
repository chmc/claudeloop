#!/bin/sh
# release.sh — detect conventional commit bump, update VERSION, commit, tag
# Usage: ./release.sh [major|minor|patch]   (optional override)
set -eu

# ── helpers ──────────────────────────────────────────────────────────────────

die() { printf 'Error: %s\n' "$1" >&2; exit 1; }

# Compute next semver given current and bump type
next_version() {
  current="$1"; bump="$2"
  major=$(printf '%s' "$current" | cut -d. -f1)
  minor=$(printf '%s' "$current" | cut -d. -f2)
  patch=$(printf '%s' "$current" | cut -d. -f3)
  case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

# ── resolve current version from claudeloop ───────────────────────────────────

current=$(grep '^VERSION=' ./claudeloop | head -1 | sed 's/VERSION="\(.*\)"/\1/')
[ -z "$current" ] && die "Could not read VERSION from ./claudeloop"

# ── determine commit range ────────────────────────────────────────────────────

last_tag=$(git tag -l 'v*' | sort -V | tail -1)
if [ -z "$last_tag" ]; then
  # First release — use all commits
  log=$(git log --format='%s')
else
  log=$(git log "${last_tag}..HEAD" --format='%s')
fi

# ── guard: nothing to release ─────────────────────────────────────────────────

if [ -z "$log" ]; then
  printf 'No commits since %s — nothing to release.\n' "${last_tag:-beginning}"
  exit 0
fi

# ── detect bump type ─────────────────────────────────────────────────────────

if [ -n "${1:-}" ]; then
  # Explicit override
  case "$1" in
    major|minor|patch) bump="$1" ;;
    *) die "Unknown bump type '$1'. Use major, minor, or patch." ;;
  esac
else
  bump="patch"
  # Scan subject lines for conventional commit type
  printf '%s\n' "$log" | while IFS= read -r subject; do
    # Breaking change (any type with !)
    if printf '%s' "$subject" | grep -qE '^[a-z]+!:'; then
      printf 'major\n'; exit 0
    fi
    # Feature
    if printf '%s' "$subject" | grep -qE '^feat:'; then
      printf 'minor\n'
    fi
  done | {
    result=""
    while IFS= read -r line; do
      case "$line" in
        major) result="major"; break ;;
        minor) result="minor" ;;
      esac
    done
    printf '%s\n' "${result:-patch}"
  } | {
    read -r bump
    printf '%s\n' "$bump"
  }

  # Re-derive bump via a simpler two-pass scan (avoids subshell variable leakage)
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

# For first release, always start at 0.1.0 regardless of bump
if [ -z "$last_tag" ]; then
  next="0.1.0"
else
  next=$(next_version "$current" "$bump")
fi

printf 'Detected bump: %s  (%s → %s)\n' "$bump" "$current" "$next"

# ── update VERSION in claudeloop ──────────────────────────────────────────────

tmp=$(mktemp)
sed "s|^VERSION=.*|VERSION=\"${next}\"|" ./claudeloop > "$tmp" && mv "$tmp" ./claudeloop

# ── commit and tag ────────────────────────────────────────────────────────────

git add claudeloop
git commit -m "chore: release v${next}"
git tag -a "v${next}" -m "chore: release v${next}"

printf 'Released v%s. In CI: push and gh release create follow automatically.\n' "$next"
