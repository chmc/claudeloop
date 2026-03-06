# 21. Two-Branch Release Strategy

**Date:** 2026-03-06
**Status:** Accepted

## Context

All development happened on `main` with beta and stable releases differentiated only by a flag passed to the release workflow. This meant a production hotfix couldn't be made while beta work was in progress — both shared the same commit history. Code-level separation was needed so experimental beta development and stable releases can happen independently.

## Decision

Adopt a two-branch model with rebase-only synchronization:

| Branch | Purpose | VERSION state |
|--------|---------|---------------|
| `main` | Stable/production code | Always stable (e.g. `0.16.0`) |
| `beta` | Experimental/beta development | Always beta (e.g. `0.17.0-beta.1`) |

**Key rules:**
- No merge commits. All branch synchronization uses `git rebase` for linear history.
- CI enforces branch/release-type pairing: beta releases must come from `beta`, stable from `main`.
- Claude Code must check the current branch before starting work and confirm it matches intent.

**Workflows:**
- New features: develop on `beta`, trigger beta release with `-r beta -f beta=true`
- Promote beta to stable: `git checkout main && git rebase beta`, then stable release from `main`
- Hotfix on stable: commit on `main`, stable release, then `git checkout beta && git rebase main`

**Implementation:**
- `.github/workflows/release.yml`: branch guard step validates branch vs release type
- `release.sh`: no changes needed (existing state machine handles all transitions)
- `CLAUDE.md`: branching model and branch-awareness rule
- Skills: updated to be branch-aware

## Consequences

**Positive:**
- Production hotfixes can be made independently of beta work
- Clear separation between stable and experimental code
- CI prevents accidental mismatched releases
- Linear history via rebase-only policy

**Negative:**
- Slightly more complex workflow (two branches to manage)
- Rebase-only policy requires care when syncing branches
- Developers must be branch-aware before starting work
