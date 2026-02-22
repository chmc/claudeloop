#!/usr/bin/env bats

setup() {
  . "$BATS_TEST_DIRNAME/../lib/release_notes.sh"
}

@test "feat commits appear under Features" {
  run format_release_notes "feat: add --force flag" "" "v1.0.0" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Features"* ]]
  [[ "$output" == *"- feat: add --force flag"* ]]
}

@test "fix commits appear under Bug Fixes" {
  run format_release_notes "fix: unblock resume after failure" "" "v1.0.0" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Bug Fixes"* ]]
  [[ "$output" == *"- fix: unblock resume after failure"* ]]
}

@test "non-feat/fix commits appear under Other Changes" {
  run format_release_notes "docs: update README" "" "v1.0.0" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Other Changes"* ]]
  [[ "$output" == *"- docs: update README"* ]]
}

@test "chore release commits are excluded from output" {
  run format_release_notes "chore: release v0.7.0" "" "v1.0.0" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"chore: release"* ]]
}

@test "Full Changelog link is appended when prev_tag and repo_url are provided" {
  run format_release_notes "feat: something" "v0.6.0" "v0.7.0" "https://github.com/chmc/claudeloop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Full Changelog**: https://github.com/chmc/claudeloop/compare/v0.6.0...v0.7.0"* ]]
}

@test "Full Changelog link is omitted when prev_tag is empty" {
  run format_release_notes "feat: something" "" "v0.1.0" "https://github.com/chmc/claudeloop"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Full Changelog"* ]]
}

@test "sections with no commits are omitted entirely" {
  run format_release_notes "feat: new feature" "" "v1.0.0" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"## Bug Fixes"* ]]
  [[ "$output" != *"## Other Changes"* ]]
}

@test "multiple commits in a section all appear as list items" {
  log="feat: add feature one
feat: add feature two
feat: add feature three"
  run format_release_notes "$log" "" "v1.0.0" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"- feat: add feature one"* ]]
  [[ "$output" == *"- feat: add feature two"* ]]
  [[ "$output" == *"- feat: add feature three"* ]]
}

@test "download badge is included when repo_url and next_tag are provided" {
  run format_release_notes "feat: something" "v0.6.0" "v0.7.0" "https://github.com/chmc/claudeloop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"![Downloads](https://img.shields.io/github/downloads/chmc/claudeloop/v0.7.0/total)"* ]]
}

@test "download badge is omitted when repo_url is empty" {
  run format_release_notes "feat: something" "v0.6.0" "v0.7.0" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"img.shields.io"* ]]
}

@test "download badge is omitted when next_tag is empty" {
  run format_release_notes "feat: something" "v0.6.0" "" "https://github.com/chmc/claudeloop"
  [ "$status" -eq 0 ]
  [[ "$output" != *"img.shields.io"* ]]
}

@test "download badge URL contains correct owner/repo and tag" {
  run format_release_notes "feat: something" "" "v1.2.3" "https://github.com/myorg/myrepo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"img.shields.io/github/downloads/myorg/myrepo/v1.2.3/total"* ]]
}
