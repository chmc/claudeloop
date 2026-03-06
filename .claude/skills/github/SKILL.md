---
name: github
description: Git and GitHub conventions for this project
---

# Git & GitHub Conventions

Follow these conventions when committing, pushing, or creating PRs in this project.

## Branching model

Two long-lived branches: `main` (stable) and `beta` (experimental). Before any work, check the current branch:
```sh
git branch --show-current
```
Confirm the target branch matches the intent (stable vs beta) before pushing.

**Rebase-only rule:** Never use `git merge`. Always use `git rebase` for branch synchronization.

## Commits

- **Conventional commits** are required: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, etc.
- Always pass the commit message via a HEREDOC:
  ```sh
  git commit -m "$(cat <<'EOF'
  feat: add phase timeout support
  EOF
  )"
  ```
- Do **NOT** add `Co-Authored-By` trailers.
- Keep the first line under 72 characters. Use the body for details if needed.

## Staging

- Stage specific files by name: `git add lib/retry.sh tests/test_retry.sh`
- **Never** use `git add -A` or `git add .`
- Skip `.env`, credentials, large binaries, and other sensitive files.

## Pushing

- Check the current branch before pushing and confirm it matches intent:
  - `git push origin main` for stable work
  - `git push origin beta` for beta/experimental work
- Before pushing, check if you're ahead of remote: `git status` or `git log origin/<branch>..HEAD`
- Do not force-push unless explicitly asked.

## Pull Requests

- Use `gh pr create` with a clear title and body.
- Keep PR titles under 70 characters.
