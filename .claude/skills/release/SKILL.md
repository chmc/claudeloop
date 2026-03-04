---
name: release
description: Trigger a GitHub release (beta or stable)
disable-model-invocation: true
argument-hint: "[beta|stable]"
---

# Release Workflow

Trigger a GitHub Actions release for claudeloop.

## Pre-checks

Before triggering, check and inform the user (but don't block) if:
- There are uncommitted changes: `git status --porcelain`
- There are unpushed commits: `git log origin/main..HEAD --oneline`

## Commands

**Beta release** (default if no argument or `beta`):
```sh
gh workflow run release.yml -f beta=true
```

**Stable release** (if argument is `stable`):
```sh
gh workflow run release.yml
```

After triggering, show the latest workflow run:
```sh
gh run list --workflow=release.yml --limit=1
```

## Post-release reminder

The CI auto-pushes a version bump commit. After the workflow completes, run `git pull` to pick it up.
