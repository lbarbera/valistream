# Feature 002 — Performance and UX (PLANNED, not implemented)

Planned 2026-06-13. Artifacts: `specs/002-performance-ux/{plan,research,data-model,quickstart}.md` +
`contracts/{cli-interface,report-format,terminal-output}.md`. See `mem:implementation-progress` /
`mem:implementation-setup` for the 001 codebase it layers on.

## Scope
UX/perf only on top of 001. US1 responsive narrated output (MVP) → US2 graceful stop → US3 output dir
→ US4 live/aliased/prettified report → US5 Promptberry prompt. Segment/bandwidth audit = OUT (deferred).

## Binding design decisions (research.md D1–D10)
- **Core `ValistreamCore` stays ZERO external deps.** New deps Rainbow (color) + Promptberry (prompts)
  attach to the **CLI Xcode target only** (like ArgumentParser). Aliases + atomic/live report writing
  + output-location resolver + progress events = pure logic in core.
- **FROZEN (FR-003): JSON report schema, rule sets/IDs, exit codes (0/1/2/3, 130).** Only report write
  timing changes (per refresh cycle, atomic temp+replace).
- **Aliases markdown-only** — never added to JSON (avoids schema drift). `PlaylistAlias`/`AliasRegistry`
  in core: role+attrs (video-1080p/audio-en/subs-en/iframe-720p), indexed fallback V1/A1/S1/I1, dedup
  numeric suffix, stable per session.
- **Graceful stop**: unified `finish()` for completion/stop/limit; 1st SIGINT = cancel-in-flight +
  flush + finalize ≤3s (one-shot → PARTIAL report); 2nd SIGINT = `_exit(130)`. Extends existing
  abort/stopRequested. Applies to one-shot too (run() must honor stop between playlists).
- **Output dir**: `OutputLocation` (core) resolves absolute; default base `~/.valistream/sessions/<id>/`
  (literal dotfolder on macOS per clarification, NOT Application Support); pre-flight writability →
  fail fast before fetch; print absolute path first.
- **Styling gate (CLI)**: color iff isatty ∧ ¬NO_COLOR ∧ ¬--no-color ∧ TERM≠dumb. Severity also in
  text. Reports never styled.
- **Verbosity**: --quiet (exists) / normal / --verbose (new); mutually exclusive; never affects files
  or exit codes.
- **Rename (FR-001)**: set CLI target `PRODUCT_NAME=valistream` (binary currently `Valistream`;
  ArgumentParser commandName already `valistream`).

## Dependency-verification caveat (CLAUDE.md: NO WebSearch; DocumentationSearch = Apple only)
Rainbow/Promptberry coordinates + Swift 6 / macOS 14 compat NOT verifiable at plan time. Confirm via
SwiftPM resolve at impl start (fails fast). Fallbacks: in-house ANSI (color); retain termios
`PlaylistChecklist` (prompts, US5 is P5/optional). Recorded in plan Complexity Tracking.

## Stale flags
`--segments`/`--tolerance` CLI args exist but US4-segments never built and now deferred — hide/remove
in 002 (inert), don't advertise.

## Next: `/speckit-tasks` then `/speckit-analyze`.
