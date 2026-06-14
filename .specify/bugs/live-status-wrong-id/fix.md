# Bug Fix: Live monitoring lines show internal candidate IDs, not presentation IDs

- **Slug**: live-status-wrong-id
- **Fixed**: 2026-06-14
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

`monitorPlaylist` (and the staleness path it drives) emitted every live status event keyed on the
internal `PlaylistSelection.Candidate.id` (`variant-0`, `audio-5`, `subtitles-6`) instead of the
`AliasRegistry` presentation ID shown by the roster, legend, and report. The fix resolves the
presentation ID once per monitored playlist (`aliasRegistry.alias(for: candidate.url)?.alias ??
candidate.id`) and routes it through every monitoring event, snapshot label, trace, and archive call
— mirroring what the heartbeat already did. `Candidate.id` is left unchanged, so `--preselect`
matching is unaffected (open question Q2 deferred).

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift` | modified | `monitorPlaylist`: resolve `presentationID` once; replace `candidate.id` in `setMonitorState`, `SnapshotID.label`, all `.trace(...)`, `archiveFetch`, `incrementRefreshCount`, `.refreshCompleted`, heartbeat `aliasInScope`. `evaluateStaleness`: resolve `presentationID` for its `setMonitorState`. |
| `Valistream/Valistream/ValistreamIntegrationTests/PlaylistIDSchemeTests.swift` | added test | `monitoringUsesPresentationIDNotCandidateID()` — master→variant, asserts monitor state keyed `1080p_avc1`, not `variant-0`. |
| `Valistream/Valistream/ValistreamIntegrationTests/LiveMonitoringTests.swift` | modified test | Direct-media monitor-state key `"media"` → `"video_1"` (registry presentation ID) ×2 + clarifying comment. |
| `Valistream/Valistream/ValistreamIntegrationTests/LiveFaultScenarioTests.swift` | modified test | Same `"media"` → `"video_1"` ×2 + comment. |

## Diff Highlights

`ValidationSession+Monitoring.swift` — `monitorPlaylist` head:

```swift
// Live status, evidence, archive paths, and traces must all show the same presentation
// ID used by the roster, legend, and report (FR-013-ID). Resolve it once from the registry
// (populated at discovery in `run()`); fall back to the internal candidate ID only when the
// playlist was never registered.
let presentationID = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id
```

All downstream `candidate.id` event/label/archive uses now read `presentationID`. The previously
correct-but-redundant per-cycle `let alias = aliasRegistry.alias(for: candidate.url)?.alias ??
candidate.id` (heartbeat) was folded into the single `presentationID`.

## Tests Added or Updated

- `PlaylistIDSchemeTests/monitoringUsesPresentationIDNotCandidateID()` — regression guard: monitored
  variant is keyed by `1080p_avc1`; asserts `variant-0` is **never** a monitor-state key.
- `LiveMonitoringTests/healthyLiveRefreshesCleanly()`, `/gracefulStopProducesSummary()` — key updated
  to `video_1` (the registry ID a direct media playlist with no RESOLUTION/CODECS resolves to —
  matches the roster, which always used it).
- `LiveFaultScenarioTests/stallingPlaylistWarnsThenErrors()` (`video_1` == `.staleError`),
  `/timeLimitExpiryCompletesSession()`-suite monitoring assertion (`video_1` == `.monitoring`).

## Local Verification

- `BuildProject` (xcode-tools, `Valistream` workspace) → built successfully, 0 errors.
- `XcodeListNavigatorIssues` (warning severity) on the changed source → 0 issues.
- `RunSomeTests` — affected integration suites (`PlaylistIDSchemeTests`, `LiveMonitoringTests`,
  `LiveFaultScenarioTests`, `EvidenceInOutputTests`, `VerboseDistinctnessTests`,
  `HeartbeatMonotonicTests`, `RosterAndZeroURLTests`) → **27 passed, 0 failed**. New regression test
  green; trace lines remain ID-based; evidence/roster/heartbeat unaffected.
- `RunSomeTests` — FROZEN guards (`ReportJSONSchemaTests`, `ReportMarkdownTests`,
  `SessionReportTests`) → **32 passed, 0 failed**. JSON `playlists[].id` and markdown report unchanged
  (they already resolved the ID from the URL, independent of this path).

## Deviations from Assessment

- **Secondary `master_2` / "no body captured" issue NOT fixed here.** The assessment listed it as a
  *secondary* hypothesis gated by open question Q1. While auditing, Q1 was confirmed at the code level:
  `URLSessionStreamFetcher` sets `FetchResult.url = response.url ?? url` (the redirected final URL).
  When the master URL redirects, the master is registered under two URLs — `result.url` (archive +
  registry, via `archiveFetch`) and `inputURL` (findings + roster, via `run()`) — producing the dedup
  alias `master_2` and a broken evidence join (`no body captured`). This is a **distinct
  redirect-identity bug** in the master code path (`ValidationSession.run()` / `archiveFetch`), not the
  candidate-ID bug the user reported, and fixing it touches master/roster/report URL identity. It is
  left out of this change to keep the fix minimal and is recorded as a follow-up.
- Test key for direct media is `video_1` (not the assessment's illustrative `540p_avc1-mp4a`/`audio_en`,
  which apply to master-based streams). The new master-based regression test covers the `1080p_avc1`
  case directly.

## Follow-ups

- **New bug (recommended `/speckit-bug-assess`)**: master URL redirect causes `master_2` + lost master
  evidence. Fix direction: make `run()`'s master findings, archive entry, and alias registration key on
  one consistent URL (align the master with the media path, which already uses `load.url` everywhere).
- Open question Q2 (should `--preselect <pattern>` match the presentation ID rather than the role-based
  candidate ID?) remains a spec decision; the current fix intentionally does not change selection
  matching.
