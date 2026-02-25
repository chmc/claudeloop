# 9. TDD Workflow with Mutation Testing

**Date:** 2026-02-23
**Status:** Accepted

## Context

The project uses bats-core for testing, but test quality was hard to measure. Code coverage tools for shell scripts are limited and don't indicate whether tests actually verify behavior (a test that runs code without asserting anything still counts as "covered"). Mutation testing provides a stronger quality signal.

## Decision

Adopt a mandatory TDD workflow enforced through project conventions (CLAUDE.md) and add mutation testing via `tests/mutate.sh`:

**TDD workflow:**
1. Write failing tests first
2. Verify tests fail
3. Implement the minimal change to pass
4. Verify tests pass
5. Run full suite

**Mutation testing:**
- `tests/mutate.sh` applies small faults (mutations) to source code one at a time
- Mutations include: flipping comparisons, changing operators, altering string literals, swapping return values
- For each mutation, the corresponding test suite is run
- If tests still pass (mutation "survives"), the test suite has a gap
- Reports which mutations survived for targeted test improvement

Options: `--with-deletions` for line-deletion mutations, `--with-integration` to re-test survivors against integration tests.

## Consequences

**Positive:**
- Mutation testing catches tests that run code but don't assert correctness
- TDD workflow prevents writing tests after the fact that just confirm existing behavior
- `mutate.sh` is a zero-dependency shell script — no external tools needed
- Survivors point directly to specific test gaps

**Negative:**
- Mutation testing is slow (runs full test suite per mutation × number of mutations)
- Some mutations are "equivalent" — semantically identical to the original, so surviving is expected
- Mandatory TDD workflow requires discipline and adds overhead for small changes
- Shell-based mutation tool is limited compared to language-specific mutation frameworks
