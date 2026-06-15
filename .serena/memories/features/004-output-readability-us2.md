# Feature 004 US2 — quiet output + report incident timeline (DONE 2026-06-15)

Committed `35cbc25` "Feature 4. US2: quiet output + report incident timeline" on `main`. Builds on US1 (`mem:features/004-output-readability-us1`). Tasks T035–T041 [X].

## What shipped
- **`Session/IncidentTimeline.swift`** (NEW, T039): pure `IncidentTimeline(events: [(sequence: Int, event: TimestampedEvent)])` + `TimelineKind` enum (`.lifecycle(PlaylistLifecycleEvent.Kind)`/`.finding(Finding.Severity)`/`.operationalFailure`). `Entry` has `sequence`/`kind`/`findingAnchor`/`summary`. Eligibility: include warning+error findings, all lifecycle, operationalFailure (from `.stateChanged(.failed)`/`.aborted`); EXCLUDE info findings + all `.refreshCompleted`. Ordered by `(at, sequence)`, deterministic. Finding entries compact: `findingAnchor == "finding-<id>"`, summary never contains message/evidence (R11). Equatable.
- **`SessionReportBuilder.buildMarkdown`** (T040) new signature adds `timeline:`, `playlistInformation:`, `timeZone:` (all defaulted → old call sites compile). Section order: identity preamble → `## Summary` (outcome-first) → `## Incident Timeline` → `## Findings` → `## Playlist Information` → `## Legend` → `## Session Details` (was `## Per-playlist`). GitHub callouts `> [!CAUTION]`/`> [!WARNING]`, emoji `🔴/🟡/🔵 Error/Warning/Info`. Finding anchor = heading `#### Finding <id>` → `#finding-<id>`. Evidence/message appear exactly once (Findings only); timeline links via `[Finding <id>](#finding-<id>)`. No `![`/`<table>`. `buildJSON` FROZEN (unchanged signature/schema v1).
- **`ValidationSession+Reporting.swift`**: assembles `IncidentTimeline` from `recordedTimelineEvents`, passes `playlistInformation` accumulator + `timeZone: .current` to buildMarkdown.
- **`StatusRenderer.swift`** (T041) quiet tier: `buffer()` drops info-severity findings in `.quiet`; evidence line marked `noTimestamp` in quiet so it reads `message\nEvidence: path` contiguous. Quiet retains warnings/errors/lifecycle notices/shutdown state/final summary; omits state changes, classification, roster, info block, successful refresh, trace, info findings.
- **`TerminalWriter.Line`** gained `noTimestamp: Bool = false`; `formattedLines` early-returns styled text with no timestamp/wrapping when set.
- **`TraceEvent.fetchStarted(url:playlistID:refreshIndex:)`** NEW additive case + TraceFormatter line "Fetch started: …". NOTE: case exists + formats, but is NOT yet EMITTED in the fetch path — wire emission in US3 verbose tier (T044) if verbose should show it.
- **`TimestampFormatter.ReportTimestampFormatter.format`** rewritten to emit exact `YYYY-MM-DDTHH:mm:ss.SSS±HH:MM` (never `Z`). Rounds the whole instant to ms first (parent fix) so seconds/ms come from the same Calendar components — avoids off-by-one-second carry.

## Parent review fixes applied (post-worker)
1. TerminalWriter `noTimestamp` branch had an `if wholeLineTint` with two identical branches → collapsed.
2. ReportTimestampFormatter ms drift: was deriving ms from `timeIntervalSince1970` while sec from Calendar → off-by-one-sec at fractional ≥.9995; fixed via ms-rounded instant.

## Tests
- Existing tests updated for renamed sections (`## Per-playlist`→`## Session Details`, `### Error`→`### 🔴 Error`) in ReportMarkdownTests/SessionReportTests/LiveReportFreshnessTests — assertions preserved, not weakened.
- Staged integration tests had `@testable import Valistream` removed (CLI sources compile directly into the integration bundle — not a module).
- **429 tests green** (RunAllTests, Valistream scheme), 0 navigator warnings, build clean, frozen surfaces (CompatibilityFreezeTests/ReportJSONSchemaTests) intact.

## Process note
- `SendMessage` to continue a spawned worker is NOT available in this harness — parent applies small review fixes directly via serena instead of round-tripping to the worker.
