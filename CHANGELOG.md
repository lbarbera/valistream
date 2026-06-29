# Changelog

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
