# 16. Mutation Testing CI

**Date:** 2026-02-27
**Status:** Accepted

## Context

Mutation testing (`tests/mutate.sh`) was manual-only. Without automated runs, test quality regressions could go unnoticed between releases. The script also always exited 0 regardless of results, making it unsuitable for CI without modification.

## Decision

Add a GitHub Actions workflow (`.github/workflows/mutation-testing.yml`) that:
- Runs weekly on Monday 06:00 UTC via `schedule`
- Supports manual triggering via `workflow_dispatch` with optional inputs: target file, `--with-deletions`, `--with-integration`
- Installs bats-core via npm (apt provides the old unmaintained `bats` package)
- Reports results as a GitHub job summary and uploads the mutation report as a downloadable artifact
- Uses `concurrency` groups per event type so manual runs don't cancel scheduled runs

Additionally, `tests/mutate.sh` now exits 1 when surviving mutants exist (`[ "$TOTAL_SURVIVED" -gt 0 ] && exit 1`), giving CI a meaningful pass/fail signal.

## Consequences

- (+) Automated weekly regression detection for test quality
- (+) Mutation score visible in workflow history and job summaries
- (+) Manual trigger allows targeted investigation of specific files
- (-) Up to 240 minutes of CI budget per weekly run
- (-) Exit code change is a breaking change for scripts that depend on `mutate.sh` always returning 0
