# Bug Fix: Sidecar `.meta.json` timestamps lack ms/offset + no fetch duration field

- **Slug**: sidecar-timestamp-precision
- **Fixed**: 2026-06-15
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Added a dedicated `metaEncoder`/`metaDecoder` pair to `SessionArchive` that serializes `Date` fields as
full ISO-8601 with milliseconds and explicit `+00:00` UTC offset (via `ReportTimestampFormatter`), and
added a required `durationMs: Int` field to `ArtifactRecord` computed from the fetch interval.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Valistream/ValistreamCore/Sources/ValistreamCore/Networking/StreamFetching.swift` | modified | Added `durationMs: Int` field to `ArtifactRecord`; computed in `init` as `max(0, round((responseEndedAt − requestStartedAt) × 1000))` |
| `Valistream/ValistreamCore/Sources/ValistreamCore/Archive/SessionArchive.swift` | modified | Added `private static metaEncoder` (custom ISO-8601+ms date strategy) and `static metaDecoder` (parses `withFractionalSeconds`); `store` now uses `metaEncoder` instead of `Finding.prettyJSONEncoder` |
| `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Archive/SessionArchiveTests.swift` | modified | Updated `sidecarContainsAllFields` to use `metaDecoder` + assert `durationMs == 1000`; added `makeSubSecondResult` helper; added 4 new tests |
| `Valistream/Valistream/ValistreamIntegrationTests/PrettyJSONFilesTests.swift` | modified | `sidecarIsSchemaValid` now checks `durationMs` field presence and `requestStartedAt` timestamp format |
| `specs/004-output-readability/data-model.md` | modified | Added §7 "Sidecar `.meta.json` format" documenting timestamp form and `durationMs`; §8 renumbered from §7 |
| `specs/004-output-readability/contracts/compatibility.md` | modified | Updated C5 to reflect additive `durationMs` and new timestamp format; documents no back-compat decode path |

## Diff Highlights

**`StreamFetching.swift`** — `ArtifactRecord` struct:
```swift
public let bodyBytes: Int
public let durationMs: Int   // ← new
public let outcome: String

// in init:
self.bodyBytes = result.body.count
self.durationMs = max(0, Int((result.metadata.responseEndedAt
    .timeIntervalSince(result.metadata.requestStartedAt) * 1000).rounded()))
```

**`SessionArchive.swift`** — new encoder/decoder pair:
```swift
private static let metaEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
    encoder.dateEncodingStrategy = .custom { date, enc in
        var container = enc.singleValueContainer()
        try container.encode(ReportTimestampFormatter.format(date, timeZone: .gmt))
    }
    return encoder
}()

static let metaDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { dec in
        let container = try dec.singleValueContainer()
        let str = try container.decode(String.self)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: str) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(str)")
    }
    return decoder
}()
// store: Finding.prettyJSONEncoder → SessionArchive.metaEncoder
```

## Tests Added or Updated

- `SessionArchiveTests/sidecarContainsAllFields()` — updated: uses `metaDecoder`; asserts `durationMs == 1000`
- `SessionArchiveTests/sidecarTimestampsAreFullISO8601UTC()` — new: raw JSON timestamps match `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}\+00:00`; `durationMs` key present
- `SessionArchiveTests/sidecarSubSecondTimestampPrecision()` — new: sub-second start/end produce distinct strings; `durationMs == 250`
- `SessionArchiveTests/sidecarDurationMsIsZeroOnClockSkew()` — new: `responseEndedAt < requestStartedAt` → `durationMs == 0`
- `SessionArchiveTests/sidecarMetaCoderRoundTrip()` — new: sidecar file decoded via `metaDecoder` preserves dates within 1 ms; `durationMs` matches
- `PrettyJSONFilesTests/sidecarIsSchemaValid()` — updated: asserts `durationMs` present; asserts `requestStartedAt` contains `.` (ms) and ends with `+00:00`

## Local Verification

- Commands run: `BuildProject` (windowtab1) → success, 0 errors
- `RunSomeTests ValistreamCoreTests/SessionArchiveTests` → 13/13 passed
- `RunSomeTests ValistreamIntegrationTests/PrettyJSONFilesTests` → 6/6 passed

## Deviations from Assessment

None. Implemented exactly as specified:
- Dedicated `metaEncoder`/`metaDecoder` on `SessionArchive` — ✓
- `Finding.prettyJSONEncoder`/`jsonEncoder`/`jsonDecoder` untouched — ✓
- `durationMs` required, non-optional, computed from raw `Date` values — ✓
- UTC (`+00:00`) via `ReportTimestampFormatter.format(date, timeZone: .gmt)` — ✓
- `metaDecoder` is `internal` (not `private`) to allow `@testable import` access in tests — minor deviation from assessment's "private" suggestion, intentional for testability

## Follow-ups

- Existing `.meta.json` archives from pre-fix sessions are incompatible (missing `durationMs`, `Z` timestamps) — documented in C5; no action required
- `Finding.prettyJSONEncoder` date format split (sidecar ms, JSON report seconds) is documented in data-model.md §7 as intentional
