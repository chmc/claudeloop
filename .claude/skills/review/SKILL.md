---
name: review
description: Run code review and create auditable session artifact
---

# /review — Code Review Skill

Creates auditable review session in `.claude/review-sessions/` that satisfies Gate 10.

## Usage

```
/review [context]
```

Context is optional kebab-case description (default: derives from branch).

## Step 1: Create Session

```sh
BRANCH=$(git branch --show-current)
GIT_SHA=$(git rev-parse --short HEAD)
CONTEXT="${1:-$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9]/-/g')}"
SESSION=".claude/review-sessions/$(date +%Y%m%d-%H%M%S)-${BRANCH}-${CONTEXT}"
mkdir -p "$SESSION"
```

## Step 2: Capture Diff

```sh
git diff main...HEAD > "$SESSION/diff.patch" 2>/dev/null || git diff HEAD~1 > "$SESSION/diff.patch"
```

## Step 2.5: Run Targeted Tests

For each modified `lib/*.sh` file, run its corresponding test if it exists:

```sh
for file in $(git diff --name-only main...HEAD | grep '^lib/.*\.sh$'); do
    base=$(basename "$file" .sh)
    test_file="tests/test_${base}.sh"
    if [ -f "$test_file" ]; then
        echo "Running $test_file..."
        bats "$test_file" >> "$SESSION/test-results.log" 2>&1 || echo "FAIL: $test_file" >> "$SESSION/test-results.log"
    fi
done
```

If `test-results.log` contains any `FAIL:` lines, set `result: FAIL` in the session README.

## Step 3: Review Changes

Review the diff using any method:
- Direct analysis of `git diff main...HEAD`
- External reviewer agent
- Manual inspection

Check for correctness, quality, test coverage, security.

## Step 4: Write Session README

Based on review, write `$SESSION/README.md`:

```yaml
---
date: <ISO 8601>
git_sha: <short sha>
branch: <branch>
result: PASS | FAIL
reviewer: <method used>
files_reviewed: [<from git diff --name-only>]
---

# Code Review: <context>

## Summary
<agent verdict summary>

## Findings
<issues found or "None">

## Approved
<what was approved, or changes needed>
```

Set `result: PASS` if agent says APPROVED, `result: FAIL` if NEEDS_CHANGES.

## Step 5: Report

Output session path and result:

```
Review complete: $SESSION
Result: PASS/FAIL
```

If PASS, Gate 10 is now satisfied for task completion.
