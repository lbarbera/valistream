# Serena reference-search scope gotcha

Serena indexes **only the `ValistreamCore` SPM package**, not the app target (`Valistream/Valistream/`).

Consequence: `find_referencing_symbols` gives **false negatives** for references that live in the app target but point at `ValistreamCore` symbols.

Real case (report.md redesign): `PlaylistInfoFormatter.groups(for:)` showed 0 references via serena, suggesting it was dead and deletable. But `StatusRenderer.swift:238` (app target) calls it for stdout rendering. A plain `grep` caught it.

Rule: before deleting any `public`/`internal` ValistreamCore symbol as "unused", confirm with **grep across the whole repo** (incl. `Valistream/Valistream/`), not serena reference search alone.

Also: serena file paths need the `Valistream/` workspace prefix (e.g. `Valistream/ValistreamCore/Sources/...`), while `xcode-tools ExecuteSnippet` does not.
