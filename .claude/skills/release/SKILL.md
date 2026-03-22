---
name: release
description: Trigger a GitHub release (beta or stable)
argument-hint: "[beta|stable]"
---

# Release Workflow

Trigger a GitHub Actions release for claudeloop.

## Guardrails

- NEVER run `./release.sh` locally or use `gh release create` manually. The workflow builds the release tarball and attaches it as an asset — local execution skips this, producing incomplete releases.
- `release.sh` is a CI-internal script, not a user-facing command.

## Pre-checks

Before triggering, verify:
1. **Correct branch for release type:**
   - Beta release: must be on `beta` branch
   - Stable release: must be on `main` branch
   - If on the wrong branch, warn and offer to switch.
2. Check and inform the user (but don't block) if:
   - There are uncommitted changes: `git status --porcelain`
   - There are unpushed commits: `git log origin/$(git branch --show-current)..HEAD --oneline`

## Commands

**Beta release** (default if no argument or `beta`):
```sh
# Must be on the beta branch
gh workflow run release.yml -r beta -f beta=true
```

**Stable release** (if argument is `stable`):
```sh
# Must be on the main branch
gh workflow run release.yml -r main
```

After triggering, show the latest workflow run:
```sh
gh run list --workflow=release.yml --limit=1
```

## Post-release

- The CI auto-pushes a version bump commit. After the workflow completes, run `git pull` to pick it up.
- After a **stable** release, also run `/rebase sync` to update beta with the new version commit.
