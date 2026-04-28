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

## Sub-Issues

Use GitHub's GraphQL API for sub-issue management:

```sh
# Get parent issue node ID
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    issue(number: 31) { id }
  }
}'

# Add sub-issue to parent
gh api graphql -f query='
mutation {
  addSubIssue(input: {
    issueId: "PARENT_NODE_ID",
    subIssueUrl: "https://github.com/OWNER/REPO/issues/32"
  }) {
    subIssue { number title }
  }
}'

# Remove sub-issue
gh api graphql -f query='
mutation {
  removeSubIssue(input: {
    issueId: "PARENT_NODE_ID",
    subIssueId: "SUB_NODE_ID"
  }) {
    issue { id }
  }
}'
```

Note: Sub-issues still appear in the main issues list (expected GitHub behavior). Use GitHub Projects with "group by parent" for hierarchical views.
