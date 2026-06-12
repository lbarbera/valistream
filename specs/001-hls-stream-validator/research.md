# Research: HLS Stream Validator

**Feature**: [spec.md](spec.md) | **Date**: 2026-06-12

All Technical Context unknowns resolved below. Format per decision: Decision / Rationale /
Alternatives considered.

## 1. Language & Runtime — Swift 6 + SwiftPM

- **Decision**: Swift 6.x with strict concurrency, packaged as a SwiftPM package (library +
  executable), targeting macOS 14+.
- **Rationale**: The team works in the Apple ecosystem (tool exists to troubleshoot iOS/tvOS AVPlayer
  consumers); Swift structured concurrency (actors, `TaskGroup`, `AsyncSequence`) maps directly onto
  "N playlists monitored concurrently on independent cadences"; `URLSessionTaskMetrics` exposes the
  request/response metadata the spec demands (remote IP, precise timings) without third-party HTTP
  stacks; a future GUI wrapper (clarified as possible later) reuses the core library natively.
- **Alternatives considered**: Go (great CLI story, but foreign to team toolchain and AVPlayer-side
  intuition); Rust (performance overkill for I/O-bound polling; slower iteration); Python (weak
  long-running concurrency ergonomics for 24 h sessions; packaging burden for ops use).

## 2. M3U8 Parsing — custom line-level parser (no third-party parser)

- **Decision**: Implement our own M3U8 tokenizer/parser that preserves line numbers, raw bytes, and
  unknown/duplicate/malformed tags as first-class parse events.
- **Rationale**: Parsing *is* the product domain. A validator must surface exactly what is wrong and
  where (FR-008 requires line/tag references); third-party parsers are built for playback, so they
  normalize, skip, or silently tolerate the malformed input we must report. Lenient parse + rule
  evaluation over a lossless token stream is the core design.
- **Alternatives considered**: Existing Swift HLS parsers (playback-oriented, lossy on errors,
  unmaintained); regex-based ad-hoc parsing (unmaintainable once attribute-list grammar and quoting
  rules accumulate).

## 3. Request/Response Metadata Capture — URLSession + URLSessionTaskMetrics

- **Decision**: Single shared `URLSession` with delegate; capture per-request: request headers as
  sent, response headers, status code, body bytes; from `URLSessionTaskMetrics.transactionMetrics`:
  `remoteAddress`/`remotePort`, fetch start / response end timestamps, negotiated protocol; record
  every redirect hop via the redirect delegate callback (FR-011, edge case "redirects").
- **Rationale**: `URLSessionTaskMetrics` is the only first-party API exposing the resolved remote IP
  per transaction — satisfies FR-011 without raw sockets; redirect delegate gives per-hop fidelity.
- **Alternatives considered**: `NWConnection` hand-rolled HTTP (full control, but reimplements TLS,
  HTTP/2, proxies, redirects — large scope for no spec gain); shelling out to `curl` (loses typed
  metrics, fragile parsing, new runtime dependency).
- **Note**: HTTP caching disabled (`URLCache` off, `Cache-Control` honored as sent by server but
  every fetch hits the network) — a validator must observe origin behavior, not cache behavior.

## 4. Live Reload Cadence & Staleness Thresholds

- **Decision**: Implement RFC 8216 §6.3.4 client reload behavior per monitored playlist: first
  reload no earlier than the playlist's target duration after load; when a reload shows no change,
  back off to one-half target duration before retrying. Staleness findings (FR-007): **warning**
  when a playlist hasn't changed for > 1.5× target duration; escalate to **error** at > 3× target
  duration; both findings carry the observed stale duration.
- **Rationale**: §6.3.4 is the normative client behavior — "behaves like a real player"
  (Clarification: cadence, not variant selection). The 1.5× threshold is the industry-accepted
  liveness expectation (playlist must be refreshed server-side every target duration); 3× marks
  effective outage.
- **Alternatives considered**: Fixed poll interval (violates spec-mirroring requirement; over- or
  under-polls); `EXT-X-SERVER-CONTROL` blocking reload (LL-HLS semantics — out of scope per
  Clarification #1).

## 5. Apple HLS Authoring Specification — playlist-observable rule subset

- **Decision**: Implement the subset of Apple's HLS Authoring Specification checkable from playlists
  and segment byte-sizes alone, including (non-exhaustive): variant ladder sanity (bitrate ordering,
  gaps/duplicates); `CODECS`/`RESOLUTION`/`FRAME-RATE`/`BANDWIDTH`/`AVERAGE-BANDWIDTH` attribute
  presence and plausibility; I-frame playlist presence for VOD; audio/subtitle rendition group
  completeness and consistency across variants; `EXT-X-INDEPENDENT-SEGMENTS` presence; segment
  duration vs. declared target duration; 6-second-target-duration recommendation; measured segment
  bitrate vs. declared `BANDWIDTH`/`AVERAGE-BANDWIDTH` within tolerance (segment mode only, FR-012).
  Each rule is tagged with source = `apple-authoring` and the spec section it derives from (FR-008).
- **Rationale**: Clarification #5 added Apple Authoring checks but FR-013 forbids decoding —
  decode-dependent rules (actual codec profile, frame rate of encoded video, loudness) are excluded
  by the spec itself. The rule registry design makes the exact rule list extensible; the definitive
  enumeration lands in the rules source files with IDs, and the report schema carries rule IDs.
- **Alternatives considered**: Full authoring-spec coverage including media inspection (violates
  FR-013); skipping authoring checks entirely (rejected by user — Clarification #5).

## 6. CLI Argument Parsing — swift-argument-parser

- **Decision**: Use `apple/swift-argument-parser` for the executable target. Only external
  dependency of the package.
- **Rationale**: Declarative subcommands/flags/help; Apple-maintained; tiny; standard in Swift CLI
  tooling. Hand-rolling `CommandLine.arguments` parsing reinvents validation, help text, and
  completion for zero benefit (Constitution III: prefer already-adopted, justified dependencies).
- **Alternatives considered**: Manual parsing (error-prone help/UX duplication); other CLI libs
  (less maintained than the Apple package).

## 7. Interactive Playlist Checklist (FR-018) — custom terminal UI, no dependency

- **Decision**: Minimal interactive multi-select rendered with ANSI escapes + raw-mode termios input
  (arrow keys + space to toggle, enter to confirm, all pre-selected). When stdout is not a TTY or
  `--non-interactive`/`--select`/`--all` is passed, skip the prompt: default = all playlists, or the
  selection given via flags.
- **Rationale**: One small, self-contained component; spec demands checkbox interaction *and*
  unattended operation (FR-018). A TUI framework dependency for one prompt violates Constitution III.
- **Alternatives considered**: TUI libraries (heavy dependency for one screen); numbered-list
  text prompt (worse UX than requested "checkbox", kept as automatic fallback when raw mode is
  unavailable).

## 8. Test Strategy — Swift Testing + fixture corpus + scripted transport stubs (no local server)

- **Decision**: Swift Testing (`@Test`, `#expect`) for all targets; test development follows the
  repository's `unit-testing.md` guidelines (mandatory). Two layers:
  1. **Unit/conformance**: a `Fixtures/` corpus of `.m3u8` files — known-conformant playlists
     (modeled on Apple reference streams) and seeded-violation playlists, one violation family per
     fixture, asserting exact finding IDs/severities/line numbers (drives SC-002).
  2. **Integration**: no local socket server. The core depends on a `StreamFetching` abstraction
     (fetch URL → body bytes + full response metadata); tests inject a scripted stub that plays
     scenario timelines fully in-process — VOD, healthy live (sliding window advanced by the manual
     test clock), stalling live, sequence-regressing live, redirect chains, slow/erroring endpoints
     — exercising the full session engine including archive output (drives SC-003/SC-004 behavior at
     test scale, deterministically).
  The URLSession-backed `StreamFetching` adapter stays thin; its metrics/redirect capture is
  verified through the manual quickstart scenarios against real streams.
- **Rationale**: Deterministic and fast (no ports, no socket flakiness in CI); reuses the same
  injection seam the engine already needs for the test clock; conformance corpus makes Test-First
  concrete per rule (Constitution II).
- **Alternatives considered**: `NWListener` in-process HTTP server (dropped by user decision —
  socket layer adds nondeterminism and still wouldn't exercise URLSession adapter internals);
  SwiftNIO test server (heavyweight dependency only for tests); `URLProtocol` stubbing (URLSession
  does not synthesize `URLSessionTaskMetrics` for custom protocols, so the metrics path can't be
  validated that way; remains a fallback for adapter smoke tests); hitting real public streams in CI
  (non-deterministic, network-flaky, impolite).

## 9. Concurrency Model — actor session engine, per-playlist monitor tasks, injectable clock

- **Decision**: `ValidationSession` is an actor owning session state (findings, archive index,
  playlist registry). Live monitoring runs one structured task per selected playlist inside a
  `TaskGroup`, each sleeping on an injectable `Clock` (`ContinuousClock` in production, manual clock
  in tests). Findings and status updates flow to the CLI via `AsyncStream`. Archive writes happen on
  a dedicated serial executor to keep ordering deterministic.
- **Rationale**: Maps 1:1 to the domain (independent cadences per playlist), cancellation-safe
  (Ctrl-C → cancel group → graceful summary, FR-015), data-race-free under Swift 6 strict checking;
  injectable clock is what makes SC-003-style cadence behavior unit-testable.
- **Alternatives considered**: GCD timers (no structured cancellation, races with Swift 6);
  single polling loop multiplexing all playlists (simpler but couples cadences and degrades
  per-playlist timing accuracy).

## 10. Report & Archive Formats

- **Decision**: Session folder layout (detailed in data-model.md): artifacts stored verbatim with a
  JSON metadata sidecar per request (timestamps, remote IP, headers, status, redirect chain);
  findings stream appended as JSON Lines during the session (crash-safe, FR "interrupted session"
  edge case); end-of-session `report.json` (schema: contracts/session-report.schema.json,
  `schemaVersion` field from 1) plus human-readable `report.md` (FR-016).
- **Rationale**: JSON Lines survives aborts without truncating a monolithic JSON document; sidecars
  keep artifacts byte-exact (no envelope wrapping); versioned schema honors Constitution V.
- **Alternatives considered**: SQLite session store (queryable but breaks "open the folder and read
  the evidence" workflow and adds schema/dependency weight); wrapping artifacts in JSON envelopes
  (destroys byte-exactness of evidence).

## 11. Disk-Space Warning (FR-010)

- **Decision**: Check `volumeAvailableCapacityForImportantUsage` on the session folder's volume
  before session start and periodically during live monitoring (every archive flush batch); warn at
  < 5 GB free (warning finding + status banner), stop archiving cleanly with an error finding at
  < 500 MB (edge case "storage failure": alert immediately, stop cleanly).
- **Rationale**: First-party API, cheap to poll; thresholds sized against the ~1–2 GB/24 h archive
  growth accepted in Clarification #3.
- **Alternatives considered**: React only to write failures (risks corrupt/partial final state and
  late warning — spec demands proactive warning).
