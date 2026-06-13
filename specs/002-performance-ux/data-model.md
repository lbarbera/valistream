# Phase 1 Data Model: Performance and UX

**Feature**: 002-performance-ux | **Date**: 2026-06-13 | **Plan**: [plan.md](plan.md)

This feature adds **presentation/session-control** entities. It does **not** change feature 001's
domain model (playlists, findings, validation rules) or the structured-report schema (FR-003). New
types live in `ValistreamCore` when they are pure/testable domain logic, and in the CLI target when
they are terminal/IO concerns. The structured (JSON) report keeps the
[frozen schema](../001-hls-stream-validator/contracts/session-report.schema.json).

---

## Entities

### PlaylistAlias  *(core — new)*

A short, stable, human-meaningful, session-unique label standing in for a full playlist URL throughout
the human-readable report (FR-024–026; spec Key Entities).

| Field | Type | Notes |
|-------|------|-------|
| `alias` | String | e.g. `video-1080p`, `audio-en`, `subs-en`, `iframe-720p`, or indexed `V1`/`A1`/`S1`/`I1` |
| `url` | URL | full playlist URL it stands for |
| `role` | enum `{ video, audio, subtitles, iframe, master, unknown }` | derived from playlist context |
| `attributes` | [String: String] | the distinguishing attributes used (resolution, language, name…) for the legend |

**Derivation (deterministic, pure)**:
- `video-<height>p` from `STREAM-INF RESOLUTION`; `audio-<lang|name>` / `subs-<lang|name>` from
  `EXT-X-MEDIA TYPE/LANGUAGE/NAME`; `iframe-<height>p` from `I-FRAME-STREAM-INF`.
- Fallback to indexed `V1`/`A1`/`S1`/`I1` (role + 1-based ordinal) when distinguishing attributes are
  absent.
- Collision → deterministic numeric suffix (`video-1080p`, `video-1080p-2`).

**Rules**:
- **Stable**: computed once per playlist URL, reused across every refresh/report update within a session.
- **Deterministic**: pure function of `(role, attributes, discovery order)`.
- **Unique** within a session (post de-dup).

**Lifecycle**: built when a playlist is first discovered; held in a session-scoped
`[URL: PlaylistAlias]` map; read by the report builder and by progress events.

---

### AliasRegistry  *(core — new)*

Session-scoped owner of the `[URL: PlaylistAlias]` map; assigns aliases on first sight and guarantees
stability + uniqueness.

| Field | Type | Notes |
|-------|------|-------|
| `byURL` | [URL: PlaylistAlias] | stable mapping |
| `usedAliases` | Set<String> | drives collision de-dup |

**Operations**: `alias(for: URL, role:, attributes:) -> PlaylistAlias` (idempotent — same input always
returns the same alias for the session).

---

### OutputLocation  *(core — new)*

Resolves the absolute per-session output folder and validates writability (US3; FR-016–020).

| Field | Type | Notes |
|-------|------|-------|
| `baseDirectory` | URL | `--output` (resolved absolute) or platform default |
| `sessionFolder` | URL | `baseDirectory/<sessionID>` (absolute) |

**Rules**:
- Relative `--output` → resolved against current working directory (FR-020).
- Default base: macOS `~/.valistream/sessions/`; non-macOS platform data dir (FR-016).
- `sessionFolder` is unique per session (`sessionID` deterministic + collision-resistant) and never
  overwrites pre-existing content (FR-018).
- Pre-flight: base created if needed and verified writable **before** fetching; failure → fail-fast
  actionable error (FR-019).

**State**: created once at session startup; `sessionFolder.path` printed before any fetch (FR-017).

---

### ActivityProgress  *(core — new; carried on the event stream)*

The tool's current activity description + progress counters surfaced live (US1; spec Key Entities).

| Field | Type | Notes |
|-------|------|-------|
| `activity` | String | human phrase: "fetching master", "validating media playlist", "monitoring live" |
| `completed` | Int | units done (e.g., playlists processed) |
| `total` | Int? | known total when finite (one-shot); `nil` for open-ended live |
| `refreshes` | Int? | live-monitoring refresh count when applicable |
| `aliasInScope` | String? | alias of the playlist currently being acted on (nicer status text) |

**Delivery**: emitted as a `SessionEvent` case (additive to feature 001's enum) on the existing
`ValidationSession.events` `AsyncStream`. Consumed by the CLI renderer; not persisted to reports.

---

### SessionEndReason  *(core — new)*

Why a session finalized, so the report and CLI can label outcomes consistently (US2; FR-014–015).

`enum SessionEndReason { case completed, gracefulStop, timeLimit }`

- All three converge on the single `finish()` finalization path.
- A one-shot session ended by `gracefulStop` produces a report **marked partial**; live/`completed`/
  `timeLimit` produce a complete-for-period report.

---

### Session Report  *(core — extended from feature 001)*

Both the human-readable (Markdown) and structured (JSON) reports.

- **Structured (JSON)**: schema **unchanged** from feature 001 (FR-003, FR-021); only write *timing*
  changes — now written per refresh cycle, atomically (D6).
- **Human-readable (Markdown)**: now **prettified** (sections, severity/category grouping, aligned
  summaries — FR-023) and **expressed in aliases** with a resolving **legend** (FR-024–025). Kept
  continuously current during live monitoring; written atomically (FR-022).

| Section (Markdown) | Contents |
|--------------------|----------|
| Header | tool/session id, stream URL, start time, end reason, **partial** marker if applicable |
| Summary | finding counts by severity, playlists processed, refreshes — aligned/tabular |
| Legend | every `alias → full URL (role, attributes)` used in the body |
| Findings | grouped by severity, then category; each refers to playlists **by alias** |
| Per-playlist | one block per alias: status, refresh count, recent findings |

---

## CLI-side types *(CLI target — not core)*

These are terminal/IO concerns; they import Rainbow/Promptberry and never appear in the domain core.

### OutputStyle / Theme

Holds the styling gate result (D2) and the severity palette.

| Field | Type | Notes |
|-------|------|-------|
| `colorEnabled` | Bool | `isatty ∧ ¬NO_COLOR ∧ ¬--no-color ∧ TERM≠dumb` |
| `verbosity` | enum `{ quiet, normal, verbose }` | FR-011; mutually exclusive flags |

**Rules**: when `colorEnabled == false`, every render emits plain text (no SGR/cursor bytes). Severity
is always also labeled in text (FR-009). Verbosity affects on-screen output only — never report files
or exit codes (FR-003/FR-011).

### InterruptCounter

Tracks SIGINT count for the two-stage graceful stop (FR-012–013): first → request graceful stop; second
→ immediate `_exit(130)`.

---

## What is explicitly NOT changed

- Playlist / MediaPlaylist / MasterPlaylist models, `Finding`, rule IDs and rule sets (FR-003).
- The JSON report schema and field set (FR-003, FR-021, SC-010).
- The exit-code contract (0/1/2/3; 130 on forced interrupt) (FR-003).
- Segment download / bandwidth audit — out of scope, deferred to a future feature (spec §Out of scope).
