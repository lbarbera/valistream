# Phase 0 Research: Performance and UX

**Feature**: 002-performance-ux | **Date**: 2026-06-13 | **Plan**: [plan.md](plan.md)

This feature changes only presentation, responsiveness, session control, and report formatting on top
of feature 001. No validation semantics, structured-report schema, or exit codes change (FR-003).
Decisions below resolve every open choice the plan depends on; there are no remaining
`NEEDS CLARIFICATION` markers (the spec's seven clarifications are recorded in spec.md §Clarifications).

## Constraint: documentation lookup

Per repository rules (`CLAUDE.md`): documentation lookup goes through **xcode-tools
`DocumentationSearch`** only; **no WebSearch is allowed**. `DocumentationSearch` covers Apple
frameworks (Foundation, URLSession, FileManager) but **cannot** verify third-party Swift packages
(Rainbow, Promptberry). Consequences are folded into D1 and the verification step of D8.

---

## D1. New runtime dependencies (Rainbow, Promptberry) and where they attach

**Decision**: Adopt the two libraries named in the spec — **Rainbow** (terminal color/styling) and
**Promptberry** (interactive prompts) — as **remote SwiftPM package dependencies on the CLI Xcode
target only**. The `ValistreamCore` library stays **zero external dependencies** (pure Swift +
Foundation), exactly as in feature 001.

**Rationale**:

- Color and interactive prompts are *presentation/IO* concerns. They belong in the thin CLI shell,
  never in the testable domain core. The report **files** must contain no styling regardless (D5), so
  color cannot leak into core.
- Aliases and live/atomic report writing (US4) are pure string/file logic and stay in core with **no**
  new dependency.
- The spec's whole purpose is "world-standard CLI" UX; the user named these libraries explicitly
  (spec §Assumptions). Isolating them to the CLI target contains the blast radius and keeps core
  reusable by a future GUI.

**Constitution III (Simplicity / prefer stdlib) tension** — recorded in plan Complexity Tracking:

- Color *could* be hand-rolled ANSI (~50 lines). Promptberry's multi-select *could* be the existing
  termios `PlaylistChecklist`. So both deps are, strictly, avoidable.
- Accepted anyway because: (a) explicit user direction + the feature's UX mandate; (b) deps are
  isolated to the non-core CLI target; (c) a concrete in-house fallback exists for each (below), so the
  dependency is reversible, not load-bearing.

**Verification (binding, at implementation start)**: Because WebSearch is disallowed and these are not
Apple frameworks, exact coordinates cannot be confirmed during planning. Before any US1/US5 code that
imports them, confirm via package resolution (Xcode "Add Package" / `swift package resolve`) that each:
resolves, supports Swift 6 strict concurrency, and supports macOS 14. SwiftPM fails fast if not.

**Fallbacks** (no blocking):

- *Rainbow unavailable/incompatible* → small in-house `ANSIStyle` helper (SGR codes), same gating (D2).
- *Promptberry unavailable/incompatible* → retain feature 001's termios `PlaylistChecklist`. US5 is
  P5 (lowest) and optional, so a prompt-library failure never blocks the feature.

**Alternatives considered**: all-in-house (rejected: rebuilds what the user asked to adopt, more
escape-sequence/termios maintenance); add deps to the core package (rejected: pollutes the pure,
GUI-reusable domain library and the test target).

---

## D2. Styling gate (color on/off) — one decision point

**Decision**: All console styling routes through a single CLI-side gate. Styling is enabled **iff**
`isatty(stdout)` **AND** `NO_COLOR` is unset **AND** the user did not pass `--no-color` **AND**
`TERM != "dumb"`. When disabled, every write emits plain text with zero SGR/cursor sequences.

**Rationale**: FR-009 + SC-004 require automatic disabling for pipes/files, the `NO_COLOR` convention,
and explicit opt-out; centralizing the predicate guarantees no styled path can bypass it. Severity is
**also** labeled in text (`ERROR`/`WARN`/`INFO`/`OK`) so meaning never depends on color alone (FR-009).

**Alternatives considered**: per-call-site checks (rejected: easy to miss one → control bytes leak into
a redirected log, fails SC-004).

---

## D3. Live progress + responsiveness (US1)

**Decision**: Keep the existing `ValidationSession.events` `AsyncStream<SessionEvent>` as the single
channel from core → CLI. Extend it with an **activity/progress** signal (current human activity string
+ `completed`/`total` counts; `total` optional for live). A dedicated CLI render `Task` consumes the
stream and never blocks core work:

- **TTY**: an in-place status line (spinner + `activity — N of M (xx%)`) rewritten on each event and on
  a ≥1 Hz tick (carriage-return + clear-to-EOL); discrete log lines (findings, milestones) are printed
  *above* the live line; logical messages separated by blank line(s) (FR-010).
- **Non-TTY** (FR-007): no spinner/cursor/color; progress emitted as discrete plain lines
  ("processed N of M") at a throttled cadence; findings as plain lines.

Responsiveness (FR-002, SC-001): heavy work (fetch/parse/validate/archive/report) already runs in the
session actor and async network; the render loop is a separate Task, so the display updates ≥1×/s and
input/interrupts are never blocked. Phase-1 confirms no synchronous long block exists on the core's
main path (parsing/validation are short CPU bursts; reports written off the render path).

**Alternatives considered**: CLI polling session state (rejected: races, misses sub-second activity);
rendering from inside the session actor (rejected: couples core to a terminal, blocks work).

---

## D4. Unified graceful stop (US2)

**Decision**: One finalization path (`finish()`) is reached by **all** session endings — normal
completion, user graceful stop (SIGINT), and optional time-limit expiry (FR-014). On the **first**
interrupt: set stop-requested, **immediately cancel** all in-flight network tasks (cancel the
monitoring `TaskGroup` / per-fetch tasks; cancelled fetches recorded as aborted/incomplete), flush the
archive + findings log, write the **final** report (a live session → complete for the monitored period;
a one-shot → clearly marked **partial**, covering playlists validated so far), announce shutdown, and
print where report + artifacts were written (FR-015). Bounded ≤ 3 s (SC-003).

The **second** interrupt during shutdown forces immediate `_exit(130)`; the first-interrupt message
warns that a second one forces exit (FR-013). Graceful stop applies to **one-shot** sessions too, not
only live (clarification 2026-06-13): `run()` checks stop-requested between playlists and finalizes a
partial report.

**Rationale**: builds directly on existing `abort()` / `stopRequested` / `setState(.aborted)` →
`writeReport` wiring; extends it to one-shot and to the immediate-cancel + bounded-shutdown guarantee.

**Alternatives considered**: awaiting in-flight requests on stop (rejected: clarification mandates
immediate cancel + bounded ≤3 s shutdown, no hang).

---

## D5. Output location resolution (US3)

**Decision**: A pure core resolver (`OutputLocation`) computes the absolute per-session folder:

- `--output <dir>` given → resolve to absolute (relative paths against current working directory).
- Omitted → default base: **macOS** `~/.valistream/sessions/`; **non-macOS** the platform data dir
  (`$XDG_DATA_HOME/valistream/sessions`, else `~/.local/share/valistream/sessions`).
- Per-session subfolder `= <base>/<sessionID>`, where `sessionID` (existing `makeSessionID`) is
  deterministic + collision-resistant (timestamp + stream identifier [+ short disambiguator]).
- **Startup pre-flight** (FR-019): create the base if needed and verify writability **before any
  fetch**; on failure, fail fast with an actionable error. Print the **absolute** session folder path
  at startup, before fetching (FR-017, FR-020, SC-005).

**Rationale**: the spec/clarification fixes the literal default `~/.valistream/sessions/` (not macOS
`Application Support`); honoring it verbatim keeps artifacts discoverable and predictable. Resolver in
core = unit-testable without a terminal.

**Alternatives considered**: macOS `Application Support` via `FileManager.url(for:.applicationSupport…)`
(rejected: contradicts the explicit clarified path); resolving in the CLI (rejected: harder to test).

---

## D6. Live-updating + atomic reports (US4)

**Decision**: Move report writing from end-only to **once per refresh cycle**. In live `monitor()`,
after each refresh cycle (coalescing every playlist refreshed that cycle), perform a **single atomic
write of both** the human-readable and structured reports (staleness ≤ one cycle, SC-006). One-shot
sessions write at completion and on graceful stop (partial). A "report dirty" flag set as
findings/refreshes accrue drives at most one write per cycle.

**Atomicity** (FR-022, SC-006): write each report to a temp file in the **same directory**, then
atomically replace the target (`FileManager.replaceItemAt` / rename on the same volume), so a reader
ever sees only a complete previous or new document — never a truncated one.

**Schema unchanged** (FR-003, FR-021, SC-010): `SessionReportBuilder.buildJSON` output is byte-for-byte
the same shape as feature 001; only *when/how often* it is written changes.

**Alternatives considered**: write on every finding (rejected: write amplification over a 24 h session);
write straight to the target file (rejected: a concurrent reader can observe a half-written file).

---

## D7. Prettified report + playlist aliases + legend (US4)

**Decision (aliases)**: New pure-core `PlaylistAlias` model + deterministic derivation, computed **once
per playlist URL** and reused across all refreshes/report updates (stable, FR-026):

- Role + key attributes: `video-<height>p`, `audio-<lang|name>`, `subs-<lang|name>`,
  `iframe-<height>p` (derived from `STREAM-INF` `RESOLUTION`, `EXT-X-MEDIA` `TYPE/LANGUAGE/NAME`,
  `I-FRAME-STREAM-INF`).
- Fallback to indexed labels `V1`/`A1`/`S1`/`I1` when distinguishing attributes are absent.
- Collisions de-duplicated deterministically with a numeric suffix (`video-1080p`, `video-1080p-2`).
- Deterministic = pure function of (role, attributes, discovery order); unique within a session.

**Decision (prettify)**: Rewrite `buildMarkdown` into clear sections — header → summary (aligned/tabular
counts) → **alias legend** → findings grouped by **severity then category** → per-playlist detail. The
**body uses aliases only**; raw playlist URLs appear **only** in the legend (SC-007). The legend maps
every alias → full URL + role/attributes; every alias used anywhere resolves through it (FR-025).

**Aliases are markdown-only**: the structured (JSON) report keeps full URLs and its frozen schema
(D6); aliases are a human-report concern, so **no field is added to the JSON** — guaranteeing zero
schema change. (Aliases are also surfaced in progress events for nicer status text, D3.)

**Alternatives considered**: adding an `alias` field to the JSON (rejected: risks schema drift vs
FR-003/SC-010); hashing URLs for aliases (rejected: not human-meaningful, fails FR-024).

---

## D8. Interactive prompts (US5)

**Decision**: Replace the termios `PlaylistChecklist` interactive path with **Promptberry** multi-select
(arrow navigation, space to toggle, **all pre-selected**, on-screen hints, clear selection state).
Skip the prompt entirely when non-interactive (no TTY) or when the selection was supplied up front
(`--select`/`--all`), applying the documented default (**all**) — preserving scriptability (FR-028).
On cancel or interrupt while a prompt is open, restore the terminal to a sane state and exit cleanly
with a clear message (FR-029).

**Rationale**: directly satisfies FR-027; the no-TTY/supplied-selection skip already exists in 001's
checklist and carries over. Fallback to the existing termios checklist if Promptberry can't be adopted
(D1) — US5 stays shippable either way.

**Alternatives considered**: keep termios checklist as primary (rejected: spec calls for the polished
Promptberry experience as the headline of US5).

---

## D9. Executable rename to `valistream` (FR-001)

**Decision**: Set the CLI target build setting **`PRODUCT_NAME = valistream`** (currently
`$(TARGET_NAME)` → `Valistream`), producing a lowercase binary `valistream`. ArgumentParser's
`commandName` is **already** `valistream`, so help/usage are correct; update the session banner,
`--version`/`--help` surface, README, and any test-plan/`PRODUCT_NAME` references. The Xcode target
*name* may stay `Valistream` (only the product name changes); DerivedData binary path becomes
`…/Debug/valistream`.

**Rationale**: smallest change that satisfies FR-001/SC-009 without renaming targets/schemes (which
would churn the workspace and test plans).

**Alternatives considered**: rename the whole target (rejected: needless churn to scheme/test-plan
wiring for a cosmetic product-name change).

---

## D10. Verbosity levels (FR-011)

**Decision**: Three flag-selected levels — `--quiet` (findings + errors only), normal (default:
activity + progress + findings), `--verbose` (adds per-request/diagnostic detail). `--quiet` and
`--verbose` are mutually exclusive (validation error if both). Verbosity is **CLI-only** and gates what
`StatusRenderer` prints; it **never** affects the report files or exit codes (FR-011, FR-003). `--quiet`
already exists; add `--verbose` and the mutual-exclusion check.

**Alternatives considered**: a numeric `-v/-vv` level (rejected: spec specifies named quiet/normal/
verbose flags).

---

## Summary of decisions

| # | Area | Decision |
|---|------|----------|
| D1 | Dependencies | Rainbow + Promptberry on **CLI target only**; core stays dep-free; verify at impl; fallbacks exist |
| D2 | Color gate | One predicate: TTY ∧ ¬NO_COLOR ∧ ¬`--no-color` ∧ TERM≠dumb; severity also in text |
| D3 | Progress | Extend `events` stream w/ activity+counts; separate render Task; TTY in-place / non-TTY plain |
| D4 | Graceful stop | Unified `finish()`; 1st interrupt = cancel-in-flight + flush + finalize ≤3 s; 2nd = `_exit(130)`; covers one-shot |
| D5 | Output dir | Pure `OutputLocation`; default `~/.valistream/sessions/`; pre-flight writability; print absolute path first |
| D6 | Live/atomic reports | Per-refresh-cycle coalesced atomic write of both reports; JSON schema frozen |
| D7 | Aliases/prettify | `PlaylistAlias` (role+attrs, indexed fallback, dedup, stable); markdown sections + legend; aliases markdown-only |
| D8 | Prompts | Promptberry multi-select; skip when non-TTY/supplied; restore terminal on cancel; termios fallback |
| D9 | Rename | `PRODUCT_NAME = valistream`; commandName already correct |
| D10 | Verbosity | `--quiet`/normal/`--verbose`, mutually exclusive; never affects files/exit codes |
