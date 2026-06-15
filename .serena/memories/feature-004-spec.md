# Feature 004 — Readable Output and Onboarding (SPECIFIED)

Created 2026-06-14 at `specs/004-output-readability/spec.md`; active feature pointer updated in `.specify/feature.json`. Product version is 0.4.0. No plan was requested or created.

## Scope
- Improve human-readable terminal output in quiet, normal, and verbose modes through semantic visual roles, emphasis hierarchy, natural-language messages, contiguous operation/finding blocks, deliberate whitespace, wrapping, and prominent final summaries.
- Normal: one persistent result per successful playlist refresh; omit low-level request/rule/archive/scheduling detail unless actionable.
- Quiet: findings, required notices/failures, shutdown state, final summary only; findings grouped by playlist/snapshot.
- Verbose: retain all existing diagnostic categories, nested under phase or playlist/snapshot context and visually subordinate to primary outcomes.
- Improve Markdown report navigation and hierarchy; errors before warnings; evidence stays adjacent.
- Rewrite README as verified GitHub-style onboarding: why, capabilities, workflow, quick start, supported installation/source build, full public options, mode guidance, realistic examples, artifacts, exits, troubleshooting, platform limits.
- User will provide a realistic live stream URL before manual acceptance; never commit sensitive/signed URLs without explicit publication approval.

## Frozen / out of scope
Feature 003 contracts remain authoritative: no changes to validation rules/findings/severities, IDs, evidence resolution, selection semantics, structured report data/schema/values, JSONL behavior, or exit codes. Human presentation and README only; machine output compatibility verification only. No new distribution channels/platform claims/themes/localization/GUI.

## Accessibility/readability additions
Color reinforces but never carries meaning alone; plain text is baseline. Honor existing styling gates (`NO_COLOR`, `--no-color`, non-TTY, limited terminal). No styling/control bytes in plain output or reports. Symbols need text/fallback. Important content must wrap without loss at 80/120 columns.

## Clarifications completed (2026-06-15)
Seven decisions are encoded under `## Clarifications` in the spec:
1. Normal mode persists one concise result for every successful refresh.
2. Every human-readable terminal message is timestamped using compact local `[HH:mm:ss.SSS]`; report events use full local ISO 8601 with milliseconds and numeric UTC offset.
3. Timestamps represent event occurrence time and the same recorded instant is reused across terminal/report representations.
4. Markdown adds an incident-focused chronological timeline for findings, failures, interruption/shutdown, and playlist lifecycle events; routine successful refreshes are excluded.
5. Full findings remain in severity-grouped sections; compact timeline entries link to them without duplicating messages/evidence.
6. Playlist lifecycle events are unavailable, recovered, added, removed, and identity-changed events.
7. Equal-timestamp incident entries preserve recorded event sequence.

## Quality
`specs/004-output-readability/checklists/requirements.md` remains 16/16 passing after clarification. No NEEDS CLARIFICATION markers.