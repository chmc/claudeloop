---
name: rebase
description: Safe branch rebasing (sync beta from main, promote beta to main)
disable-model-invocation: true
argument-hint: "[sync|promote]"
---

# Rebase Skill

Safe rebase operations for the two-branch model. Always restores the original branch on exit.

## Operations

### `sync` — Update beta with latest main

Rebases `beta` on top of `origin/main`, then force-pushes.

**Steps:**

1. Record original branch: `ORIGINAL_BRANCH=$(git branch --show-current)`
2. `git fetch origin`
3. **Hard block** if worktree is dirty (`git status --porcelain` is non-empty). Tell user to commit or stash first.
4. Check if already up-to-date: `git merge-base --is-ancestor origin/main origin/beta`. If yes, inform user and stop.
5. `git checkout beta`
6. Check for unpushed local commits: `git log origin/beta..beta --oneline`. If any exist, **warn and confirm** — these commits will be lost by the reset in step 7.
7. `git reset --hard origin/beta` (sync local to remote state)
8. Show incoming commits: `git log origin/beta..origin/main --oneline`
9. **Warn**: "The VERSION line will likely conflict (stable vs beta version). If so, keep the beta version and continue the rebase."
10. **Confirm** before proceeding.
11. `git rebase origin/main`
12. **On conflict**: `git rebase --abort`, inform user about the conflict, restore original branch (`git checkout "$ORIGINAL_BRANCH"`), and stop.
13. On success: `git push --force-with-lease origin beta`
14. **On push failure**: "Remote changed since fetch. Re-run `/rebase sync`." Restore original branch and stop.
15. Restore: `git checkout "$ORIGINAL_BRANCH"` (skip if user was already on beta)

### `promote` — Fast-forward main to beta

Fast-forwards `main` to match `origin/beta`, then pushes.

**Steps:**

1. Record original branch: `ORIGINAL_BRANCH=$(git branch --show-current)`
2. `git fetch origin`
3. **Hard block** if worktree is dirty (`git status --porcelain` is non-empty). Tell user to commit or stash first.
4. **Safety check**: `git merge-base --is-ancestor origin/main origin/beta`. If false, main has diverged — tell user to run `/rebase sync` first, restore original branch, and stop.
5. Check if already up-to-date: `git merge-base --is-ancestor origin/beta origin/main`. If yes, inform user and stop.
6. `git checkout main`
7. Check for unpushed local commits: `git log origin/main..main --oneline`. If any exist, **warn and confirm** — these commits will be lost by the reset in step 8.
8. `git reset --hard origin/main` (sync local to remote state)
9. Show commits being promoted: `git log origin/main..origin/beta --oneline`
10. **Confirm** before proceeding.
11. `git merge --ff-only origin/beta`
12. `git push origin main` (plain push — no force needed for fast-forward; detects races)
13. **On push failure**: "Someone pushed to main between fetch and push. Re-run `/rebase promote`." Restore original branch and stop.
14. Restore: `git checkout "$ORIGINAL_BRANCH"` (skip if user was already on main)
15. **Post-promote reminder**: "Consider running `/release stable` if this is a release-worthy promotion."

## Error handling

- **Always** restore the original branch on exit, whether success or failure.
- Never leave the user on a different branch than they started on (unless they started on the target branch).
- On any git command failure not explicitly handled above, abort the operation, restore the original branch, and report the error.
