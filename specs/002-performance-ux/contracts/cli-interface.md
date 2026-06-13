# Contract: CLI Interface (delta for 002-performance-ux)

This is the **delta** over feature 001's [cli-interface.md](../../001-hls-stream-validator/contracts/cli-interface.md).
Everything in the 001 contract still holds unless overridden here. The executable is invoked as
**`valistream`** (FR-001, SC-009).

## Executable name

- Binary/product name MUST be `valistream` (all lowercase) (FR-001).
- `valistream --help`, `valistream --version`, and the session-start banner MUST refer to the tool as
  `valistream` (SC-009).

## Options

### New in this feature

| Option | Arg | Default | Behavior |
|--------|-----|---------|----------|
| `--output <dir>` | path | platform default (below) | Base directory under which the per-session subfolder is created (US3, FR-016). Relative paths resolved to absolute (FR-020). *(May already exist from 001; semantics fixed here.)* |
| `--verbose` | — | off | Verbosity = verbose: adds per-request/diagnostic detail (FR-011). |
| `--no-color` | — | off | Force-disable color/styling even on a TTY (FR-009). |

### Confirmed / clarified (already present)

| Option | Behavior |
|--------|----------|
| `--quiet` | Verbosity = quiet: findings + errors only (FR-011). |
| `--select <pattern>` / `--all` | When supplied, the interactive selection prompt is skipped (FR-028). |
| `--limit <duration>` | Optional live time limit; expiry finalizes via the same clean path as graceful stop (FR-014). |
| `--json` | Machine-readable status stream on stdout (unchanged from 001). |

### Mutual exclusion

- `--quiet` and `--verbose` MUST NOT be combined → validation error, exit 2 (usage).

### Out-of-scope flags

- Segment/bandwidth flags (`--segments`, `--tolerance`) correspond to deferred work (spec §Out of
  scope). They MUST NOT be advertised as supported in 002; if retained, they are inert. Tasks decide
  hide vs remove (no behavior depends on them in 002).

## Default output location (FR-016)

- No `--output`: base = `~/.valistream/sessions/` on macOS; the platform data directory on non-macOS
  (`$XDG_DATA_HOME/valistream/sessions`, else `~/.local/share/valistream/sessions`).
- Per-session subfolder `<base>/<sessionID>` is unique and never overwrites existing content (FR-018).

## Startup behavior (ordering is part of the contract)

1. Parse + validate options (mutual exclusion above).
2. Resolve output base → absolute; create base if needed; verify writable. **On failure: fail fast,
   exit 2-class error, before any network fetch** (FR-019).
3. Print the **absolute** per-session folder path (FR-017, SC-005).
4. Begin fetching/validation.

## Graceful stop (FR-012–015)

- **First SIGINT** (interactive) / documented interrupt: begin graceful stop — cancel in-flight
  requests immediately, flush archive, finalize report (partial for one-shot, complete-for-period for
  live), announce shutdown + final paths. Completes ≤ 3 s (SC-003).
- The first-stop message MUST warn that a second interrupt forces immediate exit.
- **Second SIGINT** during shutdown: immediate termination, exit 130.
- Applies to **any** in-progress session (live or one-shot).

## Exit codes — FROZEN (FR-003, SC-010)

Unchanged from feature 001: `0` success/no findings · `1` findings present · `2` usage/precondition
error · `3` operational error · `130` forced interrupt (second stop / SIGINT abort). **No new exit
codes; no remapping.**

## Non-interactive / scriptable (FR-007, FR-028)

- No TTY, or selection supplied via `--select`/`--all`: no prompt is shown; documented default applied.
- Non-TTY output: no color, cursor control, or animation; progress as plain log lines (see
  [terminal-output.md](terminal-output.md)).
