# CLI Interface Contract: `valistream`

**Feature**: [../spec.md](../spec.md) | **Date**: 2026-06-12

The executable's user-facing contract. Changes to flags, exit codes, or output formats after release
follow semver (constitution Principle V).

## Synopsis

```text
valistream <playlist-url> [options]
```

`<playlist-url>` — HTTP/HTTPS URL of a master playlist (or media playlist, auto-detected — FR-002).
Required. Exactly one.

## Options

| Flag | Default | Meaning |
|------|---------|---------|
| `--segments` | off | Enable segment validation mode (FR-012) |
| `--tolerance <percent>` | `10` | Bandwidth deviation tolerance in percent (FR-012) |
| `--limit <duration>` | none | Live session time limit, e.g. `90s`, `15m`, `24h` (FR-015) |
| `--select <pattern>[,…]` | all | Pre-select playlists to monitor non-interactively; matches playlist id, group id, name, or URL substring (FR-018) |
| `--all` | — | Explicitly select all playlists, skipping the checklist prompt (FR-018) |
| `--non-interactive` | auto-on when stdout is not a TTY | Never prompt; implies `--all` unless `--select` given (FR-018) |
| `--output-dir <path>` | `./valistream-sessions` | Parent directory for session folders (FR-010) |
| `--json` | off | Machine output mode: findings as JSON Lines on stdout (see Output) |
| `--quiet` | off | Suppress live status; findings and summary only |
| `--version` / `--help` | — | Standard |

## Interactive checklist (FR-018)

After initial validation, on a TTY without `--all`/`--select`/`--non-interactive`: render the
discovered media playlists as a checkbox list (all pre-selected; arrows move, space toggles, enter
confirms, `a` toggles all). Non-TTY fallback: selection prompt is skipped, all selected.

## Output streams

- **Human mode (default)**: live status + findings to **stdout** (FR-009): session banner, stream
  classification (FR-005), per-playlist monitor state, running finding counts by severity; findings
  printed as they occur: `LEVEL [category/ruleId] resource — message`.
- **`--json` mode**: **stdout** carries one JSON object per line — finding objects (shape:
  `finding` in [session-report.schema.json](session-report.schema.json)) plus
  `{"type":"status",…}` heartbeat objects; human chrome goes to **stderr**.
- End of session (both modes): summary block + absolute path of the session folder and
  `report.json` / `report.md` (FR-015/016).

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Session completed; no error-severity findings (warnings/info allowed) |
| `1` | Session completed; at least one error-severity finding |
| `2` | Usage error: invalid URL/flags (no session folder created) |
| `3` | Fatal runtime failure: initial fetch impossible, storage failure mid-session (partial session folder preserved — US3 scenario 3) |
| `130` | Interrupted (SIGINT/SIGTERM); summary + report still written for the observed period (FR-015). Deliberately unified: `130` is returned for any termination signal, simplifying the shell `128+N` convention |

Automation contract: `0` vs `1` is the pass/fail signal for CI checks (Clarification #2 —
automation-friendly).

## Behavior invariants

- Every network request the process makes for the stream is archived (SC-004) — no hidden fetches.
- The tool never decodes/decrypts media (FR-013).
- Reload cadence per RFC 8216 §6.3.4 (research §4); the tool never polls faster.
- SIGINT triggers graceful cancellation: in-flight requests finish or cancel, archive flushes,
  report written, exit `130`.
