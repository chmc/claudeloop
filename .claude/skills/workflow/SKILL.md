---
name: workflow
description: Show enforced workflow status and documentation
---

# Workflow Status

Show the current enforced workflow state and link to documentation.

## Check Current State

Run these commands to check workflow state:

```bash
# Branch confirmation
[ -f .claude/workflow-state/branch-confirmed ] && echo "Branch: $(cat .claude/workflow-state/branch-confirmed)" || echo "Branch: NOT CONFIRMED"

# Plan requirements
[ -f .claude/workflow-state/plan-requirements.json ] && cat .claude/workflow-state/plan-requirements.json || echo "No plan requirements"

# Completion state
echo "Simplify: $([ -f .claude/workflow-state/simplify-complete ] && echo 'done' || echo 'pending')"
echo "Review: $([ -f .claude/workflow-state/review-complete ] && echo 'done' || echo 'pending')"
echo "Visual: $([ -f .claude/workflow-state/visual-verified ] && echo 'done' || [ -f .claude/workflow-state/visual-skip-reason ] && echo 'skipped' || echo 'pending')"
```

## Documentation

Full workflow documentation: `docs/WORKFLOW.md`

## Quick Reference

| Gate | How to satisfy |
|------|---------------|
| Branch awareness | Confirm branch, then `echo "branch-name" > .claude/workflow-state/branch-confirmed` |
| Planning checklist | Include all 8 sections in plan |
| Plan-to-tasks | Use TaskCreate for plan steps |
| TDD | Edit test file before impl file |
| Documentation | Update docs if plan indicated |
| Workflow | Update skills/hooks if plan indicated |
| ADR | Create docs/adr/*.md if plan indicated |
| Install/README | Update if plan indicated |
| Simplify | Run /simplify, then `touch .claude/workflow-state/simplify-complete` |
| Code review | Complete review, then `touch .claude/workflow-state/review-complete` |
| Visual verification | Run /verify or `echo "reason" > .claude/workflow-state/visual-skip-reason` |
