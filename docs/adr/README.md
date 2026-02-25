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
