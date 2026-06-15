# Bug Assessment: Staleness findings never deduplicate → unbounded report/JSONL flood

- **Slug**: staleness-finding-flood
- **Created**: 2026-06-15
- **Source**: pasted text (in-session broad code review of `ValidationSession` live monitoring)
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

During a broad project check, the live-monitoring path was found to emit a fresh
`TOOL.staleness` finding on **every refresh cycle** while a playlist is stale, with no
deduplication. Because a stale (stuck) live playlist by definition keeps refreshing at the
`target/2` cadence indefinitely, the findings collection, the append-only JSONL log, and the
per-refresh report all grow without bound for the exact failure mode staleness exists to detect.

## Symptom

- **Observed**: While a monitored media playlist stays unchanged past the staleness threshold,
  one new `TOOL.staleness` finding is recorded per refresh. Over a long monitor of a stuck stream
  this produces hundreds–thousands of near-duplicate findings in the terminal stream, the
  `FindingsLog` JSONL, and the JSON/Markdown report.
- **Expected**: A stale episode should surface a bounded number of findings — ideally one per
  threshold crossing (`monitoring → staleWarning`, `staleWarning → staleError`), reset when the
  playlist next changes. The report for a dead stream should stay readable.

## Reproduction

1. Start a live monitor against a media playlist whose target duration is small (e.g. 4s).
2. Cause (or simulate) the playlist to stop updating — content never changes after load.
3. Let the session run; refreshes continue at `target/2` (~2s) because `lastChanged == false`.
4. Observe `recordedFindings` / the JSONL log / the report: one `TOOL.staleness` finding is added
   each refresh (~1 every 2s ≈ 1800 findings in a 1-hour monitor), all near-identical except the
   stale-seconds value in the message.

Note: deterministic to confirm via the existing in-process harness (`ManualClock` +
`ScriptedStreamFetcher` returning an unchanging body) — see Tests below. Not yet executed; the
defect is established directly from code behavior.

## Suspected Code Paths

- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift:155-156`
  — monitor loop: `if changed == false { evaluateStaleness(candidate, since: lastChangedAt, target: targetDuration, refreshIndex: refreshIndex) }`. Runs every refresh while unchanged.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift:214-228`
  — `evaluateStaleness` calls `record(...)` **directly** (not `recordIfNew`), so no dedup is even
  attempted.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift:322`
  — `record(...)` always appends to `findings`, appends to the JSONL log, and yields a `.finding`
  event. No suppression.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift:460`
  — `signature(_:resource:)` = `resource | ruleId | line | message`. The staleness **message**
  embeds the live stale-seconds (`"Playlist has not changed for \(staleText)s …"`,
  `StalenessDetector.violation`), so the signature differs every cycle. Even if `evaluateStaleness`
  used `recordIfNew` (`:352-353`), the changing message would defeat the `recordedSignatures` set.
- Compounding: `writeReport(interruption: nil)` is invoked at the end of every refresh cycle and
  serializes the **entire** findings list each time. With findings growing linearly, total report
  write work over a session is O(n²).

## Root Cause Hypothesis

**Confidence: high.** Two reinforcing causes: (1) staleness is recorded via `record` rather than
`recordIfNew`, so no deduplication is attempted; (2) the dedup key (`signature`) is derived from
the human message, which intentionally varies (stale-seconds), so the existing dedup mechanism
could not suppress staleness even if asked to. The staleness condition is persistent by nature
(a stuck stream stays stuck), so the per-refresh emission accumulates without bound, and the
per-refresh full-report rewrite turns that linear growth into quadratic write cost.

## Proposed Remediation

**Preferred**: Emit staleness on **state transition only**. Track the per-playlist
`MonitorState` already maintained in `monitorStates`; in `evaluateStaleness`, compute the new
staleness severity, and record a `TOOL.staleness` finding only when the staleness *level changes*
(`monitoring/none → warning`, `warning → error`). When content next changes (the `if changed`
branch in the monitor loop, `ValidationSession+Monitoring.swift:130-133`), the state already
returns to `.monitoring`, which re-arms the next crossing. This yields at most two staleness
findings per stale episode and keeps the report readable. The terminal/heartbeat can still reflect
ongoing staleness via `setMonitorState` without minting a new `Finding` each cycle.

**Alternatives**:
- Dedup by a stable key: give staleness a severity-bucketed signature that excludes the
  stale-seconds (e.g. `resource | ruleId | severity`) and route it through `recordIfNew`; clear
  those signatures from `recordedSignatures` when the playlist changes so a later re-stale can
  re-fire. Trade-off: needs targeted signature handling + reset logic, slightly more state than the
  transition approach.
- Rate-limit staleness to once per N refreshes or once per target-duration window. Trade-off:
  still unbounded over very long sessions, picks an arbitrary cadence.

**Files likely to change**:
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift`
  (`evaluateStaleness`, and possibly the call site / change-branch to expose prior staleness level)
- Possibly `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift`
  (helper to read prior `MonitorState` if not already accessible inside the method)

**Tests to add or update**:
- Integration (in-process harness): monitor a never-changing media playlist across many refresh
  cycles via `ManualClock`; assert the count of `TOOL.staleness` findings is bounded (≤ 2 per stale
  episode), not one-per-refresh.
- Unit: a stale → recover (content changes) → stale-again sequence emits a new warning/error on the
  second episode (transition re-arms after change).
- Guard: existing `StalenessDetectorTests` (threshold math) stay green — detector logic is unchanged;
  the fix is in the session's emission policy, not the detector.

## Risks & Considerations

- **Behavioral change to findings volume**: any test or fixture asserting "staleness fires every
  refresh" must be updated. Audit `LiveFaultScenarioTests` / staleness integration tests.
- **FROZEN contracts**: rule ID `TOOL.staleness`, JSON report schema v1, exit codes, and the
  `--json` stream object shape must stay unchanged — only the *number/cadence* of staleness findings
  changes, not their structure. Confirm `ReportJSONSchemaTests` and exit-code guards stay green.
- **Related (out of scope here, worth a follow-up)**: continuity violations
  (`ValidationSession+Monitoring.swift`, the `continuityChecker.check` loop) also use `record`
  directly; a persistently broken stream (e.g. repeated `segment-stability` on the same retained
  sequence) can similarly re-fire. Staleness is the guaranteed unbounded case; continuity is a
  narrower edge. Track separately if confirmed.
- **Severity rationale (high, not critical)**: no crash, no data loss, no security/contract breakage;
  but it degrades the core deliverable (a readable incident report) precisely for the failure it is
  meant to capture, and imposes O(n²) report-write cost on long unattended runs.

## Open Questions

- [NEEDS CLARIFICATION: Is per-refresh staleness emission an intentional "ongoing signal" design, or
  an oversight? Even if intentional for the live terminal, the durable artifacts (findings/JSONL/report)
  should be bounded — confirm the intended contract for staleness in the report vs. the heartbeat.]
- [NEEDS CLARIFICATION: Desired bound — one finding per stale episode, one per severity crossing
  (warning + error), or a capped/rate-limited stream?]
