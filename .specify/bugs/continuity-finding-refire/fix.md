# Bug Fix: Continuity & delivery findings dedup via recordIfNew (no per-refresh re-fire)

- **Slug**: continuity-finding-refire
- **Fixed**: 2026-06-15
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The two per-refresh loops in `monitorPlaylist` recorded delivery and continuity violations via
`record(...)` directly, so a persistently failing origin (404 forever) or a repeating continuity
fault re-emitted an identical finding every refresh — unbounded growth of findings/JSONL/report.
Both loops now route through the existing `recordIfNew(...)`; because these messages are stable
(unlike staleness, whose message embeds the live stale-seconds), the `resource|ruleId|line|message`
signature collapses a persistent identical fault to a single finding while still recording
genuinely distinct faults.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift` | modified | `monitorPlaylist`: delivery loop and continuity loop `record` → `recordIfNew`; added comments noting why stable-signature dedup suffices here vs. transition-gating for staleness. |
| `Valistream/Valistream/ValistreamIntegrationTests/LiveFaultScenarioTests.swift` | added tests | Delivery-dedup and continuity-dedup regression tests. |

## Diff Highlights

Delivery loop (per refresh):

```swift
// Dedup by stable signature: a persistently failing origin returns the same delivery
// violation every refresh … The message is stable, so `recordIfNew` suffices — unlike
// staleness, whose message embeds the live stale-seconds and so is gated on a state transition.
for violation in load.deliveryViolations {
    recordIfNew(violation, resource: candidate.url, refreshIndex: refreshIndex)
}
```

Continuity loop (per refresh, inside `if let media`):

```swift
for violation in continuityChecker.check(previous: previous, current: media) {
    recordIfNew(violation, resource: candidate.url, refreshIndex: refreshIndex)
}
```

## Tests Added or Updated

- `LiveFaultScenarioTests/deliveryViolationIsNotRefiredEachRefresh()` — loads once, then 404s every
  refresh across 6 cycles; asserts exactly 1 `TOOL.delivery` finding (a failed fetch has no media,
  so delivery is the only finding minted each cycle — the guaranteed-unbounded case).
- `LiveFaultScenarioTests/repeatedContinuityFaultIsNotRefired()` — a window oscillating seq10 ⇄ seq8
  re-emits the identical "regressed from 10 to 8" fault on every down-leg; asserts exactly 1
  `TOOL.continuity.media-sequence` finding (dedup collapses the identical message).
- Over-suppression guard: existing `sequenceRegressionIsContinuityError` (a single distinct
  regression IS recorded) and `discontinuityInsertionIsInfoAndContinues` stay green, confirming
  `recordIfNew` does not swallow genuinely distinct faults.

## Local Verification

- `BuildProject` (windowtab1, Valistream.xcworkspace) → built successfully, 0 errors.
- `RunSomeTests` (LiveFaultScenarioTests, InterruptedSessionTests, LiveMonitoringTests,
  PlaylistIDSchemeTests, ContinuityCheckerTests) → 33/33 passed, incl. the 2 new tests.
- `RunAllTests` (full `Valistream` test plan) → 443/443 passed, 0 failed (was 441 before the 2 new
  tests). No regression in the FROZEN-contract guards (report schema, findings JSONL, incident
  timeline, finalization / exit-code suites) called out by the assessment.

## Deviations from Assessment

None. Implemented the assessment's **preferred** remediation (route both per-refresh loops through
`recordIfNew`). Scope kept to the two per-refresh loops in `monitorPlaylist`; the initial/one-shot
delivery loops (`ValidationSession.swift:191` root, `:275` media references) were left on `record`
per the assessment's *Scope* note — they fire once per playlist, not per refresh.

Open questions accepted as designed:
- **No re-arm after recovery** (a fault that clears and recurs with the same message records once):
  accepted. The lifecycle/incident-timeline events from the staleness work already carry the
  recurrence signal; the durable findings list stays bounded.
- **Info-severity dedup** (`discontinuity-inserted`): now deduped per identical message, distinct
  sequences still recorded — consistent with the error-severity continuity handling.

## Follow-ups

- If the product later wants a *re-occurrence-after-recovery* signal in the durable findings (not
  just the timeline), revisit with the transition/lifecycle alternative from the assessment.
- Next: `/speckit-bug-test slug=continuity-finding-refire`.
