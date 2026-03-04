---
name: github
description: Git and GitHub conventions for this project
---

# Git & GitHub Conventions

Follow these conventions when committing, pushing, or creating PRs in this project.

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

- This project works on `main` directly: `git push origin main`
- Before pushing, check if you're ahead of remote: `git status` or `git log origin/main..HEAD`
- Do not force-push unless explicitly asked.

## Pull Requests

- Use `gh pr create` with a clear title and body.
- Keep PR titles under 70 characters.
