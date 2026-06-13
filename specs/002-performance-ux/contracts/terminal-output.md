# Contract: Terminal Output (002-performance-ux)

Governs on-screen rendering: color/styling, progress, message spacing, and verbosity. None of this
affects the report files or exit codes (FR-003, FR-011).

## Styling gate — FR-008, FR-009, SC-004

Color/styling is enabled **iff all** of:

- stdout is an interactive terminal (`isatty`), **and**
- the `NO_COLOR` environment variable is **unset**, **and**
- the user did **not** pass `--no-color`, **and**
- `TERM` is not `dumb`.

When disabled, output MUST contain **zero** SGR color, cursor-movement, or animation control sequences
(SC-004). Meaning MUST NOT be carried by color alone: severity is **always** also labeled in text
(`ERROR` / `WARN` / `INFO` / `OK`) (FR-009).

### Severity palette (when enabled)

| Kind | Text label | Color (advisory) |
|------|------------|------------------|
| error | `ERROR` | red |
| warning | `WARN` | amber/yellow |
| info | `INFO` | default/cyan |
| success | `OK` | green |

Palette chosen to stay legible on common light and dark themes (spec §Assumptions).

## Progress — FR-005, FR-006, FR-007, SC-001, SC-002

- The tool MUST continuously communicate (a) current activity in human terms and (b) overall progress
  (counts / percentage where a total is known), updated **≥ 1×/second** while work is ongoing (SC-001).
- **Interactive (TTY)**: a live, in-place indicator (spinner + activity + `N of M (xx%)`) that updates
  without flooding scrollback (FR-006). Discrete log lines (findings, milestones) print above the live
  line.
- **Non-interactive (pipe/file)**: progress emitted as discrete, plain, log-friendly lines — **no**
  color, cursor control, or animation characters (FR-007). The captured text is fully legible (SC-004).
- The interface MUST never appear frozen; the user can interrupt at any time (FR-002, SC-001).

## Message spacing — FR-010

Distinct logical output messages MUST be separated by blank line(s) so output reads as a running log,
not a dense block.

## Verbosity — FR-011

| Level | Flag | On-screen content |
|-------|------|-------------------|
| quiet | `--quiet` | findings + errors only |
| normal | (default) | current activity, progress, findings |
| verbose | `--verbose` | normal + per-request/diagnostic detail |

`--quiet` and `--verbose` are mutually exclusive. Verbosity MUST NOT affect the human-readable or
structured report files, nor the exit codes (FR-003, FR-011).

## Interactive prompts — FR-027, FR-028, FR-029

- On a TTY with no selection supplied, the playlist-selection step presents a navigable multi-select
  (arrow keys, space to toggle, **all pre-selected**, clear selection state, on-screen hints) (FR-027).
- Non-interactive, or selection supplied via `--select`/`--all`: **no prompt**; documented default
  (all) applied (FR-028).
- On cancel / interrupt while a prompt is open: the terminal MUST be restored to a sane state and the
  tool exits cleanly with a clear message (FR-029) — never leaving raw mode / a broken terminal.

## Edge cases (from spec §Edge Cases)

- Narrow/wide terminals: long values (URLs, paths) truncate/wrap gracefully; aliases keep the body
  compact.
- Output redirected mid-pipe: all animation/color/cursor control suppressed automatically.
- Color requested but terminal can't render it: degrade to plain text without error.
