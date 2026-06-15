# Feature 004 US3 — verbose tier (DONE 2026-06-15)

Committed `4ef8403` "Feature 4. US3: verbose tier + deterministic report ordering" on `main`. Builds on US1/US2. Tasks T042–T044 [X].

## What shipped
- **`StatusRenderer.renderTrace`** (T044): verbose-only. When a trace event's playlist/snapshot context changes, emits a context-header line (`.identifier` role / cyan), then the trace line (`.metadata` / dim, subordinate per T28). `lastTraceContext` tracks current context; reset to `nil` in EVERY non-trace branch of `render(_:TimestampedEvent)` so the header re-emits after any result/finding block breaks the stream. New `traceContext(of: TraceEvent)` maps each case → snapshotID (fetch/validation/stored/compare) or playlistID (scheduling/drift/rendition). Additive only — no change to findings/evidence/report/`--json`/exit.
- **`VerbosityEquivalenceTests.swift`** (NEW, T042): 6 tests — same scripted session run normal vs verbose; findings (count+IDs+severity/message/ruleId), exit state, report.md section structure, report.json keys/schemaVersion/findings-count, machine event stream (finding IDs + state sequence), and verbose-has-more-human-lines all asserted equal/greater. Cross-tier freeze guard (FR-021/SC-011).
- **`VerboseDistinctnessTests.swift`** EXTENDED (T043): +4 tests — category labels present, trace nested under context (ordering), `.metadata` subordinate (no result markers on trace lines), context header reappears after a block break.

## Machine-stream freeze — verified NOT violated
`--json` mode: `.trace` goes to **stderr** (`writer.writeToStderr`, verbose-gated); machine stdout NDJSON carries only findings (`writeMachineLine`) + status. So `--json` stdout is identical across tiers; verbose only adds stderr diagnostics. `verboseEvents: verbose` (set in ValistreamCommand) gates trace EMISSION via `emit` into both streams, but the `--json` renderer routes trace to stderr. T29 holds. (Pre-existing 003 design, correct.)

## Parent review fixes applied (post-worker)
1. Removed dead `"  " + formatted` indent in renderTrace (TerminalWriter.wrap() splits on whitespace → leading spaces stripped anyway; nesting is via the context header, not indentation). Fixed stale comment (header is `.identifier`, not `.metadata`).
2. **Non-deterministic report ordering bug** (caught by the new equivalence test, flaked on 2nd run): `playlistInfos = playlistTracks.map{…}` iterated a Dictionary + concurrent first-load → `## Session Details` / `report.json` playlist order varied run-to-run. Fixed in `ValidationSession+Reporting.writeReport`: sort `playlistInfos` AND `playlistInformation` master-first-then-by-id before building. report.md/report.json now regenerate identically (FR-021, R12). report.json playlist array order was never a frozen guarantee (003 also used dict order) → safe improvement.

## Tests
- **439 tests green** (RunAllTests, Valistream scheme), 0 navigator warnings, build clean. swift-test units 261.

## fetchStarted note (carryover from US2)
`TraceEvent.fetchStarted` still NOT emitted anywhere — `traceContext` handles it but no emit site. Existing categories (Fetch/Validation/Refresh/Compare/Stored) come from fetchIntent/fetchResult/validationPlaylistOK/refreshScheduled/continuityCompare/stored. Left unemitted (no test requires it). Could remove the unused case in polish if desired.
