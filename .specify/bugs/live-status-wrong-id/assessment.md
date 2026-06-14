# Bug Assessment: Live monitoring lines show internal candidate IDs, not presentation IDs

- **Slug**: live-status-wrong-id
- **Created**: 2026-06-14
- **Source**: pasted text + macOS Terminal screenshot (`~/Desktop/Screenshot 2026-06-14 at 20.58.38.png`)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

> I still see that stdout writes "variant-2_6", "audio-5_3", etc. It suppose to show playlist ID. See screenshot of macOS Terminal.

Screenshot shows two ID styles in the same run:

- **Roster / legend (top)** — correct presentation IDs: `540p_avc1-mp4a → https://…`, `360p_avc1-mp4a → …`, `audio_nor → …`, `subs_nor → …`.
- **Live monitoring lines (below)** — wrong, internal IDs:
  - `• [variant-1] monitoring`, `• [audio-5] monitoring`, `• [subtitles-6] monitoring`
  - `variant-0_1 – OK`, `audio-5_1 – OK`, `subtitles-6_1 – OK`, `variant-4_1 – OK`
  - `[WARN] master_2_0 – no body captured for master_2` (×6)

## Symptom

During live monitoring, the per-playlist status lines (`[<id>] monitoring`, `<id>_<n> – OK`, finding/evidence lines, verbose traces) print the **internal selection candidate ID** (`variant-0`, `audio-5`, `subtitles-6`, `master_2`) instead of the **AliasRegistry presentation ID** (`540p_avc1-mp4a`, `audio_nor`, `subs_nor`, `master`) that US3/FR-013-ID mandates and that the roster, legend, JSON report, and markdown report already use correctly.

## Reproduction

1. Run the validator against a live HLS master playlist that produces presentation IDs (variants with `RESOLUTION`+`CODECS`, language-tagged audio/subs) — e.g. the Altibox stream in the screenshot.
2. Let it enter the `monitoring` state (live stream, not VOD).
3. Observe stdout: the roster prints `540p_avc1-mp4a`/`audio_nor`/`subs_nor`, but every monitoring line (`[id] monitoring`, `id_n – OK`, WARN/evidence lines) prints `variant-0`/`audio-5`/`subtitles-6`/`master_2`.

Expected: monitoring lines use the same presentation IDs as the roster.

## Suspected Code Paths

- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/PlaylistSelection.swift:71` — `Candidate.id` is built as `"\(reference.role.rawValue)-\(index)"` → `variant-0`, `audio-5`, `subtitles-6`. This is the internal candidate identity, never the registry alias.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift:27` — `monitorPlaylist(...)` threads `candidate.id` into nearly every event/label:
  - `setMonitorState(candidate.id, …)` → `.monitorStateChanged` → `• [variant-1] monitoring`
  - `.refreshCompleted(playlistID: candidate.id, index:…)` → `variant-0_1 – OK`
  - `SnapshotID.label(id: candidate.id, index:)` → `variant-0_1` (traces, evidence snapshot)
  - `.trace(.refreshScheduled/fetchIntent/fetchResult/continuityCompare/stored/validation…(playlistID/snapshotID: candidate.id))`
  - `incrementRefreshCount(candidate.id)`, `evaluateStaleness(candidate, …)`
  - Only the heartbeat `.activity(... aliasInScope: aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id)` resolves the registry alias — proving the registry is populated and reachable from this exact spot.
- `Valistream/Valistream/Valistream/StatusRenderer.swift:42-57` — renders `• [\(playlistID)] \(state)` and `renderRefreshCompleted(playlistID:…)` using whatever ID the event carries (no re-resolution at the CLI).
- Contrast — these already resolve the alias from the URL and are correct:
  - `Session/ValidationSession.swift:481` `emitRoster` → `aliasRegistry.alias(for: …)?.alias`
  - `Session/SessionReportBuilder.swift:273` per-playlist/JSON `id = aliasRegistry.alias(for: playlist.url)?.alias ?? playlist.id` (so FROZEN `playlists[].id` is unaffected — candidate id is only the fallback).
  - `Session/ValidationSession+Reporting.swift:32` `archiveFetch` resolves `presentationID` from the registry before storing.
- Secondary (`master_2` + "no body captured"): `Session/ValidationSession.swift:174` calls `archiveFetch(rootLoad.result, playlistID: "master")` **before** the master alias is registered for `inputURL` (registration happens at `:189` inside the `.master` branch). `archiveFetch` (`+Reporting.swift:40-50`) then registers the alias against `result.url`; the later `aliasRegistry.alias(for: inputURL, role: .master)` registers a *second* entry that dedups to `master_2`. Findings whose `resource` is `inputURL` resolve to `master_2`, and because no archive entry is keyed to `inputURL`, evidence resolves to `.unavailable` → `no body captured for master_2`. Confidence medium (depends on `result.url != inputURL`, e.g. a redirect on the master URL).

## Root Cause Hypothesis

**High confidence (primary).** The live monitoring/event pipeline keys every stdout-facing event on the pure `PlaylistSelection.Candidate.id` (`"\(role.rawValue)-\(index)"`), not on the `AliasRegistry` presentation ID. The presentation IDs are resolved from the playlist URL only in the roster, the report builders, `archiveFetch`, and the heartbeat — but `monitorPlaylist` (and the staleness/finding emission it drives) never resolves the alias, so the user-facing live lines display the internal candidate identity. US3 intended presentation IDs everywhere on stdout; the monitoring surface was missed.

**Medium confidence (secondary).** `master_2` and `no body captured for master_2` stem from the master being identified by two different URLs/registrations (fetch-time `result.url` vs. discovery-time `inputURL`), producing a dedup alias and a broken evidence join. Related but distinct from the candidate-ID issue.

## Proposed Remediation

**Preferred (localized, low-risk).** Resolve the presentation ID once at the top of `monitorPlaylist` and use it everywhere the method currently uses `candidate.id`:

```swift
let presentationID = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id
```

Replace `candidate.id` with `presentationID` in: `setMonitorState`, `SnapshotID.label`, every `.trace(...)`, `archiveFetch`, `incrementRefreshCount`, `.refreshCompleted`, and the staleness path (`evaluateStaleness` uses `candidate` — pass the resolved ID or have it resolve the same way). This mirrors what the heartbeat `.activity` already does and keeps `Candidate.id` (hence `--preselect` matching) unchanged. Scope: one file.

**Alternatives**:
- *Systemic single-source*: stamp the registry alias into `Candidate.id` at construction in `ValidationSession.run()` (after aliases are registered), so candidate, `trackPlaylist`, archive, and events share one ID. Cleaner, but changes what `--preselect <pattern>` matches against (presentation ID instead of `variant-0`) — a behavioral change that should be confirmed against `spec.md`/`contracts/cli-interface.md` (FR-018) before adopting.
- *Render-side resolution*: have `StatusRenderer` re-resolve IDs. Rejected — the CLI has no registry; the Core is the right owner.

**Secondary fix** (`master_2` / lost master evidence): register the master alias for `inputURL` **before** the master `archiveFetch`, and make `archiveFetch` + finding `resource` key on a consistent URL so the master keeps the single ID `master` and its evidence resolves. Confirm whether `result.url` diverges from `inputURL` (redirect) for this stream first.

**Files likely to change**:
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift` (primary)
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` (secondary: master alias ordering; optionally candidate-id stamping for the systemic variant)
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Reporting.swift` (secondary: `archiveFetch` master branch)

**Tests to add or update**:
- Integration: assert that emitted `.monitorStateChanged` / `.refreshCompleted` / `.trace` carry the presentation ID (`540p_avc1-mp4a`, `audio_nor`), not `variant-0`/`audio-5`. Drive via `LiveSessionHarness` with `LivePlaylists` that yield resolvable IDs. (`Valistream/Valistream/ValistreamIntegrationTests/LiveMonitoringTests.swift` or `EvidenceInOutputTests.swift`.)
- Unit: a case proving `monitorPlaylist`'s event IDs equal `aliasRegistry.alias(for: url)` for a known master+media set.
- Secondary: a master fetched via a redirected URL keeps ID `master` (not `master_2`) and its findings resolve to a real evidence file.
- Guard: re-run `ReportJSONSchemaTests` to confirm `playlists[].id` (FROZEN) is unchanged.

## Risks & Considerations

- **FROZEN contract**: the fix must not alter JSON `playlists[].id` — it already resolves via the registry (`SessionReportBuilder.swift:273`), so the localized fix leaves it untouched. Verify with `ReportJSONSchemaTests`.
- **Archive paths**: the preferred fix routes `archiveFetch(playlistID: presentationID)` for monitored playlists. `archiveFetch` already re-resolves the alias internally, so on-disk paths stay `playlists/<presentationID>/…` — but confirm the snapshot index/continuity evidence pairing (`SnapshotID.label`) still lines up after the ID swap.
- **`--preselect` semantics**: the preferred (localized) fix leaves `Candidate.id` and selection matching unchanged. The systemic alternative changes the match surface — only adopt with a spec check.
- **Empty/unresolvable IDs**: keep the `?? candidate.id` fallback so playlists without a registry alias (edge cases, direct media before registration) still render a stable ID.
- This is output-only (no validation-rule change), consistent with the Feature 003 scope.

## Open Questions

- [NEEDS CLARIFICATION: For this stream, does the master fetch follow a redirect (i.e. `result.url != inputURL`)? Confirms the `master_2` / "no body captured" secondary hypothesis.]
- [NEEDS CLARIFICATION: Should `--preselect <pattern>` match against the presentation ID (`540p_avc1-mp4a`) going forward, or keep matching the role-based candidate ID (`variant-0`)? Decides preferred vs. systemic fix.]
