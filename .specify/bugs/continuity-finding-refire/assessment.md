# Bug Assessment: Continuity & delivery findings re-fire per refresh → report/JSONL flood

- **Slug**: continuity-finding-refire
- **Created**: 2026-06-15
- **Source**: pasted text (follow-up flagged by the `staleness-finding-flood` fix)
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

Follow-up from the `staleness-finding-flood` fix. In `ValidationSession+Monitoring.swift`'s
`monitorPlaylist`, two per-refresh loops call `record(...)` **directly** (no dedup, no transition
gating — the same pattern that caused the staleness flood):

- the `deliveryViolations` loop (HTTP / transport / non-playlist faults from `PlaylistLoader`);
- the `continuityChecker.check(previous:current:)` loop (media-sequence, head-removal,
  segment-stability, discontinuity faults).

A persistently broken stream can re-fire the same violation once per refresh, growing the findings
collection, the `FindingsLog` JSONL, and the per-refresh report. Asked to assess whether these can
flood and what the right remediation is.

## Symptom

- **Observed**: For an origin that fails the same way every refresh, the corresponding finding is
  re-recorded on **every** refresh. The strongest case is delivery: an origin that returns HTTP 404
  (or a transport error, or a non-M3U8 body) on every poll records one identical `TOOL.delivery`
  error per refresh — ~1 every `target/2` seconds — with no upper bound. Findings list, JSONL, and
  report grow linearly; the per-refresh full-report rewrite makes total write cost O(n²).
- **Expected**: A persistent fault should surface a bounded number of findings (ideally one per
  distinct fault), keeping the report readable for a dead/erroring origin.

## Reproduction

Delivery (guaranteed unbounded):

1. Start a live monitor against a media playlist URL.
2. After the initial successful load, make every subsequent fetch fail identically (e.g. HTTP 404,
   or a transport error, or a body that is not an M3U8).
3. Let the session run. Each refresh, `load.playlist?.media` is `nil`, so staleness and continuity
   are skipped — but the `deliveryViolations` loop records one `TOOL.delivery` finding per refresh.
4. Observe `recordedFindings` / JSONL / report: one near-identical `TOOL.delivery` error per refresh,
   unbounded.

Continuity (narrower):

1. Start a live monitor; serve a valid window initially.
2. Make the window keep changing in a broken way that yields the **same** violation message each
   refresh — e.g. the media-sequence repeatedly regresses by the same delta, or a head-removal jump
   repeats with identical advanced/previous counts.
3. Observe: the identical continuity finding is recorded each refresh.

Note: deterministic via the existing in-process harness (`ManualClock` + `ScriptedStreamFetcher`
with a failing/oscillating timeline) — see Tests below. Not yet executed; established from code
behavior.

## Suspected Code Paths

- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift:105`
  — monitor loop: `for violation in load.deliveryViolations { record(violation, …) }`. Runs every
  refresh; for a persistently failing fetch this is the **guaranteed** unbounded case (media is nil,
  so this is the only finding minted each cycle).
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift`
  (continuity loop, just after `evaluateStructural`): `for violation in continuityChecker.check(previous:current:) { record(violation, …) }`.
  Runs every refresh that has media.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift:369` — `record(...)`
  always appends to `findings`, appends to JSONL, inserts the signature, and yields a `.finding`
  event. No suppression.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift:400` —
  `recordIfNew(...)` already exists and is the intended dedup path; `evaluateStructural` already uses
  it (`ValidationSession+Monitoring.swift:187,191`). The delivery/continuity loops simply don't.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift:534` —
  `signature(_:resource:)` = `resource | ruleId | line | message`.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/PlaylistLoader.swift:70-88,122-129` —
  delivery violation messages: `"Playlist request returned HTTP status <status>."`,
  `"Failed to fetch playlist: <description>."`, `"Response body is not an M3U8 playlist…"`.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Monitoring/ContinuityChecker.swift:25-127` —
  continuity violation messages embed sequence numbers / counts.

## Root Cause Hypothesis

**Confidence: high.** Both loops record via `record` rather than `recordIfNew`, so no dedup is
attempted. **Unlike staleness**, the messages here are *stable* for a persistent fault — delivery
messages depend only on the failure mode/status, and continuity messages depend only on the
`(previous, current)` pair, not on a per-refresh-varying clock value. Therefore the existing
`signature`-based dedup (`recordedSignatures` + `recordIfNew`) is sufficient: it could not help
staleness (whose message embedded the live stale-seconds) but it *can* suppress these.

Why delivery is the worst case: when a fetch fails, `load.playlist?.media` is `nil`, so the
staleness and continuity branches are skipped entirely — the delivery violation is the only finding
minted per refresh, and it repeats identically forever for a stuck-error origin. That is the same
unbounded-report degradation, with the same O(n²) write cost, that made `staleness-finding-flood`
high severity.

Why continuity is narrower: the previous/current diff model is largely self-healing — a mutated
retained segment becomes the new `previous` (so it stops re-flagging), and an unchanged refresh
compares `previous` against itself (no violation). It floods only when the stream keeps changing in
a broken way that re-emits an *identical* message (e.g. an oscillating window). Genuinely distinct
faults (different sequence numbers) produce different signatures and are legitimately separate
findings that should not be suppressed.

## Proposed Remediation

**Preferred**: Route the two per-refresh monitor-loop loops through `recordIfNew` instead of
`record` — the same dedup path `evaluateStructural` already uses:

- `ValidationSession+Monitoring.swift:105` delivery loop → `recordIfNew(violation, resource: candidate.url, refreshIndex: refreshIndex)`
- the continuity loop → `recordIfNew(violation, resource: candidate.url, refreshIndex: refreshIndex)`

Because the messages are stable, the existing `resource|ruleId|line|message` signature collapses a
persistent identical fault to a single finding, while still recording genuinely distinct faults
(different status/sequence ⇒ different signature). This is minimal, reuses existing machinery, and
needs no new state or transition logic. It does **not** require the `MonitorState`-transition
approach used for staleness, precisely because the dedup key is stable here.

**Alternatives**:
- Transition/lifecycle gating for delivery (mirror staleness): drive a `MonitorState` (e.g.
  `.unavailable`) from delivery outcome and emit a finding only on entering the error state, clearing
  on recovery. Trade-off: more state; and `recordIfNew` already achieves the bound. Worth it only if
  the product wants a *re-occurrence-after-recovery* signal in the durable findings (see Open
  Questions) rather than only in lifecycle events.
- Rate-limit per N refreshes. Trade-off: arbitrary cadence, still unbounded over very long sessions.

**Files likely to change**:
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift`
  (the two per-refresh loops in `monitorPlaylist`).

**Tests to add or update**:
- Integration (in-process harness): a media URL that loads once then returns HTTP 404 every refresh
  across many cycles → assert the count of `TOOL.delivery` findings is bounded (1), not one per
  refresh.
- Integration: a stream whose continuity fault repeats with an identical message across refreshes →
  assert the finding is recorded once.
- Guard: a stream with *distinct* continuity faults (different sequences) still records each distinct
  finding — `recordIfNew` must not over-suppress. Audit existing `LiveFaultScenarioTests`
  (`sequenceRegressionIsContinuityError`, `discontinuityInsertionIsInfoAndContinues`) stay green.
- Guard: `ContinuityCheckerTests` (pure detector) unchanged.

## Risks & Considerations

- **No re-arm after recovery**: pure `recordIfNew` dedups globally for the session — a fault that
  clears and later recurs with the same message is recorded only once. For delivery this means a
  second outage after a recovery would not mint a new finding (the lifecycle/`unavailable`/`recovered`
  events from the staleness work already carry the recurrence signal in the timeline). Confirm this
  is acceptable for the durable findings list, or adopt the transition/lifecycle alternative.
- **FROZEN contracts**: rule IDs (`TOOL.delivery`, `TOOL.continuity.*`), JSON report schema v1, the
  `--json` stream object shape, and exit codes must stay unchanged — only the *number/cadence* of
  these findings changes. Confirm `ReportJSONSchemaTests` and exit-code guards stay green.
- **Scope**: limit the change to the two **per-refresh** loops in `monitorPlaylist`. The initial /
  one-shot delivery loops (`ValidationSession.swift:191` root, `:275` media references) fire once per
  playlist, not per refresh, and are not a flood source — leave them on `record` unless a reason
  emerges to unify.
- **Consistency**: after this, all three monitor-loop finding sources (structural, delivery,
  continuity) use `recordIfNew`; staleness uses transition gating because its message varies. That is
  the correct split, but worth a one-line comment so a future reader doesn't "fix" staleness to match.
- **Severity rationale (high)**: the delivery sub-case reproduces the exact unbounded-report
  degradation and O(n²) write cost that made `staleness-finding-flood` high — for a common,
  expected failure (a dead/erroring origin) that the tool exists to report readably. The continuity
  sub-case alone would be medium.

## Open Questions

- [NEEDS CLARIFICATION: For the durable findings list, is a single finding per persistent fault the
  intended contract, or should a fault that recurs after a recovery mint a new finding? If the
  latter, prefer the transition/lifecycle alternative over plain `recordIfNew`.]
- [NEEDS CLARIFICATION: Should `info`-severity continuity events (`discontinuity-inserted`) also be
  deduped, or is repeated info acceptable? `recordIfNew` would dedup identical-message inserts but
  keep distinct sequences — likely fine, confirm.]
