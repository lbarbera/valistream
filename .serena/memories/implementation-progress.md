# Valistream implementation progress

See `mem:implementation-setup` for layout, build/test commands (xcode-tools), test plans/schemes, serena-LSP-unavailable caveat.

## Test restructure (June 2026) — DONE
Integration tests moved OUT of the SwiftPM package INTO the CLI Xcode project:
- `ValistreamIntegrationTests` testTarget removed from `Package.swift` (package = `ValistreamCore` library + `ValistreamCoreTests` ONLY now — 1 test target, not 2).
- Integration sources + test stubs in `Valistream/Valistream/ValistreamIntegrationTests/` (incl. `Support/ScriptedStreamFetcher.swift`, `Support/ManualClock.swift`); unit-test-bundle target in `Valistream.xcodeproj`.
- Test plans: `ValistreamCore.xctestplan` (unit; package scheme) + `Valistream.xctestplan` (unit + integration; CLI scheme). `swift test` in package runs unit/conformance only; integration runs via Xcode `Valistream` scheme (xcode-tools RunSomeTests/RunAllTests, tab windowtab1).

## CLI restructure (June 2026) — DONE
CLI split into Xcode project tool target `Valistream` (sources `Valistream/Valistream/Valistream/`), links `ValistreamCore` (local) + `ArgumentParser` (remote). SWIFT_VERSION 6.0.

## Done (features)
- **Phase 1 (T001-T003)**: package skeleton, build green.
- **Phase 2 Foundational (T004-T015)**: tokenizer+AttributeList, playlist model+builder, Finding, StreamFetching/FetchResult/ArtifactRecord, URLSessionStreamFetcher, ScriptedStreamFetcher + ManualClock, SessionState+SessionLifecycle, ValidationSession actor, RuleEngine.
- **Phase 3 US1 MVP (T016-T028)**: RFC8216 master+media rules, AppleAuthoringRules, StreamClassifier, PlaylistLoader, ValidationSession.run() one-shot, CLI (ValistreamCommand + StatusRenderer, exit 0/1/2/3).
- **Phase 4 US2 live monitoring (T029-T040) — DONE (June 2026)**:
  - Pure components in `Sources/ValistreamCore/Monitoring/`: `RefreshScheduler` (RFC 8216 §6.3.4: initialDelay=TD, nextDelay changed=TD / unchanged=TD/2), `ContinuityChecker` (media-seq regression, head-removal, segment-stability mutation, discontinuity-inserted INFO, discontinuity-seq regression), `StalenessDetector` (>1.5×TD warning, >3×TD error, strict `>`), `Duration+Seconds.swift` (internal `.seconds` Double), `MonitorState` enum.
  - `Session/PlaylistSelection.swift`: `PlaylistSelection.Candidate` + `resolve(_:patterns:)` (nil/empty patterns → all; else localizedStandardContains match on id/groupID/name/url).
  - `ValidationSession` extended: added `sleep` closure param (default Task.sleep) + `selectPlaylists` provider closure param; `monitor()` via `withDiscardingTaskGroup`, `monitorPlaylist()` reload loop (sleep→fetch→re-validate `recordIfNew` dedup by signature→continuity→staleness→monitorState), `abort()`→aborted / `requestStop()`, time-limit deadline via now(), empty-selection note `TOOL.selection-empty`. New `SessionEvent.monitorStateChanged`.
  - CLI (T040): StatusRenderer handles monitorStateChanged + `--json` status objects to stdout; SIGINT/SIGTERM via DispatchSource → `abort()` + cancel runTask → exit 130 (state==.aborted); `--all` wiring; `PlaylistChecklist.swift` termios checkbox + numbered fallback + select-all when no TTY.
  - Tests: unit RefreshSchedulerTests/ContinuityCheckerTests/StalenessDetectorTests (Monitoring/), PlaylistSelectionTests (Session/). Integration `LiveMonitoringTests` + `LiveFaultScenarioTests` (+ Support `LiveSessionHarness` driving ManualClock deterministically via sleeperCount, `LivePlaylists` builder; added `sleeperCount`/`elapsedSeconds` to ManualClock).
- **125 unit tests green** (`swift test`); **140 total tests green** via Xcode (Valistream.xctestplan) — includes 5 new InterruptedSessionTests integration tests.

## New rule IDs (US2)
TOOL.continuity.media-sequence, .head-removal, .segment-stability, .discontinuity-inserted (info), .discontinuity-sequence; TOOL.staleness; TOOL.selection-empty (info).

## Rule IDs (US1, fixture/report consistency)
RFC8216.4.3.1.1, .4.3.4.2-BANDWIDTH, .4.3.4.2-URI, .4.3.4.1, .4.3.4.2.1, .4.3.3.1, .4.3.3.1-DURATION, .4.3.2.1, .4.3.3-DUPLICATE; APPLE.codecs/.average-bandwidth/.resolution/.independent-segments/.iframe-playlists/.variant-ladder/.target-duration; TOOL.delivery/.low-latency/.encryption.

## US3 done (June 2026) — T041-T050 all [X]
- `SessionArchive` actor: session folder `<outputDir>/<sessionID>/`, per-playlist `playlists/<id>/NNNNNN.m3u8` + `.meta.json` sidecars, `artifactIndex` accumulates across stores.
- `FindingsLog` (@unchecked Sendable class, JSONL append-only, `0x0A` per entry — durable on abort).
- `DiskSpaceWatcher` struct, injected capacity provider, warn ≤5 GiB / stop ≤500 MiB.
- `SessionReportBuilder`: `buildJSON` (schema v1, schemaVersion/session/stream/playlists/findings/summary/artifactIndex) + `buildMarkdown`.
- `ValidationSession` wired: archive/log/watcher created when `config.archiveEnabled`; every fetch archived (master as "master", media refs as "\(role)-\(i)", direct media as "media"); `record()` appends to JSONL; `setState(.aborted)` called BEFORE `writeReport` (bug fix — snapshot captures correct state); `finish()` async writes report.
- `SessionConfig.archiveEnabled` defaults `false` — existing tests unaffected.
- CLI sets `archiveEnabled: true`, prints `sessionFolderURL` path.
- New unit tests: SessionArchiveTests (8), FindingsLogTests (5), DiskSpaceWatcherTests (10), SessionReportTests (12).
- New integration tests: InterruptedSessionTests (5) — all with `.timeLimit(.minutes(1))`.
- File was placed in wrong dir (one level up); fixed by moving to `Valistream/Valistream/ValistreamIntegrationTests/`.
- `SessionConfig` param order: `outputDir` precedes `nonInteractive` — must match in all call sites.

## NOT done (remaining)
- US4 (T051-T055): SegmentAuditor + wiring + CLI --segments/--tolerance.
- Polish (T056-T060): message-actionability audit, scale test, styleguide/unit-testing compliance pass, README, full manual quickstart.

## Deviations / notes
- swift-tools-version 6.3 (template), not 6.0 as T001 text says.
- Finding JSON uses .withoutEscapingSlashes.
- Fixtures are Swift string constants; corpus/violation tests in Tests/ValistreamCoreTests/Conformance/.
- No git commit made (awaiting user request).
- Manual quickstart against real streams (T028/T060) not run. PlaylistChecklist termios path build-verified but not runtime-tested (headless env).
- Monitoring elapsed/staleness measured via injected `now` (Date); tests pin `now` to ManualClock offset so now()+sleep stay consistent.
- RunAllTests was flaky/cancelled twice in this env; RunSomeTests subsets reliable.
