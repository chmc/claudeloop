---
paths:
  - ".claude/hooks/**"
  - ".claude/settings.json"
  - "docs/WORKFLOW.md"
---

# Hook and Workflow Conventions

## Hook contract

- **stdin**: JSON from Claude Code (tool name + inputs)
- **stdout**: message shown to user
- **exit 0**: allow the tool use
- **exit 2**: block the tool use (deny)
- Never use `set -x` — debug output goes to the user as hook response

## Reading hook input

```sh
input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
```

See `run-edited-tests.sh` (16 lines) as the minimal working example.

## State files

Located in `.claude/workflow-state/` (gitignored). Naming: one file per gate condition, presence = condition met.

- Touch to set: `touch .claude/workflow-state/my-gate`
- Remove to reset: `rm -f .claude/workflow-state/my-gate`
- Read in hooks via: `[ -f "$CLAUDE_PROJECT_DIR/.claude/workflow-state/my-gate" ]`

## Hook ordering

Hooks in `settings.json` fire in **array order**. `branch-awareness.sh` must remain first in PreToolUse for Edit/Write — it gates all subsequent hooks.

## Keeping docs in sync

Any change to hook logic that affects gate behavior must update `docs/WORKFLOW.md`:
- Gate table (add/remove/modify gate row)
- State files table (if new state file added)
- Modifying the Workflow table (if hook file mapping changes)
