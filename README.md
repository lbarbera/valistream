# valistream

![Version](https://img.shields.io/badge/version-0.4.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)

**valistream** validates and monitors HLS streams against RFC 8216 and Apple
HLS authoring rules. It fetches every master and media playlist in a stream,
runs a rule engine across them, and reports findings — warnings or errors —
with severity, rule ID, and evidence. During live monitoring it watches for
staleness, continuity failures, and playlist lifecycle changes, and writes a
durable session archive to disk.

---

## Motivation

HLS delivery failures are often invisible until viewers complain. Broken
`#EXT-X-STREAM-INF` bandwidth attributes, mismatched codec declarations,
stale segments, and missing discontinuity sequence tags do not cause hard
errors in most players — they cause silent degradation, adaptive-bitrate
thrash, or playback stalls. valistream makes these defects visible before or
while they affect viewers, with enough context (rule ID, evidence snapshot
path, occurrence timestamp) to diagnose and reproduce them.

---

## Key capabilities

- Validates master and media playlists against RFC 8216 and Apple HLS
  authoring rules (bandwidth, URI, codecs, target duration, segment count,
  duplicate URIs, independent segments, iframe playlists, variant ladder).
- Live monitoring with RFC 8216 §6.3.4 refresh scheduling, staleness
  detection (>1.5× target duration warning, >3× error), and continuity
  checks (media sequence regression, head removal, segment stability,
  discontinuity insertion and sequence regression).
- Three human-readable output tiers — quiet, normal, verbose — plus a
  machine-readable `--json` stream.
- Timestamped terminal messages (`[HH:mm:ss.SSS]`) and a structured Markdown
  report with an incident timeline, severity-grouped findings, and a playlist
  information block (protection, codec, resolution, segment duration stats).
- Per-session archive: fetched playlist snapshots with `.meta.json` sidecars,
  an append-only findings log, and both a JSON and a Markdown report.
- Interactive multi-select checklist for choosing which renditions to monitor,
  with `--preselect` for scripted/unattended runs.

---

## How it works

1. **Discovery** — valistream fetches the URL you provide. If it is a master
   playlist it discovers every variant stream, audio rendition, subtitle track,
   and I-frame playlist. If it is a media playlist it is used directly.

2. **Selection** — On an interactive terminal you see a multi-select checklist
   of all discovered renditions (pre-selected). Confirm to proceed, or use
   `--preselect` to select by pattern without a prompt.

3. **Validation** — The rule engine evaluates every fetched playlist and
   reports findings: errors (rule violation) and warnings (advisory).

4. **Live monitoring** — For live/event streams valistream reloads each
   selected media playlist on the RFC 8216 schedule (initial delay = target
   duration; reloads: changed = target duration, unchanged = target
   duration ÷ 2). Continuity and staleness are checked on every reload.

5. **Evidence capture** — Every fetched playlist snapshot is saved to the
   session archive folder. Findings reference the snapshot they were derived
   from by ID so you can inspect the exact bytes.

6. **Report** — When the session ends (stream finished, `--limit` reached, or
   Ctrl-C), valistream writes `report.md` and `report.json` to the session
   folder. The Markdown report contains an incident timeline, findings grouped
   by severity and category, a playlist information block, and an artifact
   legend.

---

## Quick start

> **Note:** The command below uses Apple's public BipBop reference stream —
> a stable, credential-free HLS test stream published by Apple for developer
> testing. Substitute any `http://` or `https://` master or media playlist URL.
>
> Live verification of this stream against the 0.4.0 binary is a **deferred
> manual step** (the build environment has no network access). If the stream
> is unreachable, use any other stable public HLS URL.

```
# 1. Install (see Installation below)

# 2. Validate the Apple BipBop reference stream
valistream https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8

# 3. The session folder path is printed at startup, e.g.:
#    [10:04:22.381] Ready: session output folder is ~/.valistream/sessions/2026-06-15T100422-abc123/
#
# After validation completes:
#    ~/.valistream/sessions/2026-06-15T100422-abc123/
#    ├── report.md
#    ├── report.json
#    ├── findings.jsonl
#    └── playlists/
#        ├── master/
#        │   └── 000001.m3u8  (+ 000001.meta.json)
#        └── video-1080p/
#            └── 000001.m3u8  (+ 000001.meta.json)
```

---

## Installation

### Primary: prebuilt binary (recommended)

Download the prebuilt `valistream-cli.zip` from the
[GitHub Releases page](https://github.com/Lyse-AS/altibox-tv-valistream-hls/releases/tag/0.4.0).

```
# Unzip and make executable
unzip valistream-cli.zip
chmod +x valistream
# Move to a directory on your PATH, e.g.:
mv valistream /usr/local/bin/valistream
```

> **Supported platforms**: macOS 14 (Sonoma) and later, Apple Silicon and Intel.
> **Unsupported**: Linux, Windows — not built or tested.

### Secondary: build from source

**Prerequisites**

- macOS 14 or later
- Xcode 16 or later (provides Swift 6)
- Command Line Tools: `xcode-select --install`

**Steps**

```
git clone https://github.com/Lyse-AS/altibox-tv-valistream-hls.git
cd altibox-tv-valistream-hls/Valistream
xcodebuild -workspace Valistream.xcworkspace \
           -scheme Valistream \
           -configuration Release \
           -derivedDataPath .build
cp .build/Build/Products/Release/valistream /usr/local/bin/valistream
```

### Unsupported channels

Homebrew and other package managers are **not supported** for this release.
Do not install via `brew install` — no formula is published.

---

## Usage

```
valistream <url> [options]
```

`<url>` must be an `http://` or `https://` URL to a master playlist or a
media playlist (auto-detected).

---

## Option reference

All options accepted by `valistream 0.4.0`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `<url>` | Argument | — | HTTP/HTTPS URL of a master playlist (or media playlist, auto-detected). Required. |
| `--limit <duration>` | Option | none | Cap a live session. Accepts `90s`, `15m`, `24h`. When omitted, the session runs until the stream ends or Ctrl-C. |
| `--preselect <patterns>` | Option | none | Comma-separated patterns (matched against rendition ID, group ID, name, or URL) to pre-select a subset of renditions. No prompt is shown. Unattended/scriptable. Formerly `--select <pattern>` (≤0.2.0). |
| `--select` | Flag | off | Open the interactive multi-select checklist with all renditions pre-selected. Requires a TTY; on non-TTY falls back to processing all renditions. Cannot be combined with `--preselect`. |
| `--non-interactive` | Flag | off | Never prompt; process all renditions without interaction. |
| `--output <dir>` | Option | `~/.valistream/sessions/` | Parent directory for session folders. Relative paths are resolved to absolute. |
| `--json` | Flag | off | Machine-readable output: findings and status objects as JSON Lines on stdout. |
| `--quiet` | Flag | off | Suppress live status; emit only findings and the final summary. |
| `--verbose` | Flag | off | Show extended detail: raw per-request timings, all HTTP headers, and trace diagnostics. |
| `--no-color` | Flag | off | Disable all terminal color output. Also honored via the `NO_COLOR` environment variable or `TERM=dumb`. |

**Mutually exclusive pairs**

- `--quiet` and `--verbose` cannot be combined (exit 2).
- `--select` and `--preselect` cannot be combined (exit 2).

---

## Output modes

| Mode | When to use | How to invoke |
|------|-------------|---------------|
| **Normal** (default) | Interactive monitoring — colored, timestamped, progress heartbeat. | _(no flags)_ |
| **Quiet** | Concise review or CI — findings and summary only, no live status. | `--quiet` |
| **Verbose** | Diagnosis — adds per-request trace lines and extended metadata. | `--verbose` |
| **No-color / redirected** | Piped output, log files, terminals without color support. | `--no-color`, `NO_COLOR=1`, `TERM=dumb`, or redirect stdout |
| **Structured JSON** | Automation, integration, log ingestion. | `--json` |

When stdout is not a TTY (piped or redirected) valistream automatically
disables color and the interactive prompt without requiring explicit flags.

---

## Generated artifacts

Every run creates a timestamped session folder under `--output`
(default `~/.valistream/sessions/<sessionID>/`). The path is printed at
startup before any network activity.

| File | Description |
|------|-------------|
| `report.md` | Human-readable Markdown: incident timeline, findings by severity, playlist information block, legend. |
| `report.json` | Machine-readable findings (schema v1). |
| `findings.jsonl` | Append-only JSON Lines log. Written incrementally — durable on interrupt (Ctrl-C). |
| `playlists/<id>/NNNNNN.m3u8` | Fetched playlist snapshot. `<id>` is a stable alias (e.g. `video-1080p`, `audio-en`). |
| `playlists/<id>/NNNNNN.meta.json` | Sidecar with fetch metadata (URL, HTTP status, timing, refresh index). |

---

## Examples

All excerpts below are illustrative — representative of 0.4.0 output format
and structure. They are **not live-captured** output (live-run verification
against a real stream is a deferred manual step; see Quick start note above).
Inputs, IDs, and paths are sanitized and stable.

### Normal mode (interactive TTY)

```
[10:04:22.381] Ready: session output folder is ~/.valistream/sessions/2026-06-15T100422-abc123/

[10:04:22.410] example-stream
               master  https://example.com/stream/master.m3u8
               Protection    None
               Variants      3

[10:04:22.540] video-1080p  https://example.com/stream/1080p/playlist.m3u8
               Role          Variant  1080p  H.264
               Protection    None
               Target dur.   6 s  ·  observed median 5.9 s  (min 5.8 s  max 6.0 s)

● Refresh 1 · video-1080p · no findings.

⚠ Refresh 2 · video-1080p · 1 warning
  [10:04:34.210] ⚠ WARNING  TOOL.staleness
                 Playlist has not been updated for 9.1 s (target duration 6 s, threshold 1.5×).
                 Evidence: video-1080p_000002

[10:04:40.310] Session complete · 2 refreshes · 1 warning · elapsed 18.2 s
               Saved session: ~/.valistream/sessions/2026-06-15T100422-abc123/
```

### Quiet mode (`--quiet`)

```
[10:04:34.210] ⚠ WARNING  TOOL.staleness
               Playlist has not been updated for 9.1 s (target duration 6 s, threshold 1.5×).
               Evidence: video-1080p_000002

[10:04:40.310] Session complete · 2 refreshes · 1 warning · elapsed 18.2 s
               Saved session: ~/.valistream/sessions/2026-06-15T100422-abc123/
```

### Verbose mode (`--verbose`)

Verbose adds trace lines for every fetch and refresh scheduling decision,
nested under a context header. Example trace block:

```
[10:04:22.395] video-1080p  000001
               Fetch started: https://example.com/stream/1080p/playlist.m3u8
[10:04:22.410] ✔ Validated  video-1080p  000001 · no findings.
[10:04:22.412]   Refresh scheduled: next in 6.0 s
```

### No-color / redirected output

When stdout is not a TTY (or `--no-color` / `NO_COLOR=1` is set), all ANSI
color codes and cursor-control sequences are stripped. Severity markers
fall back to ASCII (`[OK]`, `[WARN]`, `[ERR]`). The output is otherwise
identical in structure.

```
[10:04:34.210] [WARN] TOOL.staleness
               Playlist has not been updated for 9.1 s (target duration 6 s, threshold 1.5×).
               Evidence: video-1080p_000002
```

### Structured JSON (`--json`)

`--json` writes one JSON object per line to stdout (NDJSON / JSON Lines).
Each stdout line is either a finding object (schema v1) or a status event;
findings carry no `type` field, status events are tagged `"type":"status"`.
stderr carries human-readable progress messages (roster, refresh, trace).

```json
{"id":"F-001","ruleId":"TOOL.staleness","source":"tool","severity":"warning","category":"delivery","resource":"https://example.com/stream/1080p/playlist.m3u8","refreshIndex":2,"observedAt":"2026-06-15T10:04:34Z","message":"Playlist has not been updated for 9.1 s (target duration 6 s, threshold 1.5×).","context":{}}
{"type":"status","state":"completed"}
```

### Markdown report excerpt

```markdown
## Summary

Session completed normally. 1 warning found across 2 refreshes.

## Incident Timeline

| Time | Event | Ref |
|------|-------|-----|
| 2026-06-15T10:04:34.210+02:00 | ⚠ Warning — TOOL.staleness | [Finding F-001](#finding-f-001) |

## Findings

### ⚠ Warning

#### Finding F-001

> [!WARNING]
> **TOOL.staleness** — Playlist has not been updated for 9.1 s (target duration 6 s, threshold 1.5×).

- **Playlist**: `video-1080p`
- **Refresh**: 2
- **Evidence**: `video-1080p_000002`
```

### Session directory layout

```
~/.valistream/sessions/2026-06-15T100422-abc123/
├── report.md
├── report.json
├── findings.jsonl
└── playlists/
    ├── master/
    │   ├── 000001.m3u8
    │   └── 000001.meta.json
    ├── video-1080p/
    │   ├── 000001.m3u8
    │   ├── 000001.meta.json
    │   ├── 000002.m3u8
    │   └── 000002.meta.json
    └── audio-en/
        ├── 000001.m3u8
        └── 000001.meta.json
```

---

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Validated — no findings (or only info-level findings). |
| `1` | Validated — one or more error-severity findings. |
| `2` | Usage or pre-condition error (invalid URL, bad option combination, unwritable output directory). |
| `3` | Operational error (network failure, unreadable playlist, unexpected internal error). |
| `130` | Graceful interrupt — second Ctrl-C during graceful shutdown, or SIGTERM received. |

---

## Troubleshooting

**"invalid URL" on startup (exit 2)**
The URL must begin with `http://` or `https://`. Bare hostnames and `file://`
URLs are not accepted.

**"--select and --preselect cannot be combined" (exit 2)**
These flags are mutually exclusive. Use `--preselect <patterns>` for
scripted/unattended runs; use `--select` to open the interactive checklist.

**"--quiet and --verbose cannot be combined" (exit 2)**
Choose one output tier. For diagnosis use `--verbose`; for CI/automation use
`--quiet` or `--json`.

**Exit 3 — operational error**
A network failure or an unreadable playlist caused the session to fail. Check
that the URL is reachable, the server returns valid HLS, and you have network
access. The session folder and `findings.jsonl` (if any findings were recorded
before the failure) are still written.

**No interactive prompt shown**
The prompt is skipped automatically when stdout is not a TTY (piped or
redirected), when `--non-interactive` is passed, or when `--preselect` or
`--select` is used. Pass `--select` explicitly on an interactive terminal to
force the checklist.

**Color output when piped (`--no-color`)**
valistream detects TTY automatically. If ANSI codes still appear (e.g. in a
terminal multiplexer), set `NO_COLOR=1` or pass `--no-color`.

---

## Limitations and platform support

- **macOS only.** valistream is built and tested on macOS 14 (Sonoma) and
  later. Linux and Windows are not supported.
- **HTTP/HTTPS only.** Only `http://` and `https://` URLs are accepted.
  Local file paths and `file://` URLs are not supported.
- **Credential-free streams only.** No authentication support. Streams behind
  token-signed URLs, cookie auth, or certificate-based auth are not accessible.
- **Manifest validation only.** Segment-level validation (TS/fMP4 content,
  DRM license exchange, audio/video decode) is outside scope.
- **Live run in headless environments.** The interactive multi-select prompt
  requires a TTY. In CI or scripted environments, use `--non-interactive` or
  `--preselect`.

---

## Links

- [RFC 8216 — HTTP Live Streaming](https://datatracker.ietf.org/doc/html/rfc8216)
- [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)
- [GitHub Releases](https://github.com/Lyse-AS/altibox-tv-valistream-hls/releases)
