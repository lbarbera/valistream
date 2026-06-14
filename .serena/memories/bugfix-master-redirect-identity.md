# Bugfix: master redirect identity — `master_2` / "no body captured" (2026-06-14)

Bug dir `.specify/bugs/master-2-wrong-alias/`. Resolves the KNOWN FOLLOW-UP from
`mem:bugfix-live-status-wrong-id`. Builds on `mem:implementation-progress` (feature 003).

## Root cause
When the master URL redirects, `URLSessionStreamFetcher` sets `FetchResult.url = response.url ?? url`
(redirected final URL — correct for `PlaylistLoader.build(baseURL:)` relative resolution). But
identity was keyed inconsistently across the redirect boundary: findings, roster, and discovery-time
alias registration key on the **requested** URL (`inputURL`/`load.url`), while the archive index entry
and the master alias registered inside `archiveFetch` keyed on `result.url`. With a redirect,
`archiveFetch` (runs before the explicit registration) claimed `"master"` for the redirected URL, so
`inputURL` deduped to `master_2`; and the evidence join `artifactIndex.filter { $0.url == finding.resource }`
missed → `.unavailable(id: master_2)` → `[WARN] master_2_0 — no body captured for master_2`.

## Fix
Key archive identity + alias on the REQUESTED URL, keep `result.url` for base resolution only.
- `ValidationSession+Reporting.archiveFetch` gained `requestURL: URL`; alias lookup/registration and
  the `evidenceEntries` IndexEntry key on `requestURL`; passes `requestURL` to `archive.store`.
- Call sites: `ValidationSession.swift` master→`inputURL`, media→`reference.url`;
  `ValidationSession+Monitoring.swift`→`load.url`.
- **Key insight:** the report's `artifactIndex` is `SessionArchive.artifactIndex` (built in
  `SessionArchive.store` from `result.url`), NOT the session's `evidenceEntries`. So `store` also
  needed the fix: added `requestURL: URL? = nil`, IndexEntry `url: requestURL ?? result.url` (defaulted
  → no churn for the ~13 test callers; meta sidecar still records the real final URL via ArtifactRecord).

## Latent test-stub defect (also fixed)
`ScriptedStreamFetcher.Reply.redirect` kept `FetchResult.url = requested` — never diverged — which is
why no test caught this. Changed to `.redirect(finalURL:finalBody:hops:)` emitting `url = finalURL`,
matching the real fetcher. Updated the one caller in `DeliveryFailureTests`.

## Tests
New `MasterRedirectIdentityTests/redirectingMasterKeepsIdentity()`: master redirects; asserts alias ==
`master` (no `master_2`), report artifactIndex keyed on requested URL (not final), master finding
resolves (no "no body captured"). Full plan: **360 passed, 0 failed** (incl. FROZEN guard); build 0
errors. `playlists[].id` for a redirecting master is restored to the FROZEN-correct `master`.
