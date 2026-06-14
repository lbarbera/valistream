# Bug Assessment: Master redirect breaks alias + evidence join (`master_2` / "no body captured")

- **Slug**: master-2-wrong-alias
- **Created**: 2026-06-14
- **Source**: pasted text + screenshot (`~/Desktop/Screenshot 2026-06-14 at 20.58.38.png`)
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

> I see some weird "master_2_0 - no body captured for master_2" in the stdout. See the screenshot. Also, master_2 is wrong alias

Screenshot shows repeated lines during a live run against an Altibox HLS master that redirects:

```
[WARN] master_2_0 – no body captured for master_2
[WARN] master_2_0 – no body captured for master_2
...
```

This is the **KNOWN FOLLOW-UP** already documented in serena memory `bugfix-live-status-wrong-id`
("master redirect identity"), deferred from the live-status-wrong-id fix.

## Symptom

When the master playlist URL issues an HTTP redirect, the master is registered in the alias
registry under **two** URLs, producing the dedup alias `master_2` (expected: `master`), and every
master finding fails its evidence join, emitting `[WARN] master_2_0 — no body captured for master_2`.
Expected: master alias is `master`, master findings resolve to their archived snapshot body, no
spurious WARN.

## Reproduction

1. Validate an HLS stream whose **master** URL returns a 3xx redirect to a different final URL
   (the Altibox `*.envision.services.altibox.net` master in the screenshot does this).
2. Observe stdout / report: master alias shows as `master_2` and any master-level ERROR/WARN finding
   prints `master_2_0 — no body captured for master_2`.
3. Compare to a non-redirecting master: alias is `master`, evidence resolves.

(Media playlists that redirect would hit the same evidence-join break, but only the master is
observed here because only the master URL redirects.)

## Suspected Code Paths

- `Networking/URLSessionStreamFetcher.swift:62` — `FetchResult(url: response.url ?? url, …)`: the
  result's `url` is the **redirected final** URL, not the requested URL. (Correct for base-URL
  resolution, wrong as a join key.)
- `Session/ValidationSession.swift:174-175` — `loader.load(inputURL)` then
  `archiveFetch(rootLoad.result, playlistID: "master")` runs **before** alias registration.
- `Session/ValidationSession+Reporting.swift:44,51,61` — `archiveFetch` looks up / registers the
  master alias on `result.url` (redirected) and stores `IndexEntry(url: result.url, …)`.
- `Session/ValidationSession.swift:193` — discovery-time `aliasRegistry.alias(for: inputURL, role: .master)`
  registers the **requested** URL; base `"master"` already taken by the redirected URL.
- `Session/PlaylistAlias.swift:46-69` (`alias(for:role:)`) + `186-194` (`deduplicate`) — collision on
  `"master"` yields `master_2`.
- `Session/EvidenceResolver.swift:94` — `artifactIndex.filter { $0.url == finding.resource }`: findings
  use the requested URL; archive entry uses the redirected URL ⇒ empty match ⇒ `.unavailable(id:)`.
- `Session/SessionReportBuilder.swift:325-326` / `Session/EvidenceResolver.swift:57-60` — render
  `"no body captured for \(id)"`.
- `Session/PlaylistLoader.swift:96 (LoadedPlaylist.url = requested url)` and `:140
  (builder.build(baseURL: result.url))` — confirm `load.url` is the requested URL (used by all
  finding sites) while `result.url` is legitimately the redirect-final URL for relative resolution.

## Root Cause Hypothesis

**Confidence: high.** Identity of a playlist is keyed inconsistently across the redirect boundary.
Findings, roster, and discovery-time alias registration key on the **requested** URL
(`inputURL` / `load.url`); but the archive `IndexEntry` and the master alias registration inside
`archiveFetch` key on `result.url`, which is the **redirected final** URL. When the master redirects:

1. `archiveFetch` (ValidationSession.swift:175) runs first, sees `alias(for: result.url) == nil`, and
   registers the redirected URL as `master`, storing the archive entry under that URL.
2. Discovery registration (line 193) then registers `inputURL`; `"master"` is taken ⇒ `deduplicate`
   ⇒ `master_2`. Roster (`ValidationSession.swift:484`) reads `alias(for: inputURL)` ⇒ `master_2`.
3. `EvidenceResolver` joins findings (`resource == inputURL`) against archive entries
   (`url == redirected`) ⇒ no match ⇒ `.unavailable(id: alias(for: inputURL)) == master_2` ⇒ the WARN.

`result.url` being the final URL is *correct* for `PlaylistLoader.build(baseURL:)`; the defect is
that archive identity and alias registration reuse it as a join key.

## Proposed Remediation

**Preferred**: Key archive identity and `archiveFetch`'s alias lookup/registration on the
**requested** URL, leaving `result.url` for base-URL resolution only. Thread the requested URL into
`archiveFetch`:

- Change `archiveFetch(_ result: FetchResult, playlistID:)` →
  `archiveFetch(_ result: FetchResult, requestURL: URL, playlistID:)` (or pass the `LoadedPlaylist`,
  which already carries `.url` = requested).
- Inside `archiveFetch`: replace `aliasRegistry.alias(for: result.url)` → `alias(for: requestURL)`,
  `alias(for: result.url, role:)` → `alias(for: requestURL, role:)`, and `IndexEntry(url: result.url)`
  → `IndexEntry(url: requestURL)`.
- Call sites: `ValidationSession.swift:175` pass `inputURL`; `:217` pass `reference.url`;
  `ValidationSession+Monitoring.swift:98` pass `candidate.url` (`load.url`).

This makes alias registration, archive identity, findings, and roster all key on one URL (the
requested URL), eliminating the dedup alias and restoring the evidence join — uniformly for master
and any redirecting media. The resulting `playlists[].id` becomes `master` again, i.e. it *restores*
the FROZEN-correct value rather than changing it.

**Alternatives**:
- *Register master alias before archiving*: move the `alias(for: inputURL, role: .master)` registration
  (line 193) above the `archiveFetch` at line 175 so `master` is claimed for `inputURL` first. Reduces
  the dedup alias, but the evidence join still breaks (entry url stays redirected) — only a partial
  fix. Rejected.
- *Make the fetcher set `FetchResult.url = requested` and add a separate `finalURL`*: most uniform but
  invasive — `PlaylistLoader.build(baseURL:)` legitimately needs the final URL for relative resolution,
  so this would break base-URL handling unless every consumer is audited. Higher risk. Rejected.

**Files likely to change**:
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Reporting.swift`
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift`
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift`
- `Valistream/Valistream/ValistreamIntegrationTests/` (new redirect scenario)
- `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/PlaylistIDSchemeTests.swift` (alias assertion)

**Tests to add or update**:
- Integration (scripted in-process transport stub): master URL whose `FetchResult.url` differs from
  the requested URL (redirect). Assert: master alias == `master` (never `master_2`); roster `id` ==
  `master`; a master ERROR/WARN finding resolves to its archived body path (no `.unavailable`); stdout
  contains no `no body captured` line.
- Unit: `AliasRegistry` is not asked to register `master` twice for the same logical master when the
  redirect URL differs from the input URL.
- Optional regression: a redirecting **media** playlist resolves evidence (same join path).

## Risks & Considerations

- **FROZEN contract**: `playlists[].id` is FROZEN. The fix *restores* `master` (the correct id) for
  redirecting masters; verify against the FROZEN-guard suite that no other ids shift.
- Confirm `archive.store(result:playlistID:)` and meta sidecars still record the redirect chain
  (`metadata.redirectChain`) for observability — redirect info must not be lost when the entry key
  changes to the requested URL.
- Ensure `EvidenceResolver` fallback path and continuity (`.pair`) findings also resolve after rekey.
- Swift 6 strict concurrency: `archiveFetch` is on the session actor/class; adding a parameter is
  signature-only, no new sendability surface.

## Open Questions

- None blocking. The mechanism is confirmed end-to-end in code; remediation is a localized rekey.
