# Feature Specification: Readable Output and Onboarding

**Feature Branch**: `main`

**Created**: 2026-06-14

**Status**: Draft

**Input**: User description: "Increase stdout and report readability across quiet, normal, and verbose modes through meaningful color and emphasis, message grouping, whitespace, and natural language. Make output easy to skim and navigate. Rewrite README.md as a complete GitHub-style onboarding guide with rationale, operation, installation, options, and realistic examples. Ship as 0.4.0."

## Clarifications

### Session 2026-06-15

- Q: Should normal mode persist a result for every successful refresh? → A: Yes; persist one concise
  result for every refresh, and add timestamps to all human-readable terminal messages and report
  entries so trouble can be correlated in time.
- Q: Which timestamp formats and timezone should human-readable output use? → A: Terminal messages use
  compact local time with milliseconds (`[HH:mm:ss.SSS]`); report entries use full local ISO 8601 with
  milliseconds and numeric UTC offset.
- Q: How much chronological activity should the human-readable report include? → A: Include an
  incident-focused timeline of findings, failures, and playlist unavailable, recovered, added, removed,
  or identity-changed events; exclude routine successful refreshes.
- Q: Should timestamps represent event occurrence or message rendering time? → A: Timestamp each event
  when it occurs and preserve that same instant in terminal output and reports.
- Q: How should findings appear across severity sections and the incident timeline? → A: Keep complete
  finding details grouped by severity; use compact chronological timeline entries that link to those
  findings instead of duplicating their messages and evidence.
- Q: Which playlist lifecycle changes belong in the incident timeline? → A: Include playlist
  unavailable, recovered, added, removed, and identity-changed events.
- Q: How are incident timeline events ordered when their timestamps are equal? → A: Preserve recorded
  event sequence.
- Q: Which human-readable surfaces should show the one-time playlist information block? → A: Show it
  in normal and verbose terminal output and in the Markdown report; keep quiet terminal output
  unchanged.
- Q: How should playlist protection be classified in the information block? → A: Show `None`,
  `Encrypted (AES-128)`, or `DRM (<key format>)` from declared key metadata; show protection for every
  media playlist individually and summarize session protection declared by the master playlist.
- Q: Should playlist information detail vary by human-readable surface? → A: No; show the same
  comprehensive engineering summary in normal and verbose terminal output and in the Markdown report.
- Q: How should media-playlist segment duration be summarized? → A: Show the declared target duration
  plus the observed median and minimum–maximum segment durations from the first loaded snapshot.
- Q: Should a media-playlist block include metadata inherited from the master playlist? → A: No; show
  only facts declared by that media playlist. Master-derived resolution, codec, bandwidth, language,
  and role remain in the master block.
- Q: What concrete color palette should styled terminal output use? → A: A restrained, terminal-safe
  8/16-color ANSI palette — red for errors, yellow for warnings, green for success, a cyan accent for
  identifiers and paths, dim gray for secondary metadata, and bold (not color) for headings; no
  reliance on 256-color/truecolor or on a specific terminal background.
- Q: What status-marker glyph style should the terminal use? → A: Restrained monochrome Unicode text
  symbols colored by severity, each paired with a readable label, falling back to ASCII markers
  (`[OK]`/`[WARN]`/`[ERR]`); colorful emoji are excluded from terminal output because their variable
  width and inconsistent glyph support break column alignment and compatibility.
- Q: How wide should color and emphasis be applied per line? → A: Whole-line tint — each persistent
  result and finding line is tinted by its severity color, while structural context (bold headings,
  cyan identifiers, dim metadata and paths) keeps token-scoped styling.
- Q: How rich should the Markdown report be? → A: Clean GitHub-professional structure (linked section
  navigation, tables, code spans, emphasis) plus some color via GitHub alert/callout blocks
  (`> [!WARNING]`, `> [!CAUTION]`) and emoji severity icons; every styled element degrades to readable
  plain text, and shields-style badges and nonstandard HTML are excluded.
- Q: How should the README convey the new colored/readable output to first-time visitors? → A: Text
  excerpts only; no binary or animated visual assets (screenshots, GIFs, terminal casts), because
  GitHub renders no ANSI color inside code blocks and plain text is the accessibility/redirection
  baseline.
- Q: What URL should the quick-start copy-paste command use, given real/expiring URLs cannot be
  committed? → A: A stable, credential-free public HLS test stream so the first run works on paste,
  but only after verifying it runs cleanly with valistream `0.4.0` (a dead link or a stream that
  errors would be bad advertising); generic command syntax elsewhere MAY use a placeholder URL.
- Q: Should the README use status badges, and which? → A: Yes; a minimal set of shields-style badges
  backed by verifiable facts — license, latest release/version, platform/Swift, and code coverage —
  near the top. Every badge MUST reflect a real, current value (no broken or stale badge); the
  coverage badge requires a verifiable coverage source. The report-level badge exclusion in FR-027a
  applies to the generated session report only, not to the README.
- Q: What verified installation/distribution method should the README document as primary? → A: A
  prebuilt `valistream-cli.zip` CLI artifact published on each GitHub Release alongside the
  auto-generated source archive; users download and run it directly. The verified source build remains
  the secondary path, and channels not actually published (e.g., package managers) are marked
  unsupported rather than documented as available.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Follow a Live Session at a Glance (Priority: P1)

As an operator watching a validation session, I can immediately distinguish setup, playlist activity,
findings, and the final result without reading every line or tracking repeated low-level messages.

**Why this priority**: The primary interface is the live terminal. If normal output remains difficult to
scan, the tool cannot reliably communicate stream health even when validation itself is correct.

**Independent Test**: Run a session containing several playlists, successful refreshes, and one warning.
The operator can identify the current phase, latest playlist result, warning, evidence path, and overall
session state from the normal output without enabling verbose mode.

**Acceptance Scenarios**:

1. **Given** a normal interactive session, **When** discovery and validation progress, **Then** output is
   divided into clearly named groups with consistent spacing, indentation, and visual hierarchy.
2. **Given** a successful playlist refresh, **When** its result is printed, **Then** normal output shows
   one concise persistent result for that refresh rather than separate request, comparison, storage,
   validation, and duplicate success messages, and the result includes its timestamp.
3. **Given** a refresh with warnings or errors, **When** its result is printed, **Then** the summary,
   findings, and evidence form one adjacent block that is not interrupted by unrelated playlist output.
4. **Given** a session that completes or is interrupted, **When** output ends, **Then** a visually
   prominent summary states the outcome, finding counts, elapsed time, and report location.
5. **Given** a playlist is loaded for the first time, **When** normal or verbose output describes it,
   **Then** one human-readable playlist information block appears and is not repeated on later
   refreshes.
6. **Given** a stream mixes protected video or audio with unprotected subtitle playlists, **When**
   playlist information is shown, **Then** each media playlist states its own protection status and
   the master information summarizes the protection types declared by the stream.

---

### User Story 2 - Find Actionable Problems Immediately (Priority: P2)

As an operator or reviewer, I can scan quiet output or the human-readable report and move directly from
a warning or error to its affected playlist and evidence without searching through routine activity.

**Why this priority**: Findings are the reason the tool is run. They must remain prominent and
actionable regardless of whether the user is watching a terminal, reading captured output, or opening a
report later.

**Independent Test**: Validate a stream with multiple severities and open both quiet output and the
Markdown report. Every warning and error can be located quickly, understood without internal
implementation knowledge, and traced to its evidence.

**Acceptance Scenarios**:

1. **Given** quiet mode, **When** routine refreshes succeed, **Then** routine progress and success
   messages are omitted while every warning, error, required notice, and final summary remains.
2. **Given** several findings for one playlist refresh, **When** they are displayed, **Then** they are
   grouped under one playlist/snapshot context with severity, message, and evidence clearly separated.
3. **Given** a Markdown report with findings, **When** a reader opens it, **Then** the overall result and
   highest-severity findings appear before lower-priority detail, with stable section navigation and
   timestamps that support correlation with terminal activity and archived evidence.
4. **Given** a session with findings, failures, or a playlist becoming unavailable, recovering, being
   added or removed, or changing identity, **When** a reader opens the Markdown report, **Then** those
   events appear in one chronological incident timeline while routine successful refreshes are omitted.
5. **Given** a finding appears in the incident timeline, **When** a reader follows its reference,
   **Then** they reach the complete finding in its severity section without duplicated finding detail.
6. **Given** color and text styling are unavailable, **When** the same output is viewed, **Then** labels,
   symbols, indentation, and wording preserve the complete meaning.

---

### User Story 3 - Diagnose Deeply Without Losing Context (Priority: P3)

As a developer or advanced operator using verbose mode, I can inspect request, validation, comparison,
archive, and scheduling details while still seeing the same clear primary results as normal mode.

**Why this priority**: Verbose output must retain diagnostic depth, but its extra detail should support
the investigation instead of burying the playlist outcome.

**Independent Test**: Compare normal and verbose captures from the same scripted session. Verbose
contains every required diagnostic category, groups each detail with the relevant operation, and leaves
the primary status and finding blocks easy to identify.

**Acceptance Scenarios**:

1. **Given** verbose mode, **When** a playlist refresh occurs, **Then** diagnostic lines are nested under
   a clear playlist/snapshot context and use consistent category labels.
2. **Given** verbose mode with many successful operations, **When** output is reviewed, **Then** secondary
   metadata is visually subordinate to outcomes, warnings, and errors.
3. **Given** normal and verbose output for the same run, **When** they are compared, **Then** verbose adds
   diagnostic detail without changing the reported result, evidence, reports, or exit status.

---

### User Story 4 - Start Using Valistream from the README (Priority: P4)

As a first-time user, I can understand why Valistream exists, determine whether my environment is
supported, install it through a verified path, run my first validation, choose the right output mode,
and locate the generated evidence without outside guidance.

**Why this priority**: Readable runtime output has limited value if users cannot install the tool,
understand its workflow, or interpret its options and artifacts correctly.

**Independent Test**: Give the README to a user unfamiliar with the repository. Using only that file,
the user can choose a supported installation method, run a validation, explain the main output modes,
and find the session report and playlist evidence.

**Acceptance Scenarios**:

1. **Given** a new visitor, **When** they open the README, **Then** they first see a concise description,
   the problem the tool solves, key capabilities, and a minimal working example.
2. **Given** a user ready to install, **When** they read the installation section, **Then** supported
   platforms, prerequisites, verified installation methods, source-build steps, and unsupported
   platforms are stated explicitly.
3. **Given** a user choosing options, **When** they read the command reference, **Then** every public
   option has its purpose, value format, default behavior, important interactions, and an example where
   useful.
4. **Given** a user comparing output modes, **When** they read the examples, **Then** realistic quiet,
   normal, verbose, structured-stream, and report excerpts demonstrate when each is appropriate.

### Edge Cases

- A session has no findings; the success state remains obvious without repetitive success messages.
- Many playlists refresh concurrently; one playlist's result and findings do not become interleaved with
  another playlist's result block.
- A refresh produces many findings; the block remains navigable without hiding or silently collapsing
  findings.
- Playlist IDs, evidence paths, messages, or roster URLs exceed the terminal width.
- Output is viewed at narrow and common terminal widths, redirected to a file, piped to another
  process, or displayed with styling disabled.
- The terminal has limited color or character support; no essential meaning depends on a color,
  glyph, cursor movement, or text weight.
- A session fails before discovery, loses network access, cannot write evidence, is interrupted during
  monitoring, or receives a second forced interruption.
- Quiet mode has no findings but must still communicate the final outcome and report location.
- Verbose mode emits rapid diagnostics; primary results and findings remain distinguishable.
- Structured output is requested; human-oriented grouping, blank lines, and styling do not enter the
  machine-readable stream.
- A Markdown viewer does not support advanced rendering; headings, links, tables, and code spans remain
  usable as plain text.
- A playlist becomes unavailable, recovers, is added or removed, or changes identity during a session;
  the incident timeline records the change at its occurrence time.
- A realistic test stream URL contains credentials or expiring query parameters; it is not committed,
  copied into documentation, or exposed in saved example output.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST ship as product version `0.4.0`, and user-facing version references MUST
  agree.
- **FR-002**: Existing validation rules, finding identifiers, playlist and snapshot identifiers,
  evidence resolution, selection behavior, report data, structured report schema and values, and exit
  codes MUST remain unchanged.
- **FR-003**: Human-readable output MUST use one shared information hierarchy covering session phases,
  playlist/snapshot context, operation results, findings, evidence, notices, and final summaries.
- **FR-004**: Human-readable terminal output MUST group related messages into adjacent blocks and use
  blank lines at meaningful phase or block boundaries without adding a blank line after every message.
- **FR-005**: A refresh result, its findings, and its evidence references MUST remain contiguous; output
  from another playlist MUST NOT appear inside that block.
- **FR-006**: Indentation, alignment, labels, capitalization, punctuation, status vocabulary, and units
  MUST be consistent across all human-readable output.
- **FR-007**: System messages MUST use concise natural language that leads with the useful outcome and
  avoids unexplained internal terminology.
- **FR-008**: Routine normal-mode success MUST be represented by one persistent result per playlist
  refresh; duplicate statements of the same success or validation outcome MUST be removed.
- **FR-008a**: Every human-readable terminal message in quiet, normal, and verbose modes MUST include a
  timestamp, including headings, progress, findings, notices, errors, shutdown messages, and summaries.
- **FR-008b**: Terminal timestamps MUST use the local timezone and the fixed compact form
  `[HH:mm:ss.SSS]` with 24-hour time and milliseconds.
- **FR-008c**: A human-readable message timestamp MUST represent when the underlying event occurred,
  not when the message was rendered, grouped, buffered, or written.
- **FR-009**: Visual styling MUST assign consistent semantic roles to headings, identifiers, success,
  progress, secondary metadata, warnings, errors, paths, and summaries.
- **FR-009a**: Styled terminal output MUST use a restrained, terminal-safe palette built on the
  standard 8/16 ANSI colors: errors red, warnings yellow, success green, identifiers and paths a cyan
  accent, secondary metadata dim gray, and headings bold rather than colored. The palette MUST NOT
  depend on 256-color or truecolor support and MUST remain legible without assuming a specific
  terminal background.
- **FR-010**: Color MUST reinforce meaning but MUST NOT be the only indicator of severity, state,
  hierarchy, or actionability.
- **FR-011**: Text emphasis MUST distinguish primary outcomes from secondary context while preserving
  the same wording and information when emphasis is unavailable.
- **FR-011a**: Each persistent result and finding line MUST be tinted as a whole by its severity color
  (success green, warning yellow, error red) so severity is scannable at a glance, while structural
  context lines (headings, identifiers, evidence paths, secondary metadata) retain token-scoped
  styling; when color is unavailable, the severity label and wording MUST still convey the same state.
- **FR-012**: Styling MUST be disabled for non-interactive output, `NO_COLOR`, `--no-color`, and limited
  terminal environments; plain output MUST contain no styling or cursor-control bytes.
- **FR-013**: Status markers MUST use restrained monochrome Unicode text symbols colored by severity,
  each accompanied by a readable text label, and MUST fall back to ASCII markers (`[OK]`, `[WARN]`,
  `[ERR]`) when Unicode cannot be displayed reliably. Colorful emoji MUST NOT be used in terminal
  output because their variable width and inconsistent glyph support break column alignment and degrade
  compatibility.
- **FR-014**: Long human-readable lines MUST wrap or continue with recognizable indentation so severity,
  playlist/snapshot identity, finding text, and evidence are not lost at common terminal widths.
- **FR-015**: Quiet mode MUST contain all warnings, errors, required fallback/failure notices, shutdown
  state, and the final summary, and MUST omit routine discovery, progress, successful refresh, and
  diagnostic messages.
- **FR-016**: In quiet mode, related findings MUST be grouped by playlist/snapshot context and each
  evidence reference MUST remain directly associated with its finding.
- **FR-017**: Normal mode MUST show session setup, the playlist roster, concise progress, one result per
  refresh, findings with evidence, playlist lifecycle notices, and the final summary.
- **FR-017a**: Normal and verbose terminal output MUST show one human-readable playlist information
  block when each playlist is first loaded and MUST NOT repeat that block on later refreshes; quiet
  terminal output MUST omit it.
- **FR-017b**: Each media-playlist information block MUST classify that playlist's declared protection
  as `None`, `Encrypted (AES-128)`, or `DRM (<key format>)`; the master-playlist block MUST use the same
  vocabulary to summarize session protection declared by the master playlist.
- **FR-017c**: Normal terminal output, verbose terminal output, and the Markdown report MUST present the
  same playlist-information fields and values; verbose mode MAY add separate diagnostics but MUST NOT
  be required to obtain any playlist-summary field.
- **FR-017d**: Each media-playlist information block MUST show the declared target duration and the
  observed median and minimum–maximum segment durations calculated from the playlist's first loaded
  snapshot; later refreshes MUST NOT revise the one-time block.
- **FR-017e**: A master-playlist information block MUST include the playlist ID and type, HLS version,
  independent-segments state, variant-stream count, unique referenced media-playlist count, alternate
  rendition counts by media type, I-frame stream count, distinct resolutions, distinct codec strings,
  declared bandwidth range, declared frame-rate range, and declared session-protection summary.
- **FR-017f**: A media-playlist information block MUST include the playlist ID and media-playlist type
  or live/event/video-on-demand state, HLS version, segment count, total listed duration, target
  duration, observed median and minimum–maximum segment durations, media-sequence and
  discontinuity-sequence values, discontinuity count, end-list state, independent-segments state,
  I-frames-only state, observed segment format or formats, byte-range usage, program-date-time
  availability, and that playlist's protection classification.
- **FR-017g**: A media-playlist information block MUST NOT copy resolution, codec, bandwidth,
  frame-rate, language, role, or other metadata solely from a parent master playlist; those values
  belong to the master-playlist block.
- **FR-017h**: Missing playlist-summary values MUST be shown as `Unknown` or `Not declared`, whichever
  accurately distinguishes unavailable observation from an omitted declaration; multiple observed
  values MUST be listed distinctly or labeled `Mixed` without silently selecting one.
- **FR-017i**: In styled terminal output, each playlist-information block MUST use the bold playlist ID
  as its header and visually subordinate detail as secondary text. Plain terminal output and the
  Markdown report MUST preserve the same labels, values, and grouping without relying on color.
- **FR-017j**: Playlist information MUST be divided into coherent groups separated by one empty line;
  fields within a group MUST remain adjacent, and unrelated playlist output MUST NOT interrupt a
  block.
- **FR-018**: Normal mode MUST omit request-level, rule-level, comparison, archive-write, and scheduling
  details unless they produce an actionable finding or failure.
- **FR-019**: Verbose mode MUST retain every diagnostic category promised by the existing verbosity
  contract and group each diagnostic with the relevant session phase or playlist/snapshot.
- **FR-020**: Verbose details MUST be visually subordinate to primary refresh results and findings, and
  each line MUST identify its diagnostic category unambiguously.
- **FR-021**: Verbosity MUST affect human-readable terminal detail only; it MUST NOT change findings,
  evidence, generated reports, structured output, or exit status.
- **FR-022**: The final terminal summary MUST state the overall outcome, elapsed time, processed or
  refreshed playlist count, warning and error totals, and paths to the session folder and primary
  human-readable report when available.
- **FR-023**: Fatal, usage, and operational failure messages MUST state what failed, the relevant
  context, and a practical corrective action when one is known, while preserving the existing
  stdout/stderr and exit-code contract.
- **FR-024**: The in-place heartbeat MUST remain a transient progress aid and MUST NOT overwrite,
  split, duplicate, or visually compete with persistent result and finding blocks.
- **FR-025**: The human-readable Markdown report MUST start with an outcome-focused summary and provide
  a stable, linked section order that makes findings, evidence, playlist legend, and session details
  directly navigable.
- **FR-025a**: Human-readable report entries for findings, playlist refreshes, playlist lifecycle
  events, failures, and session boundaries MUST include timestamps that allow a reader to correlate a
  problem with terminal output and archived evidence.
- **FR-025b**: Report timestamps MUST use the local timezone and full ISO 8601 form with date, 24-hour
  time, milliseconds, and numeric UTC offset.
- **FR-025c**: The Markdown report MUST include one chronological incident timeline containing every
  warning, error, operational failure, evidence-capture failure, shutdown/interruption event, and
  playlist unavailable, recovered, added, removed, or identity-changed event.
- **FR-025d**: Routine successful refreshes MUST NOT appear in the incident timeline; aggregate and
  per-playlist summaries MAY describe successful activity outside the timeline.
- **FR-025e**: When the same event appears in terminal output and a report, both representations MUST
  derive from the same recorded occurrence instant.
- **FR-025f**: Complete finding messages, severity, context, and evidence MUST appear once in
  severity-grouped finding sections; the incident timeline MUST represent each finding with a compact,
  timestamped entry that links to its complete finding entry.
- **FR-025g**: Incident timeline entries MUST be ordered by occurrence timestamp; entries with equal
  timestamps MUST preserve their recorded event sequence.
- **FR-025h**: The Markdown report MUST include the one-time information block for every loaded
  playlist.
- **FR-026**: Markdown findings MUST be organized so errors precede warnings and routine informational
  detail, while preserving every finding and its existing evidence reference.
- **FR-027**: The Markdown report MUST use headings, whitespace, tables, emphasis, and code spans
  consistently and MUST contain no terminal styling or cursor-control bytes.
- **FR-027a**: The Markdown report MAY add color through GitHub alert/callout blocks (e.g.,
  `> [!WARNING]`, `> [!CAUTION]`) and emoji severity icons so severity is scannable on rendering
  viewers; every such element MUST degrade to readable plain text (callouts to blockquotes, icons
  beside their text labels), and the report MUST NOT rely on shields-style badges or nonstandard HTML.
- **FR-028**: The structured JSON report, metadata files, findings log, and line-delimited structured
  status stream MUST preserve their existing data contracts and machine-readable formatting rules.
- **FR-029**: `README.md` MUST follow a recognizable GitHub project structure: project name and concise
  description, motivation, key capabilities, how it works, quick start, installation, usage, option
  reference, output modes, generated artifacts, realistic examples, exit codes, troubleshooting,
  limitations/platform support, and links to applicable project resources.
- **FR-029a**: The README MUST display a minimal set of shields-style status badges near the top,
  limited to badges backed by a verifiable fact: license, latest release/version, platform/Swift
  version, and code coverage. Every displayed badge MUST reflect a real, current value; a badge whose
  underlying fact cannot be verified MUST be omitted rather than shown stale or broken. The coverage
  badge requires a verifiable coverage source. The report-level prohibition on shields-style badges
  (FR-027a) governs the generated session report only and does not apply to the README.
- **FR-030**: README installation instructions MUST distinguish verified supported methods from
  unsupported or unavailable distribution methods and MUST include prerequisites and a verified source
  build path. The primary verified method MUST be downloading the prebuilt `valistream-cli.zip`
  artifact from GitHub Releases (published alongside the auto-generated source archive) and running it;
  the source build is the secondary verified path. Distribution channels not actually published (e.g.,
  Homebrew or other package managers) MUST be marked unsupported rather than presented as available.
- **FR-031**: README quick-start instructions MUST take a user from installation to a first validation
  and explain where to find the resulting report and evidence. The quick-start command MUST use a
  stable, credential-free public HLS test stream that runs as-is on paste; a placeholder URL form MAY
  be shown for generic command syntax.
- **FR-032**: README parameter documentation MUST match the `0.4.0` command help, including defaults,
  accepted value forms, mutually exclusive options, non-interactive behavior, and hidden-option
  omission.
- **FR-033**: README examples MUST include representative quiet, normal, verbose, no-color or redirected
  text, structured-stream, Markdown report, and session-directory excerpts. All examples MUST be
  plain-text fenced excerpts; binary or animated visual assets (screenshots, GIFs, terminal casts)
  MUST NOT be used, because GitHub renders no ANSI color inside code blocks and plain text is the
  baseline representation.
- **FR-034**: Documentation examples MUST use sanitized, stable input values and MUST NOT expose
  credentials, access tokens, private stream addresses, or expiring signed URLs.
- **FR-035**: The README MUST explain the end-to-end workflow from stream discovery through selection,
  validation, live monitoring, evidence capture, and report generation in user-oriented language.
- **FR-036**: The README MUST explain which output mode is appropriate for interactive monitoring,
  automation, concise review, and diagnosis.
- **FR-037**: All README commands, option descriptions, version strings, example file paths, and output
  excerpts MUST be verified against the released `0.4.0` behavior before completion. Any public test
  stream referenced in examples MUST be confirmed to resolve and to run cleanly with valistream `0.4.0`
  before inclusion, so the README never advertises a dead link or a stream that produces misleading
  errors.
- **FR-038**: User-provided live and video-on-demand stream URLs MUST be used for realistic manual
  acceptance testing when they are available; the URLs themselves MUST remain outside committed
  artifacts unless the user explicitly confirms they are public and suitable for publication.

### Key Entities

- **Output Block**: A contiguous human-readable unit for a session phase, playlist refresh, finding set,
  notice, or final summary. It has a heading or context, primary outcome, optional subordinate detail,
  and controlled spacing.
- **Playlist Information Block**: A one-time, first-load engineering summary for a master or media
  playlist. It uses the playlist ID as its header, presents the required type-specific fields in
  separated groups, and is identical in information content across normal terminal, verbose terminal,
  and Markdown report output.
- **Presentation Role**: The semantic purpose of text such as heading, identifier, success, progress,
  metadata, warning, error, evidence path, or summary. The role determines hierarchy independently of
  any particular color.
- **Verbosity Profile**: The quiet, normal, or verbose set of human-readable messages. Each higher tier
  adds context without changing validation results or machine-readable artifacts.
- **Onboarding Path**: The ordered README journey from understanding the tool through installation,
  first run, option selection, output interpretation, evidence navigation, and troubleshooting.
- **Playlist Lifecycle Event**: A playlist becoming unavailable, recovering, being added or removed, or
  changing identity during a session. Each such event belongs in the incident timeline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a review using a representative 100-line normal session capture, at least 90% of
  participants can identify the current phase, latest playlist result, first warning or error, its
  evidence path, and the final session outcome within 15 seconds per requested item.
- **SC-002**: A warning-free playlist refresh produces no more than one persistent normal-mode result
  line with a timestamp, excluding the transient heartbeat.
- **SC-003**: 100% of warnings and errors in terminal and Markdown output have an explicit textual
  severity, timestamp, playlist/snapshot context, and adjacent evidence reference or explicit
  evidence-unavailable statement.
- **SC-003a**: 100% of human-readable terminal messages have a timestamp, and 100% of report entries
  describing findings, refreshes, lifecycle events, failures, or session boundaries have a timestamp.
- **SC-003b**: Terminal timestamp values match `[HH:mm:ss.SSS]`; report timestamp values contain a date,
  milliseconds, and numeric UTC offset, and events representing the same instant correlate within one
  millisecond.
- **SC-003c**: Delaying or reordering message rendering does not change an event's recorded timestamp,
  and terminal/report representations of the same event identify the same occurrence instant.
- **SC-004**: Quiet-mode captures contain 100% of warnings, errors, required notices, and final-summary
  data, with zero routine successful-refresh or low-level diagnostic messages.
- **SC-005**: Plain, redirected, and styling-disabled output contains zero styling/control bytes and
  preserves 100% of the state and severity information conveyed by styled output.
- **SC-006**: At 80- and 120-column widths, no warning/error severity, playlist/snapshot identifier,
  finding message, or evidence reference is silently truncated; continuation lines remain associated
  with their originating block.
- **SC-007**: Verbose output exposes all diagnostic categories required by the existing verbosity
  contract, and every diagnostic line can be associated with a session phase or playlist/snapshot.
- **SC-008**: A reader opening a representative Markdown report can reach the overall result,
  highest-severity finding, and its evidence in under 30 seconds without text search.
- **SC-008a**: The incident timeline contains 100% of findings, failures, interruption/shutdown events,
  and playlist unavailable, recovered, added, removed, and identity-changed events in chronological
  order, with zero routine successful refresh entries.
- **SC-008b**: Every finding timeline entry links to exactly one complete severity-grouped finding
  entry, and no complete finding message or evidence block is duplicated in the timeline.
- **SC-008c**: Repeated report generation from the same recorded events produces the same incident
  timeline order, including events with equal timestamps.
- **SC-009**: At least 90% of first-time users following only the README can determine platform support,
  install through a documented path, run a first validation, and locate the generated report within
  10 minutes.
- **SC-010**: README verification finds zero differences between documented and actual public options,
  defaults, conflicts, version, exit codes, output artifact names, and example command behavior, and
  every displayed badge reflects a verifiable current value (no broken or stale badge).
- **SC-011**: Automated compatibility checks confirm zero changes to validation results, rule/finding
  identifiers, structured report data, line-delimited structured output, selection behavior, and exit
  codes.
- **SC-012**: For every loaded playlist, normal terminal output, verbose terminal output, and the
  Markdown report contain exactly one playlist-information block with all fields required for that
  playlist type; quiet terminal output contains zero such blocks.
- **SC-013**: For every media playlist in a mixed-protection stream, its information block reports its
  own protection classification independently, including unprotected subtitle playlists alongside
  protected video or audio playlists.

## Assumptions

- Feature `003-monitoring-evidence` is complete and its validation, evidence, identifier, report-data,
  structured-output, selection, and exit-code contracts remain authoritative.
- The product version has already been bumped to `0.4.0`; this feature verifies consistency rather than
  choosing a different version.
- Human-readable terminal output and the Markdown report are in scope. Machine-readable output receives
  compatibility verification only.
- Existing public verbosity and color controls are sufficient; no new command-line option is required.
- Styling is progressive enhancement. The plain-text representation is the accessibility and
  redirection baseline.
- English remains the only output and documentation language for this release.
- Installation documentation describes only platforms and distribution methods that can be verified in
  the repository or release process. Unsupported platforms are identified rather than presented with
  speculative instructions.
- The user supplied two realistic acceptance inputs on 2026-06-14: the live "TV Nord" channel and the
  "NRK news" video-on-demand stream. Their full URLs are conversation-only test inputs and are not
  persisted in repository documentation or project memory.
- Stream query strings containing account metadata, client IPs, timestamps, opaque authorization
  values, or fixed playback windows are treated as sensitive and potentially expiring even when no
  separate login is required.
- The code-coverage badge requires a verifiable coverage source (for example, a CI pipeline that
  measures and publishes coverage). If no such source exists yet, establishing one is a prerequisite
  for displaying the coverage badge; until it does, per FR-029a the badge is omitted rather than shown
  stale.
- The release process publishes a prebuilt `valistream-cli.zip` CLI artifact on each GitHub Release,
  alongside the auto-generated "Source code (zip)" archive; this is the primary distribution channel
  the README documents.

## Out of Scope

- Adding or changing validation rules, finding identifiers, severity assignments, or evidence
  resolution.
- Changing playlist selection semantics, command exit codes, structured report data, or JSON Lines
  behavior.
- Adding a new distribution channel, claiming support for an unverified platform, or publishing a
  user-provided stream URL.
- Adding interactive report viewers, graphical interfaces, localization, or configurable themes.
- Embedding screenshots, animated terminal recordings, or other binary/animated media in the README;
  README examples are plain-text excerpts only.
