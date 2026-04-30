# Enforced Workflow System

This project uses Claude Code hooks to enforce a development workflow. These hooks create hard gates that block progress until workflow steps are completed.

## Workflow Overview

```
Branch confirm → Plan (8 sections) → Tasks → TDD → Updates → Simplify → Review → Verify
```

## Gates

| # | Gate | Trigger | Purpose |
|---|------|---------|---------|
| 1 | Branch awareness | First Edit/Write | Confirm branch before work |
| 2 | Planning checklist | ExitPlanMode | 8 sections required |
| 3 | Plan-to-tasks | Edit/Write (post-plan) | Tasks must exist |
| 4 | TDD | Edit (impl files) | Test file edited first |
| 5 | Documentation | TaskUpdate (complete) | Update if plan indicated |
| 6 | Workflow | TaskUpdate (complete) | Update skills/hooks/CLAUDE.md |
| 7 | Architecture | TaskUpdate (complete) | Create ADR if indicated |
| 8 | Install/README | TaskUpdate (complete) | Update if plan indicated |
| 9 | Simplify | TaskUpdate (complete) | Run /simplify for impl tasks |
| 10 | Code review | TaskUpdate (complete) | Review before task closes |
| 11 | Visual verification | TaskUpdate (complete) | Verify or justify skip |

## Planning Checklist (Gate 2)

Every plan must address these 8 sections (use "N/A - reason" if not applicable):

1. **Architecture Impact** - How does this affect system architecture?
2. **ADR** - Does this need an Architectural Decision Record?
3. **Workflow / State Machines** - Any workflow or state changes?
4. **Tests (unit, e2e, integration)** - What tests are needed?
5. **Documentation** - What docs need updating?
6. **Install / Uninstall** - Any installation changes?
7. **Release** - Release considerations?
8. **README** - README updates needed?

## TDD File Patterns (Gate 4)

| Implementation | Test |
|----------------|------|
| `lib/*.sh` | `tests/test_*.sh` |
| `src/*.ts` | `src/*.test.ts` |
| `src/*.js` | `src/*.test.js` |
| `src/*.py` | `src/*_test.py` |

## State Files

Located in `.claude/workflow-state/` (gitignored):

| File | Purpose | Set by |
|------|---------|--------|
| `branch-confirmed` | Branch acknowledged | User confirmation |
| `plan-exited` | ExitPlanMode called | Gate 2 |
| `plan-requirements.json` | Which sections need updates | Gate 2 |
| `tasks-created` | Tasks exist from plan | `tasks-created.sh` (PostToolUse on TaskCreate) |
| `edit-order` | Tracks file edit sequence | Gates 1, 4 |
| `simplify-complete` | /simplify was run | /simplify skill |
| `review-complete` | Code review done | Code review |
| `visual-verified` | Visual verification done | /verify skill |
| `visual-skip-reason` | Skip justification | Manual |

## Plan File Handling

### plansDirectory Setting

The `plansDirectory` setting in `.claude/settings.json` configures Claude Code to write plans directly to `.claude/plans/` (project-local) instead of `~/.claude/plans/` (global). This ensures plans are where the enforcement hooks expect them.

### Plan File Exemption

Plan files (`*/plans/*.md`) are exempt from the task requirement (Gate 3). You can edit plans at any time without creating tasks first.

## Modifying the Workflow

| To change... | Edit... |
|--------------|---------|
| Planning checklist sections | `.claude/hooks/planning-checklist.sh` |
| TDD file patterns | `.claude/hooks/tdd-enforcement.sh` |
| Completion checks | `.claude/hooks/completion-bundle.sh` |
| Add new gate | `.claude/settings.json` + new hook |
| Disable gate temporarily | Comment out in `.claude/settings.json` |

## Troubleshooting

### Reset all state

```bash
rm -rf .claude/workflow-state/*
touch .claude/workflow-state/.gitkeep
```

### Disable all hooks temporarily

Add to `.claude/settings.json`:
```json
{
  "disableAllHooks": true
}
```

### Check current state

Run `/workflow` to see current workflow status.
