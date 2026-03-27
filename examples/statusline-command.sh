#!/bin/sh
# claudeloop statusline script for Claude Code
# Shows: model | context usage | git branch
#
# Worktree-aware: uses .worktree.branch when available (--worktree sessions),
# falls back to git from .worktree.path (hook-based worktrees), then .cwd.
#
# Install: cp examples/statusline-command.sh ~/.claude/statusline-command.sh
# Config:  add to ~/.claude/settings.json:
#   { "statusLine": { "type": "command", "command": "sh ~/.claude/statusline-command.sh" } }

input=$(cat)

# Single jq call extracts all fields
eval "$(printf '%s' "$input" | jq -r '
  @sh "model=\(.model.display_name // "unknown")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "cwd=\(.cwd // "")",
  @sh "wt_branch=\(.worktree.branch // "")",
  @sh "wt_path=\(.worktree.path // "")"
')"

# Branch detection: worktree.branch > git from worktree.path > git from cwd
branch="$wt_branch"
if [ -z "$branch" ]; then
  git_dir="${wt_path:-$cwd}"
  branch=$(git -C "$git_dir" --no-optional-locks branch --show-current 2>/dev/null)
fi

# Show active wt/* worktrees from /wt skill (only in non-worktree sessions)
if [ -z "$wt_branch" ] && [ -n "$cwd" ]; then
  wt_names=$(git -C "$cwd" --no-optional-locks worktree list 2>/dev/null \
    | sed -n 's/.*\[wt\/\(.*\)\]/wt\/\1/p' \
    | paste -sd ',' - \
    | sed 's/,/, /g')
  [ -n "$wt_names" ] && branch="${branch:+$branch }($wt_names)"
fi

if [ -n "$used" ]; then
  ctx="ctx: $(printf '%.0f' "$used")%"
else
  ctx="ctx: –"
fi

parts="$model | $ctx"
[ -n "$branch" ] && parts="$parts | $branch"
echo "$parts"
