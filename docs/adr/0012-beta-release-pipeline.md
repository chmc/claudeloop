# 12. Beta/Prerelease Support in Release Pipeline

**Date:** 2026-02-25
**Status:** Accepted

## Context

New features and significant changes need testing before stable release. Without a prerelease channel, users either get untested releases or features are held back until manual testing is complete. A beta channel lets early adopters test changes while protecting the default install path.

## Decision

Add beta/prerelease support to the existing release pipeline and installer:

- **Version format:** follows semver with prerelease suffix: `0.14.0-beta.1`
- **Installation:** `curl ... | BETA=1 sh` fetches the latest beta; `curl ... | VERSION=x.y.z-beta.n sh` fetches a specific prerelease
- **Default behavior unchanged:** plain `curl ... | sh` always installs the latest stable release
- **GitHub Releases:** beta versions are marked as pre-releases, keeping them off the "latest" endpoint

The installer detects prerelease versions and routes to the appropriate GitHub release tag. Version comparison logic handles the prerelease suffix correctly for upgrade checks.

## Consequences

**Positive:**
- Early adopters can opt in to test new features
- Stable channel remains protected — default install is unaffected
- Standard semver prerelease conventions — familiar to developers
- Leverages GitHub's built-in pre-release marking

**Negative:**
- Adds complexity to version comparison logic (prerelease ordering rules)
- Two release channels to maintain and communicate about
- Beta users may report issues on pre-release features, increasing support surface
- No automatic promotion from beta to stable — requires a separate release
