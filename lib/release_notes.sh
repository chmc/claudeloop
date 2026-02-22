#!/bin/sh
# Release notes formatter library

# format_release_notes: format commit log subjects into grouped markdown changelog
# Args: $1=log_subjects (newline-separated), $2=prev_tag, $3=next_tag, $4=repo_url
# Output: markdown to stdout
format_release_notes() {
  log="$1"; prev_tag="${2:-}"; next_tag="${3:-}"; repo_url="${4:-}"

  feats=$(printf '%s\n' "$log" | grep '^feat' || true)
  fixes=$(printf '%s\n' "$log" | grep '^fix'  || true)
  other=$(printf '%s\n' "$log" | grep -vE '^feat|^fix|^chore: release' | grep -v '^$' || true)

  if [ -n "$feats" ]; then
    printf '## Features\n\n'
    printf '%s\n' "$feats" | sed 's/^/- /'
    printf '\n'
  fi
  if [ -n "$fixes" ]; then
    printf '## Bug Fixes\n\n'
    printf '%s\n' "$fixes" | sed 's/^/- /'
    printf '\n'
  fi
  if [ -n "$other" ]; then
    printf '## Other Changes\n\n'
    printf '%s\n' "$other" | sed 's/^/- /'
    printf '\n'
  fi

  if [ -n "$prev_tag" ] && [ -n "$repo_url" ]; then
    printf '**Full Changelog**: %s/compare/%s...%s\n' "$repo_url" "$prev_tag" "$next_tag"
  fi
}
