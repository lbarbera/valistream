# Contract: Session Report Format (002-performance-ux)

Covers both report files. The **structured (JSON)** report's schema is **frozen** to feature 001; the
**human-readable (Markdown)** report gains prettification + aliases. Both are kept current and written
atomically during live monitoring.

## Structured (JSON) report — FROZEN

- Schema is **byte-shape identical** to feature 001:
  [`session-report.schema.json`](../../001-hls-stream-validator/contracts/session-report.schema.json)
  (FR-003, FR-021, SC-010).
- **No fields added, removed, renamed, or retyped.** Aliases do **not** appear in the JSON.
- Only the **write timing** changes (see Atomic + live writing).

## Human-readable (Markdown) report

### Sections (in order) — FR-023

1. **Header** — tool name (`valistream`), session id, stream URL, start time, end reason
   (completed / graceful stop / time limit), and a clear **PARTIAL** marker when applicable.
2. **Summary** — finding counts by severity, playlists processed, refresh count; aligned/tabular.
3. **Legend** — every alias used in the body mapped to its full URL + role/attributes (FR-025).
4. **Findings** — grouped by **severity**, then **category**; each finding refers to playlists **by
   alias** (FR-024).
5. **Per-playlist detail** — one block per alias: status, refresh count, recent findings.

### Alias rules — FR-024–026, SC-007

- Every playlist URL appearing in the session is assigned a short, human-meaningful alias.
- The report **body** (Summary, Findings, Per-playlist) refers to playlists **by alias only** —
  **zero raw playlist URLs** outside the Legend (SC-007).
- Alias scheme: `video-<height>p`, `audio-<lang|name>`, `subs-<lang|name>`, `iframe-<height>p`;
  fallback indexed `V1`/`A1`/`S1`/`I1`; collisions de-duplicated with a deterministic numeric suffix.
- Aliases are **stable** across all refreshes within a session (same playlist → same alias) and
  **deterministic**.
- **Every** alias used anywhere in the body resolves through the Legend (FR-025).

## Atomic + live writing — FR-021, FR-022, SC-006

- **Atomicity**: each report file is written to a temp file in the same directory and atomically
  replaced; a reader opening either file at any moment sees a complete, valid document — never a
  partially written one.
- **Live freshness**: during live monitoring both reports are rewritten **once per refresh cycle**,
  coalescing all playlists refreshed that cycle into a single atomic write of both files; on-disk
  staleness ≤ one refresh cycle.
- **One-shot**: reports are written at completion and on graceful stop (the latter marked PARTIAL).

## Verification hooks

- `body_has_no_raw_urls`: a regex scan of Summary+Findings+Per-playlist finds no `http(s)://` (SC-007).
- `every_alias_resolves`: each alias token in the body appears exactly once in the Legend (FR-025).
- `json_schema_unchanged`: 002 JSON validates against the 001 schema with no extra properties
  (FR-003/SC-010).
- `atomic_no_partial_reads`: concurrent reads during a write never yield a truncated/invalid document.
