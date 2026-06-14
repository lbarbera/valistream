# Feature Specification: Readable Output and Onboarding

**Feature Branch**: `main`

**Created**: 2026-06-14

**Status**: Draft

**Input**: User description: "Increase stdout and report readability across quiet, normal, and verbose modes through meaningful color and emphasis, message grouping, whitespace, and natural language. Make output easy to skim and navigate. Rewrite README.md as a complete GitHub-style onboarding guide with rationale, operation, installation, options, and realistic examples. Ship as 0.4.0."

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
   validation, and duplicate success messages.
3. **Given** a refresh with warnings or errors, **When** its result is printed, **Then** the summary,
   findings, and evidence form one adjacent block that is not interrupted by unrelated playlist output.
4. **Given** a session that completes or is interrupted, **When** output ends, **Then** a visually
   prominent summary states the outcome, finding counts, elapsed time, and report location.

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
   highest-severity findings appear before lower-priority detail, with stable section navigation.
4. **Given** color and text styling are unavailable, **When** the same output is viewed, **Then** labels,
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
- **FR-009**: Visual styling MUST assign consistent semantic roles to headings, identifiers, success,
  progress, secondary metadata, warnings, errors, paths, and summaries.
- **FR-010**: Color MUST reinforce meaning but MUST NOT be the only indicator of severity, state,
  hierarchy, or actionability.
- **FR-011**: Text emphasis MUST distinguish primary outcomes from secondary context while preserving
  the same wording and information when emphasis is unavailable.
- **FR-012**: Styling MUST be disabled for non-interactive output, `NO_COLOR`, `--no-color`, and limited
  terminal environments; plain output MUST contain no styling or cursor-control bytes.
- **FR-013**: Symbols or glyphs MUST supplement readable text labels and MUST have a plain-text fallback
  when the environment cannot display them reliably.
- **FR-014**: Long human-readable lines MUST wrap or continue with recognizable indentation so severity,
  playlist/snapshot identity, finding text, and evidence are not lost at common terminal widths.
- **FR-015**: Quiet mode MUST contain all warnings, errors, required fallback/failure notices, shutdown
  state, and the final summary, and MUST omit routine discovery, progress, successful refresh, and
  diagnostic messages.
- **FR-016**: In quiet mode, related findings MUST be grouped by playlist/snapshot context and each
  evidence reference MUST remain directly associated with its finding.
- **FR-017**: Normal mode MUST show session setup, the playlist roster, concise progress, one result per
  refresh, findings with evidence, significant lifecycle notices, and the final summary.
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
- **FR-026**: Markdown findings MUST be organized so errors precede warnings and routine informational
  detail, while preserving every finding and its existing evidence reference.
- **FR-027**: The Markdown report MUST use headings, whitespace, tables, emphasis, and code spans
  consistently and MUST contain no terminal styling or cursor-control bytes.
- **FR-028**: The structured JSON report, metadata files, findings log, and line-delimited structured
  status stream MUST preserve their existing data contracts and machine-readable formatting rules.
- **FR-029**: `README.md` MUST follow a recognizable GitHub project structure: project name and concise
  description, motivation, key capabilities, how it works, quick start, installation, usage, option
  reference, output modes, generated artifacts, realistic examples, exit codes, troubleshooting,
  limitations/platform support, and links to applicable project resources.
- **FR-030**: README installation instructions MUST distinguish verified supported methods from
  unsupported or unavailable distribution methods and MUST include prerequisites and a verified source
  build path.
- **FR-031**: README quick-start instructions MUST take a user from installation to a first validation
  and explain where to find the resulting report and evidence.
- **FR-032**: README parameter documentation MUST match the `0.4.0` command help, including defaults,
  accepted value forms, mutually exclusive options, non-interactive behavior, and hidden-option
  omission.
- **FR-033**: README examples MUST include representative quiet, normal, verbose, no-color or redirected
  text, structured-stream, Markdown report, and session-directory excerpts.
- **FR-034**: Documentation examples MUST use sanitized, stable input values and MUST NOT expose
  credentials, access tokens, private stream addresses, or expiring signed URLs.
- **FR-035**: The README MUST explain the end-to-end workflow from stream discovery through selection,
  validation, live monitoring, evidence capture, and report generation in user-oriented language.
- **FR-036**: The README MUST explain which output mode is appropriate for interactive monitoring,
  automation, concise review, and diagnosis.
- **FR-037**: All README commands, option descriptions, version strings, example file paths, and output
  excerpts MUST be verified against the released `0.4.0` behavior before completion.
- **FR-038**: User-provided live and video-on-demand stream URLs MUST be used for realistic manual
  acceptance testing when they are available; the URLs themselves MUST remain outside committed
  artifacts unless the user explicitly confirms they are public and suitable for publication.

### Key Entities

- **Output Block**: A contiguous human-readable unit for a session phase, playlist refresh, finding set,
  notice, or final summary. It has a heading or context, primary outcome, optional subordinate detail,
  and controlled spacing.
- **Presentation Role**: The semantic purpose of text such as heading, identifier, success, progress,
  metadata, warning, error, evidence path, or summary. The role determines hierarchy independently of
  any particular color.
- **Verbosity Profile**: The quiet, normal, or verbose set of human-readable messages. Each higher tier
  adds context without changing validation results or machine-readable artifacts.
- **Onboarding Path**: The ordered README journey from understanding the tool through installation,
  first run, option selection, output interpretation, evidence navigation, and troubleshooting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a review using a representative 100-line normal session capture, at least 90% of
  participants can identify the current phase, latest playlist result, first warning or error, its
  evidence path, and the final session outcome within 15 seconds per requested item.
- **SC-002**: A warning-free playlist refresh produces no more than one persistent normal-mode result
  line, excluding the transient heartbeat.
- **SC-003**: 100% of warnings and errors in terminal and Markdown output have an explicit textual
  severity, playlist/snapshot context, and adjacent evidence reference or explicit evidence-unavailable
  statement.
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
- **SC-009**: At least 90% of first-time users following only the README can determine platform support,
  install through a documented path, run a first validation, and locate the generated report within
  10 minutes.
- **SC-010**: README verification finds zero differences between documented and actual public options,
  defaults, conflicts, version, exit codes, output artifact names, and example command behavior.
- **SC-011**: Automated compatibility checks confirm zero changes to validation results, rule/finding
  identifiers, structured report data, line-delimited structured output, selection behavior, and exit
  codes.

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

## Out of Scope

- Adding or changing validation rules, finding identifiers, severity assignments, or evidence
  resolution.
- Changing playlist selection semantics, command exit codes, structured report data, or JSON Lines
  behavior.
- Adding a new distribution channel, claiming support for an unverified platform, or publishing a
  user-provided stream URL.
- Adding interactive report viewers, graphical interfaces, localization, or configurable themes.
