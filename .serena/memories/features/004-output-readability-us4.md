# Feature 004 US4 — README + 0.4.0 onboarding (DONE 2026-06-15)

Committed `c22ef27` "Feature 4. US4: README rewrite + 0.4.0 onboarding" on `main`. Tasks T045/T046/T049 [X]; T048/T050 left [ ] (live-binary/network verification — pending manual). Completes US1–US4 of feature 004 (`mem:features/004-output-readability-us1/us2/us3`).

## What shipped
- **Version 0.4.0 confirmed**: `MARKETING_VERSION = 0.4.0` (both pbxproj configs, lines 298 & 359); `CommandConfiguration.version = "0.4.0"`.
- **`ValistreamCommand.swift`**: added `discussion` copy (0.4.0 readable-output summary + migration note: `--select <pattern>`→`--preselect`, `--all` removed). No option-behavior change.
- **`README.md`** full rewrite to the `contracts/readme.md` structure: badges (version/platform/Swift — license OMITTED, no LICENSE file), prebuilt-zip primary + source-build secondary install, Homebrew marked unsupported, quick start (Apple BipBop stream), option reference (verified against ValistreamCommand `@Option`/`@Flag`), output modes, generated artifacts, examples (quiet/normal/verbose/no-color/`--json`/markdown/session-dir), exit codes 0/1/2/3/130, troubleshooting, limitations, links.

## Parent review fixes applied (post-worker)
1. **Repo slug was GUESSED wrong** by the worker (`volodymyr-akimenko/valistream`). Actual remote = `git@github.com:Lyse-AS/altibox-tv-valistream-hls.git`. Fixed all README URLs (release, clone, links) + clone dir → `Lyse-AS/altibox-tv-valistream-hls` / `altibox-tv-valistream-hls/Valistream`.
2. **`--json` example was inaccurate** (showed fabricated `schemaVersion`/`type:finding`/`playlistID`/`at` on a finding line, `state:"complete"`). Corrected to the real frozen shape: finding lines are bare `Finding` objects (id/ruleId/source/severity/category/resource/refreshIndex/observedAt/message/context — no `type`); status lines are `{"type":"status","state":"completed"}` (SessionState.completed rawValue = `completed`).

## Verified vs UNVERIFIED
- VERIFIED from source: version strings, option set + defaults + mutex pairs + hidden options (`--segments`/`--tolerance`), exit codes (frozen contract), artifact names, badge facts.
- UNVERIFIED (flagged, pending manual): live run of the BipBop quick-start stream against the 0.4.0 binary (no network headless); literal `valistream --help`/`--version` byte-diff (binary not run); GitHub Release `valistream-cli.zip` does NOT exist yet (README assumes it will be published at the release path). Human-output example strings are marked illustrative, not live-captured.

## Polish phase (T051–T056)
- DONE: T051 (regression gate — 439 tests green, build clean, 0 navigator warnings), T052 (badges verifiable), T053 (styling-disabled/width — `NonInteractiveOutputTests` green), T056 (conformance — navigator authoritative 0 warnings; serena LSP diagnostics are false positives here due to misconfigured module context).
- PENDING-MANUAL: T054 (acceptance vs user's private "TV Nord" live / "NRK news" VOD — URLs must stay out of committed artifacts), T055 (quickstart end-to-end) — both need network + live binary; cannot run headless.

## Feature 004 status
US1–US4 implemented + committed (`4ff434b` foundation, US1, `35cbc25` US2, `4ef8403` US3, `c22ef27` US4). All 439 Xcode tests green, 0 warnings, machine surfaces (`--json`/JSONL/schema v1/`.meta.json`/exit codes) frozen + guarded. Remaining: manual acceptance (T054/T055), publish GitHub Release for the prebuilt-zip install path, run `valistream --help` byte-diff (T050).
