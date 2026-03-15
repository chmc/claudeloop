# Architecture Decision Records

This directory captures the key architectural decisions made in ClaudeLoop.

For background on ADRs, see [Michael Nygard's article](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

| # | Title | Date | Status |
|---|-------|------|--------|
| [0001](0001-posix-shell.md) | Use POSIX sh instead of Bash | 2026-02-18 | Accepted |
| [0002](0002-global-state-model.md) | Global flat variables for all state | 2026-02-18 | Accepted |
| [0003](0003-eval-based-dynamic-variables.md) | Eval-based dynamic variable access with hardening | 2026-02-24 | Accepted |
| [0004](0004-awk-stream-processor.md) | AWK stream processor replacing Python | 2026-02-19 | Accepted |
| [0005](0005-decimal-phase-numbers.md) | Decimal phase numbers with underscore mapping | 2026-02-20 | Accepted |
| [0006](0006-dfs-cycle-detection.md) | DFS cycle detection with space-separated strings | 2026-02-18 | Accepted |
| [0007](0007-interrupt-resume-mechanism.md) | Graceful interrupt with state preservation | 2026-02-18 | Accepted |
| [0008](0008-config-precedence-chain.md) | Layered config precedence chain | 2026-02-18 | Accepted |
| [0009](0009-tdd-with-mutation-testing.md) | TDD workflow with mutation testing | 2026-02-23 | Accepted |
| [0010](0010-heartbeat-injection.md) | Heartbeat injection for spinner keepalive | 2026-02-23 | Accepted |
| [0011](0011-lock-file-concurrency.md) | Lock file with PID-based concurrency | 2026-02-18 | Accepted |
| [0012](0012-beta-release-pipeline.md) | Beta/prerelease support in release pipeline | 2026-02-25 | Accepted |
| [0013](0013-ai-powered-plan-parser.md) | AI-powered plan parser | 2026-02-25 | Accepted |
| [0014](0014-ai-verify-feedback-loop.md) | AI verification feedback loop | 2026-02-25 | Accepted |
| [0015](0015-phase-verification.md) | Phase verification | 2026-02-26 | Accepted |
| [0016](0016-mutation-testing-ci.md) | Mutation testing CI | 2026-02-27 | Accepted |
| [0017](0017-input-sanitization.md) | Input sanitization for eval/awk contexts | 2026-03-01 | Accepted |
| [0018](0018-progress-recovery-from-logs.md) | Progress recovery from logs | 2026-03-03 | Accepted |
| [0019](0019-orphan-log-integrity-check.md) | Orphan log integrity check | 2026-03-03 | Accepted |
| [0020](0020-orphan-interactive-recovery.md) | Wire orphan detection to intelligent recovery | 2026-03-03 | Accepted |
| [0021](0021-two-branch-release-strategy.md) | Two-branch beta/stable release strategy | 2026-03-06 | Accepted |
| [0022](0022-smoke-test-verification.md) | Smoke test and GUI verification skill | 2026-03-07 | Accepted |
| [0023](0023-fake-claude-cli.md) | Fake Claude CLI for verification & testing | 2026-03-08 | Accepted |
| [0024](0024-retry-strategy-rotation.md) | Retry strategy rotation for model-agnostic resilience | 2026-03-09 | Accepted |
| [0025](0025-fixed-retry-delay.md) | Fixed retry delay replacing exponential backoff | 2026-03-09 | Accepted |
| [0026](0026-phase-state-abstraction.md) | Phase state abstraction layer | 2026-03-09 | Accepted |
| [0027](0027-automatic-refactoring.md) | Automatic refactoring after phase completion | 2026-03-10 | Accepted |
| [0028](0028-decoupled-refactor-lifecycle.md) | Decoupled refactor lifecycle with persistent state | 2026-03-10 | Accepted |
| [0029](0029-refactor-retry-improvements.md) | Refactor retry improvements | 2026-03-11 | Accepted |
| [0030](0030-regression-based-refactor-verification.md) | Regression-based refactor verification | 2026-03-12 | Accepted |
| [0031](0031-no-changes-signal-file.md) | No-changes signal file for verification-only phases | 2026-03-15 | Accepted |
