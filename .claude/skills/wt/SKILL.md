---
name: wt
description: Manage git worktrees for parallel Claude Code sessions
disable-model-invocation: false
argument-hint: "[create <name>|rm <name>|list]"
---

# Worktree Skill

Manage git worktrees for parallel Claude Code sessions. Each worktree gets a sibling directory `../claudeloop-wt-<name>` and a `wt/<name>` branch.

## Execution style

Run validation checks upfront, stop on hard blocks immediately. Only pause for user input at documented decision points (**warn and confirm** gates). On the happy path, run straight through to completion.

## VS Code workspace

All operations maintain a multi-root workspace file so one VS Code window shows the main repo and all worktrees.

- `REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"`
- `WORKSPACE_FILE="../${REPO_NAME}.code-workspace"`

Format:
```json
{
  "folders": [
    { "path": "<repo-name>", "name": "<repo-name> (main)" },
    { "path": "<repo-name>-wt-<name>", "name": "wt/<name>" }
  ],
  "settings": {}
}
```

Rules:
- Paths are relative directory names (workspace file is in the parent directory).
- Only touch the `folders` array — preserve any user-added `settings`, `extensions`, `launch`, etc.
- VS Code watches the file and auto-reloads on change.

### Workspace helpers

Check `jq` availability once at the start of any operation that touches the workspace file:
```sh
if ! command -v jq >/dev/null 2>&1; then
  echo "Warning: jq not found — skipping workspace file update"
  # Set flag to skip all workspace file operations; continue with git operations
  JQ_AVAILABLE=false
fi
```

Create workspace file (when it doesn't exist):
```sh
jq -n --arg repo "$REPO_NAME" \
  '{folders: [{path: $repo, name: ($repo + " (main)")}], settings: {}}' \
  > "$WORKSPACE_FILE"
```

Add a worktree entry:
```sh
jq --arg path "${REPO_NAME}-wt-${NAME}" --arg name "wt/${NAME}" \
  '.folders += [{path: $path, name: $name}]' \
  "$WORKSPACE_FILE" > "$WORKSPACE_FILE.tmp" && mv "$WORKSPACE_FILE.tmp" "$WORKSPACE_FILE"
```

Remove a worktree entry:
```sh
jq --arg path "${REPO_NAME}-wt-${NAME}" \
  '.folders |= map(select(.path != $path))' \
  "$WORKSPACE_FILE" > "$WORKSPACE_FILE.tmp" && mv "$WORKSPACE_FILE.tmp" "$WORKSPACE_FILE"
```

Prune stale entries (remove folders whose directories don't exist):
```sh
jq -r '.folders[].path' "$WORKSPACE_FILE" | while read -r dir; do
  if [ ! -d "../$dir" ]; then
    jq --arg path "$dir" '.folders |= map(select(.path != $path))' \
      "$WORKSPACE_FILE" > "$WORKSPACE_FILE.tmp" && mv "$WORKSPACE_FILE.tmp" "$WORKSPACE_FILE"
  fi
done
```

## Operations

### `create` — Create a new worktree

Creates `../claudeloop-wt-<name>` on a new `wt/<name>` branch from the chosen base. Adds the worktree to the VS Code workspace.

**Steps:**

1. **Hard block** if `<name>` not provided. Print usage.
2. Set `WT_DIR="../claudeloop-wt-<name>"`, `WT_BRANCH="wt/<name>"`.
3. **Hard block** if `$WT_DIR` already exists.
4. `git fetch origin`
5. `git worktree prune`. If `jq` available and `$WORKSPACE_FILE` exists, run the **prune stale entries** helper.
6. **Hard block** if branch exists: `git show-ref --verify --quiet refs/heads/wt/<name>` or `git show-ref --verify --quiet refs/remotes/origin/wt/<name>`. Check exit codes.
7. **Ask** base branch: main, beta, or other. Default: current branch.
8. If `git show-ref --verify --quiet "refs/remotes/origin/<base>"` succeeds, use `origin/<base>` as the start point. Otherwise use the local ref `<base>`. Run `git worktree add -b "wt/<name>" "$WT_DIR" "<start-point>"`.
9. If `jq` available: if `$WORKSPACE_FILE` doesn't exist, run the **create workspace file** helper. Then run the **add entry** helper.
10. Print success:
    ```
    Worktree created:
      Directory: ../claudeloop-wt-<name>
      Branch:    wt/<name>
      Base:      origin/<base>

    VS Code workspace: $WORKSPACE_FILE

    To start working:
      cd ../claudeloop-wt-<name>
    ```

### `list` — List worktrees

Runs `git worktree list` and annotates the output. Reports VS Code workspace status.

**Steps:**

1. `git worktree list`
2. Annotate `wt/*` branches as managed by this skill.
3. Note any other worktrees as "not managed by /wt".
4. Check for orphan branches: list local branches matching `wt/*` (`git branch --list 'wt/*'`) and compare against active worktrees from step 1. Report any `wt/*` branches without a corresponding worktree as "orphan branches" and suggest `/wt rm <name>` to clean up.
5. If `jq` available and `$WORKSPACE_FILE` exists:
   - Note which worktrees are in the workspace and which aren't.
   - Detect stale entries: run `jq -r '.folders[].path' "$WORKSPACE_FILE"` and check each with `[ -d "../$dir" ]`. Report any stale entries and offer to run the **prune stale entries** helper.
6. If `$WORKSPACE_FILE` doesn't exist, note: "No VS Code workspace file. Run `/wt create` to generate one."

### `rm` — Remove a worktree

Removes `../claudeloop-wt-<name>`, with options to create a PR or just clean up. Removes the worktree from the VS Code workspace.

**Steps:**

1. **Hard block** if `<name>` not provided. Show `git worktree list` and print usage.
2. Set `WT_DIR="../claudeloop-wt-<name>"`, `WT_BRANCH="wt/<name>"`.
3. If `$WT_DIR` does not exist, enter **orphan cleanup mode**:
   - Print: "Worktree directory not found — cleaning up orphan branch and workspace entry."
   - `git worktree prune`
   - If `jq` available and `$WORKSPACE_FILE` exists, run the **prune stale entries** helper.
   - **Ask** cleanup preference (simplified — no PR option since directory is gone):
     - **Just remove** (default): `git branch -D "$WT_BRANCH"`, then `git push origin --delete "$WT_BRANCH"` (warn on failure, non-fatal).
     - **Keep branch**: only prune workspace entry, keep branch for later use.
   - Print summary and **return** (skip steps 4-7).
4. Resolve absolute path: `WT_DIR_ABS="$(cd "$WT_DIR" && pwd -P)"`. **Hard block** if `$(git rev-parse --show-toplevel)` equals `$WT_DIR_ABS` — tell user to cd to main repo first.
5. Check for uncommitted changes: `git -C "$WT_DIR" status --porcelain`. If non-empty, **warn and confirm** — list the changes. User must acknowledge before proceeding with `--force`.
6. Check for unpushed commits: if `git show-ref --verify --quiet "refs/remotes/origin/$WT_BRANCH"`, run `git log "origin/$WT_BRANCH..$WT_BRANCH" --oneline`. Otherwise, all commits are unpushed — warn with `git log "$WT_BRANCH" --oneline --not --remotes`.
7. **Ask** cleanup preference:
   - **PR then remove:**
     1. `git -C "$WT_DIR" push -u origin "$WT_BRANCH"`
     2. **Warn and confirm** PR base branch (suggest the base used at creation if known).
     3. `gh pr create --head "$WT_BRANCH" --base "<base>"` — ask for title/description or auto-generate.
     4. `git worktree remove "$WT_DIR"`
     5. `git branch -D "$WT_BRANCH"`
     6. If `jq` available and `$WORKSPACE_FILE` exists, run the **remove entry** helper (only after step 4 succeeded).
     7. **On `gh pr create` failure:** warn but proceed with steps 4-6 (commits are safe on remote).
   - **Just remove:**
     1. `git worktree remove "$WT_DIR"` (`--force` if dirty, after user confirmed at step 5)
     2. `git branch -D "$WT_BRANCH"`
     3. `git push origin --delete "$WT_BRANCH"` — warn on failure, non-fatal.
     4. If `jq` available and `$WORKSPACE_FILE` exists, run the **remove entry** helper (only after step 1 succeeded).
   - **Keep branch:**
     1. `git worktree remove "$WT_DIR"` — removes directory, keeps branch and remote for later use.
     2. If `jq` available and `$WORKSPACE_FILE` exists, run the **remove entry** helper (only after step 1 succeeded).

## Edge cases

- Running `/wt rm` from inside the worktree: caught at step 4, hard block with instructions.
- Name with special characters: let git's own validation handle it — don't pre-filter.
- Branch exists on remote only: caught after `git fetch origin` in create step 6.
- Dirty worktree on rm: explicit warning at step 5, user confirms before `--force`.
- Worktree directory exists but isn't a git worktree: `git worktree remove` will fail with a clear error.
- `jq` not installed: warn, skip workspace file update, all git operations still work.
- Workspace file manually edited by user: only modify `folders` array, preserve everything else.
- Orphan state (directory deleted outside `/wt rm`): `rm` enters orphan cleanup mode at step 3 — prunes git worktree tracking, cleans workspace entry, offers branch deletion.
- Stale workspace entries (manual `rm -rf` or interrupted `/wt rm`): caught during `list`, `create` prune step, and `rm` orphan cleanup.
- Orphan branches without worktree: detected by `list` step 4, cleaned by `/wt rm`.
- Last worktree removed: leave workspace file intact (still valid, avoids closing VS Code window).

## Error handling

- On any git command failure not explicitly handled above, report the error and stop.
- Never delete a branch without removing the worktree first (unless in orphan cleanup mode where the directory is already gone).
- If `gh pr create` fails after push, proceed with worktree removal (commits are safe on remote).
- Workspace file operations are non-fatal — git operations take priority.
