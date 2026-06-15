# Bug Fix: Staleness findings now emit on level transition only (no per-refresh flood)

- **Slug**: staleness-finding-flood
- **Fixed**: 2026-06-15
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

`evaluateStaleness` recorded a `TOOL.staleness` finding on every refresh while a playlist
stayed stale, growing the findings list / JSONL log / report without bound. It now records a
finding only when the staleness *level changes* (`monitoring → staleWarning → staleError`),
reading the prior `MonitorState` before `setMonitorState` mutates it. The monitor loop already
resets the state to `.monitoring` when content next changes, which re-arms the next crossing —
so a stuck stream yields at most one warning + one error finding per stale episode.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession+Monitoring.swift` | modified | `evaluateStaleness`: compute target `MonitorState`, `record(...)` only when `monitorState(for:) != newState`; reordered so prior state is read before `setMonitorState`. |
| `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift` | added | Internal `monitorState(for:)` reader — `monitorStates` is `private`, so the extension method could not read prior state directly. |
| `Valistream/Valistream/ValistreamIntegrationTests/LiveFaultScenarioTests.swift` | added tests | Bounded-count guard + recovery-rearm regression tests. |

## Diff Highlights

`evaluateStaleness` (emission policy):

```swift
let presentationID = aliasRegistry.alias(for: candidate.url)?.alias ?? candidate.id
let newState: MonitorState = violation.severity == .error ? .staleError : .staleWarning
// Record only on a staleness level transition; the monitor loop resets to `.monitoring`
// on the next content change, which re-arms the next crossing.
if monitorState(for: presentationID) != newState {
    record(violation, resource: candidate.url, refreshIndex: refreshIndex)
}
setMonitorState(presentationID, newState)
```

New reader in `ValidationSession.swift` (next to `setMonitorState`):

```swift
func monitorState(for playlistID: String) -> MonitorState? {
    monitorStates[playlistID]
}
```

## Tests Added or Updated

- `LiveFaultScenarioTests/stalenessFindingsAreBoundedPerCrossing()` — a never-changing playlist
  driven over 10 refreshes records exactly 1 warning + 1 error staleness finding (== 2 total),
  not one per refresh. This is the direct regression guard for the flood.
- `LiveFaultScenarioTests/recoveryRearmsStaleness()` — stall → content advances (resets state) →
  stall again emits a *second* warning + error episode (2 warnings, 2 errors total), proving the
  transition policy re-arms after recovery rather than going silent.
- No existing test required updating: the prior staleness assertions use `contains` (presence of a
  warning and an error), which still hold under the bounded emission.

## Local Verification

- `BuildProject` (windowtab1, Valistream.xcworkspace) → built successfully, 0 errors.
- `RunSomeTests` (LiveFaultScenarioTests, InterruptedSessionTests, LiveMonitoringTests,
  StalenessDetectorTests) → 19/19 passed, incl. the 2 new tests.
- `RunAllTests` (full `Valistream` test plan) → 441/441 passed, 0 failed. Confirms no regression in
  the FROZEN-contract guards called out by the assessment (report schema, findings JSONL, incident
  timeline, exit-code / finalization suites).

## Deviations from Assessment

None. Implemented the assessment's **preferred** remediation (emit on state transition only). The
one not-explicitly-listed addition — the `monitorState(for:)` reader in `ValidationSession.swift` —
is exactly the "helper to read prior `MonitorState` if not already accessible" the assessment
anticipated under *Files likely to change* (the property is `private`).

Open questions resolved by the chosen approach: the durable artifacts are bounded to one finding
per severity crossing (warning + error), reset on the next content change.

## Follow-ups

- **Continuity findings** (`continuityChecker.check` loop in `ValidationSession+Monitoring.swift`)
  also call `record(...)` directly and can re-fire on a persistently broken stream (e.g. repeated
  `segment-stability` on the same retained sequence). Narrower than staleness (not guaranteed
  unbounded), but worth a separate `/speckit-bug-assess` if confirmed — flagged in the assessment's
  Risks section.
- Next: `/speckit-bug-test slug=staleness-finding-flood`.
