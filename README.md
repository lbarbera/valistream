# valistream

![Version](https://img.shields.io/badge/version-0.4.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![Coverage](https://img.shields.io/badge/coverage-96%25-brightgreen)

Validates and monitors HLS playlists (live & vod) against RFC 8216 and Apple HLS authoring rules.

📥 Fetches every master/media-playlist → **validates agains HLS specs**

📺 Follows Live stream playlist refresh logic → **validates continuity**

📝 Writes whole session logs and all artifacts to disk for **evidence**

🗒️ Generates full session **report**

---

## Quick start

### On MacOS

**Homebrew**
```bash
brew tap volodymyrai/valistream
brew trust volodymyrai/valistream
brew install valistream

valistream --version # verify it was installed
```

Then just call it like:

```bash
valistream "<.m3u8 URL here>"

or

valistream "<.m3u8 URL here>" --preselect 720p,audio,subs # to monitor only these

or

USAGE: valistream <url> [--limit <limit>] [--preselect <preselect>] [--select] [--non-interactive] [--output-dir <output-dir>] [--json] [--quiet] [--verbose] [--no-color]

ARGUMENTS:
  <url>                   HTTP/HTTPS URL of a master playlist (or media playlist, auto-detected).

OPTIONS:
  --limit <limit>         Live session time limit, e.g. 90s, 15m, 24h.
  --preselect <preselect> Pre-select a subset of renditions (comma-separated patterns matching ID, group, name, or URL).
        Unattended/scriptable; no prompt is shown. Formerly --select <pattern> (≤0.2.0).
  --select                Open the interactive multi-select checklist with all renditions pre-selected.
        Requires a TTY; on non-TTY falls back to processing all renditions. Cannot be combined with --preselect.
  --non-interactive       Never prompt; process all renditions without interaction.
  --output-dir <output-dir>
                          Parent directory for session folders. Defaults to ~/.valistream/sessions/.
  --json                  Machine output: findings as JSON Lines on stdout.
  --quiet                 Suppress live status; findings and summary only.
  --verbose               Show extended detail: raw timestamps, all HTTP headers.
  --no-color              Disable all terminal color output (also honored via NO_COLOR env).
  --version               Show the version.
  -h, --help              Show help information.
```

### On Windows

_Not yet supported 🤞_

## Generated artifacts

Every run creates a timestamped session folder under `--output-dir`
(default `~/.valistream/sessions/<sessionID>/`)

| File | Description |
|------|-------------|
| `report.md` | Human-readable Markdown: incident timeline, findings by severity, playlist information block, legend. |
| `report.json` | Machine-readable findings (schema v1). |
| `findings.jsonl` | Append-only JSON Lines log. |
| `playlists/<id>/NNNNNN.m3u8` | Fetched playlist snapshot. `<id>` is a stable alias (e.g. `video-1080p`, `audio-en`). |
| `playlists/<id>/NNNNNN.meta.json` | Sidecar with fetch metadata (URL, HTTP status, timing, refresh index). |

---

## Links

- [RFC 8216 — HTTP Live Streaming](https://datatracker.ietf.org/doc/html/rfc8216)
- [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)
