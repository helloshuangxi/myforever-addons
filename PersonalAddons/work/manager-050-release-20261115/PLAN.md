# Manager 0.5.0 release

## Goal
Merge the accepted manager into main, publish Mac DMG and Windows Setup with self-update feeds, and show the public GitHub repository and contribution invitation on the website.

## Constraints
Release authority is the user's 2026-11-15 acceptance. Limit integration to Manager and release/site support; do not merge held PR #10 gameplay code or PR #11 collector changes. Preserve the current site's other plugin metadata, historical downloads, community data, existing services, and local game/user settings. Mark Windows/Intel native tests and signing limits accurately. Never overwrite an already published artifact.

## File changes
- PersonalAddons/Manager: import the tested manager tree from 5289440; update candidate documentation for the authorized release; keep application behavior unchanged.
- PersonalAddons/website/ops: installer/feed sync and validation, compatible legacy ZIP handling, download/cache support in deployment and live checks.
- PersonalAddons/website/public: manager release/download metadata, versioned installers and per-RID feeds; install instructions and open-source links on homepage and manager page.
- AGENTS.md, CONTRIBUTING.md and release documentation: authorization, useful contributor entry points and exact verification limits.

## Step-by-step plan
1. Record the remote main and live site's hashes; hydrate immutable published assets in a clean worktree.
2. Integrate only the accepted manager files, add installer/feed release automation, update website copy and contributor links.
3. Run manager and release tooling regressions; compare application source with the accepted build, build and audit three platform packages, check DMG architecture/signatures and feed integrity.
4. Commit and merge the scoped release into main; retain PR #10/#11 separately. Build artifacts must reference the confirmed source commit.
5. Stage and verify a site snapshot preserving all historical public bytes; deploy using the existing rollback-capable entry point and publish a GitHub prerelease with the same installer bytes.
6. Verify public HTTPS, downloads/SHA-256, architecture-specific feeds, repository links and old services; record actual results and remaining native-test limits.

## Risks
The original feature branch includes unrelated gameplay commits, so do not merge it wholesale. Old tooling assumes ZIP: extend checks rather than bypassing them. Feed indexes must never reference missing packages. The site snapshot must retain current downloads and backend data. Public Mac/Windows signing remains limited; user M-chip acceptance does not imply Windows/Intel native approval. No real game mutation, default-profile app launch or real AI request is needed for this release.
