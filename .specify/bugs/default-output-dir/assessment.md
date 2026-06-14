# Bug Assessment: Default output directory lands in the call-folder instead of `~/.valistream/sessions/`

- **Slug**: default-output-dir
- **Created**: 2026-06-14
- **Source**: pasted text + screenshot (`/Users/volodymyr.akimenko/Desktop/Screenshot 2026-06-14 at 21.56.26.png`)
- **Verdict**: valid
- **Severity**: medium

## Report (verbatim or summarized)

> Artifacts seems to still be stored into cli call-folder. Instead of default ./valistream/sessions. See the bottom of screenshot from macOS Terminal.

Screenshot tail (session completion line):

```
Session completed: 0 errors, 11 warnings, 6 info.
Artifacts: /Users/volodymyr.akimenko/Library/Developer/Xcode/DerivedData/Valistream-axpjjxqwgvtygpgtjqnskcfww/Build/Products/Debug/Valistream-sessions/20260614-215115-F327/
volodymyr.akimenko@RWM-DTQKJLQTJ3 Debug %
```

The shell prompt (`… Debug %`) shows the working directory at run time was the DerivedData `Build/Products/Debug` folder. The artifacts were written to `<cwd>/Valistream-sessions/<session-id>/` — i.e. relative to the current working directory (the "cli call-folder") — rather than to the documented default base `~/.valistream/sessions/`.

## Symptom

When `valistream` is run **without** an explicit output directory, the session's evidence/report folder is created under the current working directory (`./valistream-sessions/<session-id>/`) instead of the documented default user-data location `~/.valistream/sessions/<session-id>/`. Expected behavior (per feature 002, FR-016/FR-018): with no `--output-dir`, the base MUST be `~/.valistream/sessions/` on macOS.

## Reproduction

1. From any directory (e.g. the Xcode `Build/Products/Debug` dir, as in the screenshot), run `valistream <master-url>` **without** passing `--output-dir`.
2. Let the session complete.
3. Read the final `Artifacts:` line.
4. Observe the path is `<cwd>/valistream-sessions/<session-id>/`, not `~/.valistream/sessions/<session-id>/`.

## Suspected Code Paths

- `Valistream/Valistream/Valistream/ValistreamCommand.swift:104` — `var outputDir: String = "./valistream-sessions"`. The `--output-dir` option carries a non-nil literal default, so the "omitted" case is never `nil`.
- `Valistream/Valistream/Valistream/ValistreamCommand.swift:169` — `outputDir: URL(fileURLWithPath: outputDir)` unconditionally wraps that literal into the `SessionConfig`, so a concrete relative URL is always passed downstream.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/SessionConfig.swift:45` — `outputDir: URL = URL(fileURLWithPath: "./valistream-sessions")`. Same stale legacy default at the Core API boundary; non-CLI/test callers also miss the platform default.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift:149` — `OutputLocation.resolve(outputDir: config.outputDir, sessionID: id)` passes the (always non-nil) `config.outputDir`.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/OutputLocation.swift:31-35` — `resolve(outputDir: URL?, …)` is explicitly designed to fall back: `var base = outputDir ?? defaultBase()`. Because the caller never passes `nil`, the `defaultBase()` branch is dead code in practice.
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/OutputLocation.swift:16-19` — `defaultBase()` correctly returns `~/.valistream/sessions/`; this is the value that should be used and currently is not.

## Root Cause Hypothesis

**Confidence: high.** This is a regression from the feature 002 change that moved the default output base from 001's `./valistream-sessions` to the user-data location `~/.valistream/sessions/`. The Core `OutputLocation` was updated (it has `defaultBase()` and a `nil`-coalescing fallback), but the two upstream defaults that feed it — the CLI `--output-dir` option default and `SessionConfig.outputDir`'s default — still hold the legacy literal `"./valistream-sessions"`. Because a concrete relative URL is always supplied, `OutputLocation.resolve` never sees `nil`, never calls `defaultBase()`, and resolves the relative path against the current working directory (FR-020), placing artifacts in the call-folder. (Minor cosmetic: the on-disk folder shows as `Valistream-sessions` because macOS APFS is case-insensitive and preserves the case of whatever created the directory first; the literal in code is lowercase.)

## Proposed Remediation

**Preferred**: Thread the "omitted" state through as `nil` so `OutputLocation.resolve` reaches its already-correct `defaultBase()` fallback.

1. `ValistreamCommand.swift:104` — change to `var outputDir: String?` with **no** default (omitted flag → `nil`).
2. `ValistreamCommand.swift:169` — pass `outputDir.map { URL(fileURLWithPath: $0) }` (i.e. `URL?`) into the config.
3. `SessionConfig.swift:45` — change `outputDir` to `URL?` defaulting to `nil`, and update the stored property/initializer accordingly.
4. `ValidationSession.swift:149` — no change needed; `config.outputDir` (now `URL?`) flows straight into `OutputLocation.resolve(outputDir:)`, which already coalesces to `defaultBase()`.

This keeps the single source of truth for the default (`OutputLocation.defaultBase()`), matches the design intent of the `?? defaultBase()` line, and fixes both the CLI and any direct Core consumers.

**Alternatives**:
- *Non-optional, retarget the literal*: keep the types non-optional but change both legacy defaults from `"./valistream-sessions"` to `OutputLocation.defaultBase()`. Smaller type churn, but it duplicates the default in two places (DRY risk) and leaves the `?? defaultBase()` branch dead — the next person can reintroduce the same bug. Not recommended.
- *CLI-only patch*: make only `ValistreamCommand.outputDir` optional and pass `nil`/`URL?` to a still-`URL` `SessionConfig` by retargeting `SessionConfig`'s default to `defaultBase()`. Fixes the user-visible symptom but leaves `SessionConfig`'s API able to default-to-CWD for library callers.

**Files likely to change**:
- `Valistream/Valistream/Valistream/ValistreamCommand.swift`
- `Valistream/ValistreamCore/Sources/ValistreamCore/Session/SessionConfig.swift`
- (verify only, likely no change) `Valistream/ValistreamCore/Sources/ValistreamCore/Session/ValidationSession.swift`
- `Valistream/ValistreamCore/Tests/ValistreamCoreTests/Session/OutputLocationTests.swift` (add case) and/or a CLI/integration test

**Tests to add or update**:
- Core: assert that `OutputLocation.resolve(outputDir: nil, sessionID:)` produces a `baseDirectory` under `~/.valistream/sessions/` (the omitted-flag path). `OutputLocationTests.swift:70` already verifies `defaultBase()` contains the `valistream/sessions` components — extend it to cover the `nil` → default wiring via `resolve`.
- Config/CLI: assert that constructing `SessionConfig` without an `outputDir` yields `nil` (or the default base), and that the `--output-dir`-omitted path does not resolve to CWD.
- Regression guard: a test that fails if the default ever resolves relative to `FileManager.currentDirectoryPath` again.

## Risks & Considerations

- **Public API change**: making `SessionConfig.outputDir` optional (`URL` → `URL?`) is a source-breaking change for any in-repo callers/tests that read it as non-optional. Sweep references before editing. Not part of the FROZEN surface (JSON report schema, rule IDs, exit codes are untouched), and the feature is pre-1.0 shipping 0.3.0, so a Core API change is acceptable — but update all call sites and the report builder.
- **Report output**: `SessionReportBuilder.swift:341` reads `session.config.outputDir.path(...)` for the report's `outputDir` field. If that becomes optional it must render the *resolved* absolute base instead (prefer reading the already-resolved `OutputLocation.baseDirectory`), otherwise the report could show `nil`/empty. Verify the reported path matches the actual artifact path after the fix.
- **Behavioral change for existing users/scripts**: anyone relying on the current (buggy) `./valistream-sessions` drop will now find artifacts in `~/.valistream/sessions/`. This is the documented, intended behavior, but call it out in the 0.3.0 migration notes.
- **Help text**: `--output-dir` help on line 103 should state the default is `~/.valistream/sessions/` (currently it does not mention a default).

## Open Questions

- [NEEDS CLARIFICATION: Should the 0.3.0 migration notes explicitly mention that the default artifact location moved off the working directory, given users may have been depending on the buggy CWD behavior?]
