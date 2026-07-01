# Changelog

## [0.8.0] - 2026-07-01

### New Dependency

- **Textual is now a runtime dependency**: the new dashboard design requires the Textual library. Make sure it is installed by running `pip install textual` before launching Valistream 0.8.0.

### Changed

- **Live monitoring dashboard migrated from `rich.Live` to Textual**: the terminal dashboard is now a full-screen Textual app. This makes the **Recent Errors panel genuinely scrollable** — scroll with the mouse wheel, or with the arrow keys / Page Up / Page Down (the panel is focused on start). The panel keeps a 1000-line scrollback instead of showing only the most recent handful, and its border always renders correctly regardless of how full it is (superseding the 0.7.3 workaround). Press `q` or `Ctrl+C` to stop.
- **Recent Errors panel border restyled** from red to a subdued blue-gray, reducing visual noise now that the border is always present.

### Added

- `textual>=0.60` runtime dependency.

### Fixed

- **`--version` now reports the correct version**: `valistream/__init__.py` held a hardcoded `__version__` that was not bumped alongside `pyproject.toml`, so 0.7.3 reported `0.7.2`. Both are now kept in sync.

## [0.7.3] - 2026-07-01

### Fixed

- **Terminal dashboard Recent Errors panel border rendering**: fixed visual artifact where the bottom border would disappear and be replaced with "..." when the error panel reached capacity. The maximum displayed errors reduced from 10 to 9 to ensure adequate space for border rendering.

## [0.7.2] - 2026-06-30

### Fixed

- **Terminal dashboard times now display in local timezone**: status timestamps and error messages previously showed UTC times; they now display in the user's local timezone for better readability.

## [0.7.1] - 2026-06-29

### Fixed

- **Duplicate rendition display in terminal dashboard**: when two renditions share the same resolution but have different bandwidths, they now appear as separate rows rather than being conflated into one. The bandwidth in Mbps (e.g. `5.0Mbps`) is appended to the label only for the affected renditions.
- **"Refreshes" column header shortened to "Refs"** to give the Rendition column more room when a bandwidth suffix is present, keeping each row on a single line.

### Changed

- `RenditionStatus.alias` renamed to `label` (the string shown in the Rendition column).
- `LiveDisplay._statuses` is now keyed by rendition URI instead of alias, ensuring uniqueness when multiple renditions share an alias.
- `LiveDisplay.get_status()` and `LiveDisplay.add_error()` now accept a rendition URI instead of an alias.
- New `LiveDisplay.add_renditions()` batch method handles disambiguation of labels across all selected renditions.

## [0.7.0] - 2026-06-28

- Terminal dashboard improvements (see release notes).
