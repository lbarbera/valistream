# Bugfix: live status lines showed candidate IDs (2026-06-14)

Bug dir `.specify/bugs/live-status-wrong-id/`. Builds on `mem:implementation-progress` (feature 003).

## Fixed
Live monitoring stdout showed internal `PlaylistSelection.Candidate.id`
(`"\(role.rawValue)-\(index)"` → `variant-0`/`audio-5`/`subtitles-6`) instead of the
`AliasRegistry` presentation ID (`1080p_avc1`/`audio_en`/`master`). Only the heartbeat `.activity`
had resolved the alias; `setMonitorState`, `.refreshCompleted`, `SnapshotID.label`, all `.trace`,
`archiveFetch`, `incrementRefreshCount`, and `evaluateStaleness`'s `setMonitorState` leaked
`candidate.id`.

Fix (`Session/ValidationSession+Monitoring.swift`): resolve once at top of `monitorPlaylist`
`let presentationID = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id`, route through
all events/labels/archive; same one-liner in `evaluateStaleness`. `Candidate.id` left unchanged so
`--preselect` matching unaffected. Report/roster/JSON were already correct (resolve via URL).

Tests: new `PlaylistIDSchemeTests/monitoringUsesPresentationIDNotCandidateID` (master→`1080p_avc1`,
asserts `variant-0` never a key). Direct-media monitor-state key changed `"media"`→`"video_1"` in
`LiveMonitoringTests` + `LiveFaultScenarioTests` (registry alias for a no-RESOLUTION/CODECS direct
media playlist = `video_1`, matches roster). 27 integration + 32 FROZEN-guard tests green; build 0
warnings; JSON `playlists[].id` unchanged.

## FOLLOW-UP — FIXED 2026-06-14 (see `mem:bugfix-master-redirect-identity`) — master redirect identity
`URLSessionStreamFetcher` sets `FetchResult.url = response.url ?? url` (redirected final URL). When
the master URL redirects, master is registered under TWO urls: `result.url` (archive+registry via
`archiveFetch`) and `inputURL` (findings+roster via `run()`), giving dedup alias `master_2` and a
broken evidence join → `[WARN] master_2_0 – no body captured for master_2`. Distinct redirect-identity
bug in `ValidationSession.run()`/`archiveFetch`. Fix direction: key master findings, archive entry,
and alias on ONE consistent URL (align master with the media path, which uses `load.url` throughout).
