# Bug Verification: Default output directory lands in the call-folder instead of `~/.valistream/sessions/`

- **Slug**: default-output-dir
- **Tested**: 2026-06-14
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The original symptom no longer reproduces. Running the freshly built `valistream` binary from an arbitrary working directory with no `--output-dir` now writes artifacts to `~/.valistream/sessions/<session-id>/` and creates nothing in the call-folder. The end-to-end reproduction was actually exercised (the real binary, not tests alone), and the new/updated unit tests pass.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | Ran `valistream http://127.0.0.1:1/master.m3u8` from a fresh temp CWD, no `--output-dir` | pass | `Artifacts:` printed `~/.valistream/sessions/20260614-222025-e228/`; temp CWD contained only `.`/`..` — no `valistream-sessions/` created in the call-folder. |
| Binary freshness | Compared `valistream` mtime (22:12:33) vs edited sources (22:10–22:11) | pass | `BuildProject` rebuilt the executable after the fix, so the repro exercised fixed code. |
| New / updated tests | `RunSomeTests` → `SessionConfigTests`, `OutputLocationTests/nilOutputDirUsesDefaultBase()` | pass | 3/3 passed. |
| Impacted suites (fix step) | `RunSomeTests` → `SessionConfigTests`, `OutputLocationTests`, `FinalizationTests`, `OutputLocationStartupTests`, `EvidenceInOutputTests` | pass | 20/20 passed. |
| Build | `BuildProject` (windowtab1) | pass | Built successfully, 0 errors. |
| Full 312-test suite | `RunAllTests` | skipped | Not run; impacted suites green. Recommend a full run before release. |
| Live end-to-end (real stream) | n/a | not-run | Network-dependent. Not required: `OutputLocation.resolve` creates the base **before** any fetch (`OutputLocationStartupTests/folderResolvedBeforeFetch`), so the refused-connection run exercises the exact bug locus. |

## Output Excerpts

Reproduction run (from temp CWD, no `--output-dir`):

```
Output: /Users/volodymyr.akimenko/.valistream/sessions/20260614-222025-e228/
• fetchingMaster
[ERROR] master_0 — no body captured for master
• failed
Session failed: 1 error(s), 0 warning(s), 0 info.
Artifacts: /Users/volodymyr.akimenko/.valistream/sessions/20260614-222025-e228/
```

Temp CWD after the run: `.  ..` (no `valistream-sessions/`). New dir under `~/.valistream/sessions/`: `20260614-222025-e228` (removed during cleanup).

Tests:

```
3 tests: 3 passed, 0 failed   (SessionConfigTests + nilOutputDirUsesDefaultBase)
20 tests: 20 passed, 0 failed (impacted suites, fix step)
```

## Residual Risks

- **Non-macOS default base** (`$XDG_DATA_HOME/valistream/sessions`) was not exercised — tested on macOS only. `OutputLocation.defaultBase()` for non-macOS is unchanged by this fix.
- **Full regression suite** (312 tests) not run here; only impacted suites. Low risk — the change is additive/optional-typed and tests pin both default and explicit paths.
- The reproduction used a connection-refused URL; a fully successful live session was not run, but folder resolution (the bug locus) completes before fetch, so this does not affect the verdict.

## Recommendation

Close the bug — verified end-to-end. The default now resolves to `~/.valistream/sessions/` and never to the working directory; new regression tests lock it in. Suggested pre-release follow-up: one full `RunAllTests` pass and add the default-location change to the 0.3.0 migration notes.
