# Data Model: HLS Stream Validator

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md) | **Date**: 2026-06-12

Entities below mirror the spec's Key Entities, refined with fields, relationships, lifecycle, and
the on-disk archive layout. Names are conceptual; Swift type names may differ cosmetically.

## ValidationSession

One run of the tool against one stream URL (spec: Validation Session).

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | `YYYYMMDD-HHmmss-<short-random>`; doubles as session folder name |
| `inputURL` | URL | as provided by the user (FR-001) |
| `config.segmentMode` | bool | default `false` (FR-012) |
| `config.bandwidthTolerance` | decimal | default `0.10` (FR-012) |
| `config.timeLimit` | duration? | optional live-session cap (FR-015) |
| `config.selection` | selection spec? | pre-supplied playlist selection for non-interactive runs (FR-018) |
| `config.outputDir` | path | parent dir for session folders; default `./valistream-sessions/` |
| `config.nonInteractive` | bool | suppresses checklist prompt (FR-018) |
| `startedAt` / `endedAt` | timestamp | |
| `streamKind` | enum | `vod` \| `event` \| `live` (FR-005) |
| `state` | enum | see lifecycle |
| `findings` | [Finding] | append-only |
| `playlists` | [PlaylistDescriptor] | discovered from master |

**Lifecycle (state transitions)**:

```text
initializing → fetchingMaster → validatingInitial → selectingPlaylists
    → monitoring (live only)          → finishing → completed
    → finishing (vod: after initial+segments) → completed
any state → aborted   (user interrupt; summary still produced — FR-015, edge case)
any state → failed    (fatal: unusable input, storage failure — edge cases)
```

- `selectingPlaylists` is skipped (auto-select all / supplied selection) when non-interactive
  (FR-018).
- Empty selection ⇒ straight to `finishing` with a note (edge case "deselects every playlist").

## PlaylistDescriptor

A master or media playlist discovered in the session (spec: Playlist).

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | stable within session; used in archive paths & report |
| `kind` | enum | `master` \| `media` |
| `role` | enum? | media only: `variant` \| `audio` \| `subtitles` \| `iframe` |
| `url` | URL | resolved absolute URL |
| `parent` | PlaylistDescriptor? | master that referenced it; nil for the master itself or direct media input (FR-002) |
| `declared` | attribute map | from master: `BANDWIDTH`, `AVERAGE-BANDWIDTH`, `CODECS`, `RESOLUTION`, `FRAME-RATE`, `GROUP-ID`, language, name, … |
| `selected` | bool | monitoring/segment scope membership (FR-018); always `true` for initial validation |
| `monitorState` | enum | `idle` \| `monitoring` \| `stale(warning)` \| `stale(error)` \| `stopped` (FR-007, FR-009) |
| `refreshes` | [PlaylistRefresh] | ordered observations |

## PlaylistRefresh

One observation of a media playlist at a point in time (spec: Playlist Refresh). For VOD each
playlist has exactly one.

| Field | Type | Notes |
|-------|------|-------|
| `index` | int | 0-based per playlist |
| `fetchedAt` | timestamp | |
| `artifact` | ArtifactRecord | the fetch that produced it (FR-010/011) |
| `parse` | parse result | lossless token stream + structured model + parse-level findings |
| `mediaSequence` | int | `EXT-X-MEDIA-SEQUENCE` (continuity baseline, FR-007) |
| `discontinuitySequence` | int | `EXT-X-DISCONTINUITY-SEQUENCE` (FR-007) |
| `targetDuration` | duration | drives reload cadence (FR-006, research §4) |
| `segments` | [SegmentRef] | uri + duration + attrs per entry |
| `changed` | bool | vs. previous refresh; drives cadence backoff + staleness clock (research §4) |
| `endlist` | bool | `EXT-X-ENDLIST` seen ⇒ live playlist ended |

**Continuity rules evaluated between refresh `n-1` and `n` (FR-007)**: media sequence monotonic
non-decreasing; retained segment entries byte-identical (URI+duration+attrs); removals only from the
head and only ≥ spec-allowed age; discontinuity sequence consistent with removed `EXT-X-DISCONTINUITY`
tags; staleness clock per research §4 (warning > 1.5× TD, error > 3× TD).

## SegmentRecord

A media segment referenced by a media playlist (spec: Segment). Materialized only in segment mode
(FR-012), otherwise segments exist merely as `SegmentRef` entries inside refreshes.

| Field | Type | Notes |
|-------|------|-------|
| `playlist` | PlaylistDescriptor | owning media playlist |
| `uri` | URL | resolved |
| `sequenceNumber` | int | derived from media sequence + offset |
| `duration` | duration | declared in playlist |
| `byteRange` | range? | `EXT-X-BYTERANGE` if present |
| `artifact` | ArtifactRecord | download record |
| `measuredBytes` | int | actual downloaded size |
| `impliedBitrate` | int | `measuredBytes * 8 / duration` |
| `verdict` | enum | `withinTolerance` \| `exceedsDeclared(by: %)` \| `downloadFailed` (FR-012, US4) |

## Finding

One validation observation (spec: Finding).

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | unique within session |
| `ruleId` | string | e.g. `RFC8216.4.3.4.1`, `APPLE.variant-ladder`, `TOOL.delivery` (FR-008) |
| `source` | enum | `rfc8216` \| `apple-authoring` \| `tool` (FR-008 — rule source standard) |
| `severity` | enum | `error` \| `warning` \| `info` (FR-008) |
| `category` | enum | `masterPlaylist` \| `mediaPlaylist` \| `continuity` \| `delivery` \| `segment` (FR-008) |
| `resource` | URL | affected resource (FR-008) |
| `location` | struct? | line number / tag name within the artifact, when applicable |
| `refreshIndex` | int? | which observation, for live findings |
| `observedAt` | timestamp | (FR-008) |
| `message` | string | human-readable description |
| `context` | map | rule-specific extras (e.g., stale duration, measured vs declared bitrate) |

## ArtifactRecord

A stored copy of one downloaded resource + request/response metadata (spec: Artifact Record;
FR-010/FR-011, research §3).

| Field | Type | Notes |
|-------|------|-------|
| `requestId` | string | monotonic per session; ties artifact ↔ sidecar ↔ findings |
| `url` | URL | final URL fetched |
| `method` | string | `GET` |
| `requestHeaders` | map | as sent |
| `requestStartedAt` / `responseEndedAt` | timestamp | from task metrics |
| `remoteAddress` / `remotePort` | string / int | from `URLSessionTaskMetrics` (FR-011) |
| `httpStatus` | int | |
| `responseHeaders` | map | |
| `negotiatedProtocol` | string | `h2`, `http/1.1`, … |
| `redirectChain` | [hop] | per hop: url, status, headers, timestamps (edge case "redirects") |
| `bodyPath` | relative path | verbatim body location in session folder |
| `bodyBytes` | int | |
| `outcome` | enum | `success` \| `httpError` \| `transportError(description)` (FR-014) |

## SessionReport

End-of-session aggregate (spec: Session Report; FR-015/016). Serialized as `report.json`
(contract: [contracts/session-report.schema.json](contracts/session-report.schema.json)) and
`report.md`.

Contents: session metadata + config; stream classification; monitored vs. excluded playlists
(FR-018); findings (full list + counts by severity × category × source); per-playlist refresh
statistics (count, cadence adherence, staleness episodes); segment audit summary (when enabled);
artifact index (requestId → paths); interruption marker when aborted.

## Archive Layout (per session folder)

```text
<outputDir>/<session-id>/
├── session.json                  # session config + state snapshot (updated at transitions)
├── findings.jsonl                # append-only findings stream (crash-safe — research §10)
├── report.json                   # final report (schema-versioned)
├── report.md                     # human-readable final report
├── playlists/
│   └── <playlist-id>/
│       ├── 000000.m3u8           # refresh bodies, verbatim, zero-padded refresh index
│       ├── 000000.meta.json      # ArtifactRecord sidecar for that fetch
│       └── …
└── segments/                     # segment mode only
    └── <playlist-id>/
        ├── <seq>-<name>.bin      # verbatim segment body
        └── <seq>-<name>.meta.json
```

Rules: bodies byte-exact, never wrapped or rewritten (research §10); one `.meta.json` sidecar per
fetch including redirect chains; nothing deleted or deduplicated during a session (Clarification #3);
disk-space watcher thresholds per research §11.
