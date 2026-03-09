# 25. Fixed retry delay

**Date:** 2026-03-09
**Status:** Accepted

## Context

Phase retries used exponential backoff (5s → 10s → 20s → 40s → 60s + jitter), designed for transient infrastructure failures. However, claudeloop already handles quota/rate-limit errors separately with a fixed 900s delay. The normal retry path handles logical failures (bad code, failed tests, no write actions) where the retry prompt context is what helps — not waiting longer. At attempt 5+, exponential backoff wasted 60-75 seconds of dead time per retry.

The `power()` and `get_random()` helper functions existed solely to support exponential backoff and added unnecessary complexity.

## Decision

Replace exponential backoff with a fixed delay equal to `BASE_DELAY` (lowered from 5s to 3s). Remove `MAX_DELAY` configuration variable, `power()`, and `get_random()` functions. `calculate_backoff()` now simply returns `BASE_DELAY` regardless of attempt number.

`BASE_DELAY` is kept as the configuration variable name since it is widely used in tests (as `BASE_DELAY=0` for fast test execution).

## Consequences

**Positive:**
- Eliminates 60-75s dead time per late retry (attempt 5+)
- Removes ~40 lines of numeric code (`power`, `get_random`, overflow guards, jitter)
- Simplifies configuration (one fewer variable)
- No impact on quota/rate-limit handling (separate `QUOTA_RETRY_INTERVAL` path)

**Negative:**
- If transient non-quota failures benefit from longer waits, those will retry faster (mitigated: such failures are rare and already handled by the quota path)
