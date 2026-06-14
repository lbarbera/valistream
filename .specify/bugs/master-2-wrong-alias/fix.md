# Bug Fix: Master redirect breaks alias + evidence join (`master_2` / "no body captured")

- **Slug**: master-2-wrong-alias
- **Fixed**: 2026-06-14
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

When the master URL redirected, the master was registered under two URLs — the requested URL and the
redirected final `result.url` — producing the dedup alias `master_2` and a broken evidence join that
printed `[WARN] master_2_0 — no body captured for master_2`. The fix keys archive identity and the
master alias on the **requested** URL (matching findings, roster, and discovery-time registration),
leaving `result.url` for base-URL resolution only.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Session/ValidationSession+Reporting.swift` | modified | `archiveFetch` gains a `requestURL` param; alias lookup/registration and the evidence `IndexEntry` key on `requestURL`, not `result.url`; passes `requestURL` to `archive.store`. |
| `Session/ValidationSession.swift` | modified | Two `archiveFetch` call sites pass the requested URL: master → `inputURL`, media → `reference.url`. |
| `Session/ValidationSession+Monitoring.swift` | modified | Monitoring `archiveFetch` call passes `load.url` (the requested URL). |
| `Archive/SessionArchive.swift` | modified | `store(result:playlistID:)` gains `requestURL: URL? = nil`; the report's `artifactIndex` entry keys on `requestURL ?? result.url`. The meta sidecar still records the real fetched (final) URL via `ArtifactRecord`. |
| `ValistreamIntegrationTests/Support/ScriptedStreamFetcher.swift` | modified | `.redirect` reply now carries `finalURL` and emits `FetchResult.url = finalURL`, modelling the real fetcher (`response.url`). Previously the stub kept `url = requested`, which masked the bug. |
| `ValistreamIntegrationTests/DeliveryFailureTests.swift` | modified | Updated the one existing `.redirect` caller for the new `finalURL` argument (assertions unchanged). |
| `ValistreamIntegrationTests/MasterRedirectIdentityTests.swift` | added | Regression test for the redirecting-master identity. |

## Diff Highlights

`SessionArchive.store` — index keys on the requested URL:

```swift
public func store(result: FetchResult, requestURL: URL? = nil, playlistID: String) throws -> ArtifactRecord {
    ...
    artifactIndex.append(IndexEntry(
        requestId: requestId,
        url: requestURL ?? result.url,   // was: result.url
        bodyPath: bodyRelPath,
        metaPath: metaRelPath
    ))
}
```

`archiveFetch` — identity keyed on the requested URL:

```swift
func archiveFetch(_ result: FetchResult, requestURL: URL, playlistID: String) async {
    ...
    if let registered = aliasRegistry.alias(for: requestURL)?.alias { presentationID = registered }
    else if playlistID == "master" {
        let role: AliasRole = isMaster ? .master : .video
        presentationID = aliasRegistry.alias(for: requestURL, role: role).alias
    }
    ...
    let record = try? await archive.store(result: result, requestURL: requestURL, playlistID: presentationID)
    evidenceEntries.append(SessionArchive.IndexEntry(requestId: record.requestId, url: requestURL, ...))
}
```

## Tests Added or Updated

- `MasterRedirectIdentityTests/redirectingMasterKeepsIdentity()` — master URL redirects (`result.url`
  ≠ requested). Asserts: master alias == `master` (never `master_2`); no dedup alias exists; the
  report `artifactIndex` entry keys on the requested URL (not the final URL); a master finding
  resolves to its archived body and its terminal message contains no `no body captured`.
- `ScriptedStreamFetcher.Reply.redirect` — made faithful to the real fetcher (emits the final URL),
  so redirect-identity bugs are now reproducible in-process.

## Local Verification

- `xcode-tools BuildProject` (windowtab1) → built successfully, 0 errors.
- `xcode-tools RunSomeTests` → MasterRedirectIdentityTests + SessionArchiveTests + DeliveryFailureTests
  + PlaylistIDSchemeTests + EvidenceInOutputTests: 16/16 then 19/19 green.
- `xcode-tools RunAllTests` → **360 passed, 0 failed, 0 skipped** (full plan, incl. FROZEN-guard).

## Deviations from Assessment

The assessment proposed threading the requested URL into `archiveFetch` (done). During the fix the
real index source turned out to be `SessionArchive.artifactIndex` (built in `store` from `result.url`),
not the session's `evidenceEntries` — so the rekey had to be applied in `SessionArchive.store` as well
(via a defaulted `requestURL` parameter). The assessment had not listed `Archive/SessionArchive.swift`;
this expansion is in-scope (same root cause, same join key) and is logged here. A second, latent defect
was found and fixed: the test stub's `.redirect` reply never diverged `FetchResult.url`, which is why
no existing test caught the bug.

## Follow-ups

- The redirecting **media** path is now covered by the same rekey (media `archiveFetch` passes
  `reference.url` / `load.url`); no separate change needed.
- Consider asserting `report.json` master `playlists[].id == "master"` in a FROZEN-guard test for a
  redirecting master, for belt-and-suspenders on the frozen contract.
