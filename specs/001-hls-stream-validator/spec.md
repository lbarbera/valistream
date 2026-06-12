# Feature Specification: HLS Stream Validator

**Feature Branch**: `001-hls-stream-validator`

**Created**: 2026-06-12

**Status**: Draft

**Input**: User description: "HLS stream validator tool. Why: help troubleshooting issues in apps that
consume given HLS streams. Input: .m3u8 master playlist URL. Should do: validates master playlist
against HLS official specs; loads all media playlists & validates them; (if Live stream) follows Live
stream re-fetch interval and re-validates audio/video/subtitles playlists against specs and for correct
continuity. Optionally, downloads segments and validates their size against indicated bandwidth. Does
not decode segments (DRM is out of scope). Basically the tool starts and behaves almost like native
iOS/tvOS AVPlayer but without actually playing segments, but instead analyzes stream infos. Output:
status & findings while tool is active. Findings categorized. All downloaded artefacts (playlists,
segments) are saved into disk (folder per session) with full request/response info (timestamps, ip
address, headers, etc.)"

## Clarifications

### Session 2026-06-12

- Q: How should the tool handle Low-Latency HLS (LL-HLS) streams? → A: Detect and report LL-HLS
  attributes as informational findings; validate the standard-latency parts normally; deep LL-HLS
  semantics (partial segment continuity, blocking reloads, preload hints) are out of scope for this
  feature.
- Q: What interaction form should the validator take? → A: Command-line tool — sessions started,
  observed, and stopped from the terminal; scriptable for automation. A GUI may wrap the same engine
  in a future feature.
- Q: How should the session archive handle artifact growth during long live sessions? → A: Store
  every refresh verbatim — no deduplication, no rotation; the tool warns when available disk space
  runs low. Archive size (roughly 1–2 GB per 24 h of live monitoring) is accepted for full
  evidentiary fidelity.
- Q: When segment validation mode is enabled, which segments are downloaded and checked? → A: All
  referenced segments — live: every newly published segment across all monitored playlists; VOD:
  every segment of every variant. Complete audit; download volume is the user's informed opt-in.
- Q: Should Apple HLS Authoring Specification checks be part of the validation baseline? → A: Yes —
  playlist-observable Apple HLS Authoring Specification requirements are validated alongside
  RFC 8216; authoring checks that would require decoding media content remain out of scope.
- Q: Can the user choose which media playlists are monitored in a session? → A: Yes — after the
  master playlist is validated, the discovered media playlists are presented as an interactive
  checklist with all entries pre-selected; live monitoring and segment downloads cover only the
  selected playlists. Initial one-shot validation always covers all referenced playlists.
  Non-interactive runs bypass the prompt (default: all, or a pre-specified selection).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - On-Demand Stream Structure Validation (Priority: P1)

An app developer or QA engineer is troubleshooting a playback problem reported against an HLS stream.
They start a validation session by providing the stream's master playlist URL. The tool fetches the
master playlist, validates it against the official HLS specification and the Apple HLS Authoring
Specification, then fetches every referenced media playlist (video variants, audio renditions,
subtitles) and validates each one. While the session
runs, the user sees live status (what is being fetched, findings so far). At the end they receive a
summary of categorized findings that either confirms the stream is conformant or pinpoints exactly
what is wrong and where.

**Why this priority**: This is the core value of the product — a single validation pass that replaces
manual playlist inspection. Without it nothing else matters; with it alone the tool is already useful
for VOD streams and one-shot checks of live streams.

**Independent Test**: Run a session against a known-conformant VOD stream and against a deliberately
broken playlist; verify the first reports no errors and the second reports the seeded violations with
their locations.

**Acceptance Scenarios**:

1. **Given** a conformant VOD master playlist URL, **When** a validation session runs, **Then** the
   master playlist and every referenced media playlist are fetched and validated, and the session ends
   with a summary reporting zero error findings.
2. **Given** a master playlist containing a specification violation (e.g., a required attribute is
   missing), **When** the session runs, **Then** the violation is reported as an error finding that
   identifies the affected playlist, the offending line or tag, and the specification rule violated.
3. **Given** a URL that is unreachable or returns content that is not a playlist, **When** the session
   runs, **Then** the session ends gracefully with a delivery-category error finding describing the
   failure (no crash, no silent exit).
4. **Given** a media playlist URL provided directly (not a master), **When** the session runs,
   **Then** the tool detects the playlist type and validates it as a standalone media playlist.
5. **Given** a running session, **When** the user observes the tool, **Then** current activity and a
   running count of findings by severity are visible at all times.

---

### User Story 2 - Live Stream Monitoring and Continuity Validation (Priority: P2)

A broadcast or operations engineer suspects an intermittent fault in a live stream. They start a
session against the live master playlist. After initial validation, the tool presents the discovered
media playlists as a checklist (all pre-selected) so the engineer can narrow monitoring to the
playlists under suspicion, or simply accept the default of all. The tool detects that the stream is
live and keeps each selected media playlist under observation, re-fetching it at the refresh cadence
the HLS specification prescribes (derived from the playlist's target duration), exactly as a real
player would — but for all selected renditions at once. On every refresh it re-validates the playlist and checks continuity against the
previously observed state. The session runs until the engineer stops it, accumulating a timeline of
findings that reveals intermittent faults (stalls, sequence errors, broken updates) that a one-shot
check would miss.

**Why this priority**: Live streams are where the hardest troubleshooting happens and where the
"behaves like a player" promise pays off. Depends on User Story 1's validation core, hence P2.

**Independent Test**: Run a session against a healthy live stream and verify periodic refreshes occur
on cadence with no error findings; then run against a simulated faulty live stream (stalled playlist,
sequence regression) and verify the corresponding continuity findings appear.

**Acceptance Scenarios**:

1. **Given** a live stream URL, **When** the session starts, **Then** the tool identifies the stream
   as live and begins re-fetching every selected media playlist at the specification-defined refresh
   interval, re-validating each refresh.
2. **Given** a monitored media playlist that stops receiving updates, **When** the playlist fails to
   change within the expected update window, **Then** a staleness finding is raised stating how long
   the playlist has been stale.
3. **Given** a refresh in which the media sequence number decreases, or a previously published segment
   entry changes retroactively, **When** the refresh is validated, **Then** a continuity error finding
   is raised identifying the playlist and the nature of the inconsistency.
4. **Given** a stream that introduces discontinuity markers (e.g., ad insertion), **When** refreshes
   are validated, **Then** the discontinuities are recorded as informational findings and continuity
   tracking continues correctly across them.
5. **Given** a running live session, **When** the user stops it, **Then** the session ends gracefully
   and produces a complete summary covering the entire monitored period.
6. **Given** the playlist selection step, **When** the engineer deselects some playlists, **Then**
   only the remaining selected playlists are monitored, and the session report records which
   playlists were monitored and which were excluded by choice.

---

### User Story 3 - Session Artifact Archive (Priority: P3)

A troubleshooter needs evidence to share with a CDN vendor, an encoder team, or an internal ticket.
Every validation session automatically produces a dedicated folder on disk containing every artifact
the tool downloaded — every copy of every playlist (including each live refresh) and any downloaded
segments — each accompanied by full request/response details: request and response timestamps, the
server IP address contacted, request headers sent, response headers and status code received. The
folder, together with the findings report, is a self-contained record of what the stream actually
served during the session.

**Why this priority**: The archive turns findings into shareable proof and enables offline analysis,
but the tool already delivers troubleshooting value on screen without it.

**Independent Test**: Run any session, then inspect the session folder and verify every network
request the tool reported corresponds to a stored artifact with complete request/response metadata.

**Acceptance Scenarios**:

1. **Given** a completed session, **When** the user opens the session folder, **Then** it contains
   every downloaded playlist (every refresh stored separately) and any downloaded segments.
2. **Given** any stored artifact, **When** its metadata record is inspected, **Then** it includes
   request timestamp, response timestamp, server IP address, request headers, response headers, and
   response status code.
3. **Given** a session interrupted mid-flight (user abort or fatal network failure), **When** the
   session folder is inspected, **Then** all artifacts collected up to the interruption are present
   and readable.
4. **Given** a completed session, **When** the user opens the session folder, **Then** the categorized
   findings report and session summary are stored alongside the artifacts.

---

### User Story 4 - Segment Bandwidth Verification (Priority: P4)

An engineer suspects that the stream's declared bandwidth values are wrong — a common cause of player
buffering or wrong-variant selection. They enable the optional segment validation mode for a session.
The tool then also downloads the media segments referenced by the playlists and compares each
segment's actual size (relative to its duration) against the bandwidth the master playlist declared
for that variant. Segments whose measured size implies a bitrate exceeding the declared values beyond
the configured tolerance are flagged. Segment content is never decoded — encrypted (DRM) segments are
handled as opaque data and still size-checked.

**Why this priority**: Valuable diagnostic, but optional by the user's own description, adds
significant download volume, and depends on all prior stories.

**Independent Test**: Enable segment mode against a stream whose actual segment bitrates are known;
verify segments exceeding declared bandwidth beyond tolerance are flagged and conformant segments are
not.

**Acceptance Scenarios**:

1. **Given** segment validation is enabled, **When** the session runs, **Then** referenced segments
   are downloaded and each segment's measured size is evaluated against the declared bandwidth for its
   variant, flagging deviations beyond the configured tolerance.
2. **Given** an encrypted (DRM-protected) stream with segment validation enabled, **When** segments
   are downloaded, **Then** no decoding or decryption is attempted, size checks still run, and the
   presence of encryption is recorded as an informational finding.
3. **Given** a segment download that fails (e.g., not found, timeout), **When** the failure occurs,
   **Then** a delivery error finding is raised identifying the segment address and failure reason.
4. **Given** a session started without enabling segment validation, **When** the session runs,
   **Then** no segment bodies are downloaded.

---

### Edge Cases

- Provided URL is unreachable (DNS failure, connection refused, TLS error, timeout): session reports a
  delivery error finding and ends gracefully.
- Response is not a playlist (HTML error page, binary data, wrong content type): reported as an error
  finding with the received content preserved in the session archive.
- Redirects: every redirect hop is followed, recorded with full request/response metadata, and the
  final address is used for resolving relative references.
- Master playlist references that cannot be resolved (broken rendition group references, dead media
  playlist links): each reported as an error finding naming the broken reference.
- Live playlist regresses (media sequence decreases) or previously published segments are removed
  earlier than the specification allows: continuity error findings.
- Target duration or other structural properties change mid-stream: flagged as findings on the refresh
  where the change is observed.
- One rendition stalls while others advance (renditions drift out of sync): staleness finding for the
  stalled playlist while monitoring of the others continues.
- Very large master playlists (dozens of variants/renditions): all playlists are still monitored;
  status output stays readable by aggregating per-playlist state.
- Tokenized/expiring URLs whose credentials lapse mid-session: subsequent fetch failures are recorded
  as delivery findings (re-authentication is out of scope).
- Storage failure while writing artifacts (disk full, permission denied): the user is alerted
  immediately and the session stops cleanly rather than continuing with an incomplete archive.
- User aborts a session mid-flight: summary is produced for the observed period; collected artifacts
  remain on disk.
- User deselects every media playlist at the selection step: the session delivers the initial
  one-shot validation results and ends, noting that no playlists were chosen for monitoring.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tool MUST accept an HLS playlist URL (HTTP or HTTPS, `.m3u8`) as the input that
  starts a validation session.
- **FR-002**: The tool MUST detect whether the provided playlist is a master playlist or a media
  playlist and validate it accordingly; a directly provided media playlist is validated standalone.
- **FR-003**: The tool MUST validate the master playlist against the validation baseline — the
  official HLS specification (RFC 8216 and its published updates) plus the playlist-observable
  requirements of the Apple HLS Authoring Specification — covering syntax, required tags and
  attributes, attribute value constraints, internal cross-references (e.g., rendition group references
  must resolve), and authoring requirements observable from playlist content (e.g., variant ladder
  composition, declared attribute completeness).
- **FR-004**: The tool MUST enumerate and fetch every media playlist referenced by the master playlist
  — video variants, audio renditions, subtitle renditions, and I-frame playlists — and validate each
  against the validation baseline defined in FR-003.
- **FR-005**: The tool MUST classify the stream as live, event (append-only live), or on-demand
  from playlist properties and report the classification to the user. Event streams are monitored
  with the same cadence rules as live streams.
- **FR-006**: For live streams, the tool MUST re-fetch every monitored media playlist at the refresh
  cadence defined by the HLS specification (derived from the playlist's target duration) and
  re-validate it on every refresh, mirroring the request pattern of a real player while covering all
  selected renditions simultaneously (all of them by default).
- **FR-007**: For live streams, the tool MUST validate continuity between consecutive refreshes of
  each media playlist, including: media sequence numbers never decrease; published segment entries are
  not retroactively altered; segments are not removed earlier than the specification allows (for
  event streams, which are append-only, any removal of a previously published segment is a
  continuity error); discontinuity tracking remains consistent; and a playlist that fails to update
  within its expected update window is flagged as stale, including the stale duration.
- **FR-008**: Every finding MUST carry a severity (error, warning, info) and a category (master
  playlist, media playlist, continuity, delivery/network, segment), and MUST identify the affected
  resource, the time it was observed, and the rule or expectation violated, including which standard
  the rule comes from (HLS specification vs. Apple HLS Authoring Specification).
- **FR-009**: While a session is active, the tool MUST continuously present session status: current
  activity, per-playlist monitoring state, and running counts of findings by severity.
- **FR-010**: The tool MUST save every downloaded resource (every playlist copy, including each live
  refresh, and any downloaded segments) into a dedicated per-session folder on disk, verbatim and
  without deduplication or rotation, and MUST warn the user when available disk space runs low.
- **FR-011**: Each stored artifact MUST be accompanied by its full request/response record: request
  timestamp, response timestamp, server IP address contacted, request headers, response headers, and
  response status code.
- **FR-012**: The tool MUST offer an optional, per-session segment validation mode (disabled by
  default) which downloads referenced media segments and flags any segment whose measured size implies
  a bitrate exceeding the declared bandwidth for its variant beyond a configurable tolerance
  (default 10%). Comparison basis follows Apple authoring semantics: the largest implied segment
  bitrate is checked against the variant's declared peak bandwidth (BANDWIDTH), and the average
  implied bitrate across observed segments against the declared average bandwidth
  (AVERAGE-BANDWIDTH) when present. Coverage when enabled is complete within the selected playlists: for on-demand
  streams every segment of every selected playlist; for live streams every newly published segment
  across all monitored playlists.
- **FR-013**: The tool MUST NOT decode, decrypt, or play media content; encrypted segments are treated
  as opaque data, and the presence of content protection is reported as an informational finding.
- **FR-014**: The tool MUST record network-level failures (timeouts, HTTP error statuses, TLS
  failures, redirect loops) as delivery findings and continue the session where possible rather than
  terminating on the first failure.
- **FR-015**: A session MUST end automatically when validation of an on-demand stream completes, and
  for live streams MUST run until the user stops it or an optional user-set time limit elapses; in all
  cases the tool MUST produce an end-of-session summary of all findings.
- **FR-016**: The end-of-session findings report and summary MUST be saved into the session folder in
  both a human-readable form and a structured, machine-readable form.
- **FR-017**: When a stream uses Low-Latency HLS extensions, the tool MUST detect and report their
  presence as informational findings and MUST continue validating the standard-latency aspects of the
  stream; it MUST NOT attempt low-latency-specific request patterns or validate low-latency-specific
  semantics (partial segments, blocking reloads, preload hints).
- **FR-018**: After initial validation, the tool MUST let the user choose which of the discovered
  media playlists are monitored (and, when segment mode is on, segment-checked) for the rest of the
  session, presented as an interactive checklist with every playlist pre-selected; initial one-shot
  validation always covers all referenced playlists regardless of selection. Non-interactive
  (unattended) sessions MUST be able to bypass the prompt, either accepting the default of all
  playlists or supplying a selection up front. The session report MUST record which playlists were
  monitored and which were excluded by choice.

### Key Entities

- **Validation Session**: One run of the tool against one stream URL; owns configuration (segment mode
  on/off, time limit, playlist selection — all by default), start/end times, all findings, and the
  artifact folder.
- **Playlist**: A fetched master or media playlist; carries its type, source address, declared
  properties, and validation results. Media playlists belong to the master that referenced them.
- **Playlist Refresh**: One observation of a media playlist at a point in time during live monitoring;
  consecutive refreshes of the same playlist are compared for continuity.
- **Segment**: A media segment referenced by a media playlist; when segment mode is on, carries its
  measured size and the bandwidth comparison outcome.
- **Finding**: A single validation observation with severity, category, affected resource, observation
  time, violated rule/expectation, and human-readable description.
- **Artifact Record**: A stored copy of one downloaded resource plus its full request/response
  metadata (timestamps, server IP, headers, status).
- **Session Report**: The end-of-session summary aggregating findings by severity and category,
  stored with the artifacts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A full one-shot validation (master plus all media playlists) of a stream with up to 20
  media playlists completes within 30 seconds on a normally responsive network.
- **SC-002**: Against a conformance test corpus of seeded specification violations, the tool detects
  100% of the violations covered by its documented rule set, and raises zero error-severity findings
  against known-conformant reference streams.
- **SC-003**: A live monitoring session sustains at least 24 hours of continuous operation, completing
  at least 99% of scheduled playlist refreshes on cadence.
- **SC-004**: 100% of network requests issued during a session have a complete artifact record
  (stored resource plus full request/response metadata) in the session folder.
- **SC-005**: An engineer can identify the root cause of common stream defects (stale playlist, broken
  rendition reference, bandwidth mismatch) from the findings report alone — without manually opening
  playlist files — in under 5 minutes.
- **SC-006**: Every finding is traceable: 100% of findings identify the affected resource, observation
  time, and the violated rule or expectation.

## Assumptions

- "HLS official specs" means RFC 8216 and its published updates **plus** the Apple HLS Authoring
  Specification. Authoring checks are limited to what is observable from playlists and segment
  metadata without decoding media content; decode-dependent authoring requirements (codec profiles,
  frame rates, loudness, etc.) are out of scope.
- In live mode the tool monitors media playlists simultaneously — by default **all** of them, a
  superset of a single player's behavior (a player follows one variant at a time); the user may
  narrow monitoring to a chosen subset per session. The "behaves like a native player" description is
  interpreted as matching per-playlist request cadence and request patterns, not variant selection.
- The tool is a command-line application: the user starts a session with a URL, observes live status
  in the terminal, and can stop the session at any time (e.g., interrupt key). Exit behavior and
  output must be automation-friendly so sessions can run unattended (scripts, scheduled checks).
- The provided URL carries any required access credentials (e.g., signed tokens) as-is; the tool does
  not manage authentication, refresh tokens, or DRM license exchanges.
- Segment validation mode is off by default and enabled per session; bandwidth deviation tolerance
  defaults to 10% and is configurable.
- Session artifacts are stored locally on the user's machine; retention and cleanup are the user's
  responsibility; nothing is uploaded anywhere. Long live sessions produce large archives (roughly
  1–2 GB and hundreds of thousands of files per 24 h of playlist monitoring) — accepted in exchange
  for a complete evidence trail.
- One session validates one stream URL; validating multiple streams means running multiple sessions.
- Scope boundaries: no media decoding or playback, no DRM decryption or license handling, no support
  for non-HLS protocols (e.g., DASH), no deep Low-Latency HLS validation (detected and reported only),
  no server-side remediation — the tool observes and reports only.
