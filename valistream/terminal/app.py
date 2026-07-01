"""Textual TUI app for the live monitoring dashboard.

The app owns three widgets:

* :class:`ScannerWidget` — the KITT-style animated bar, refreshed on a timer.
* :class:`StatusTable`   — the per-rendition status table, refreshed on a timer.
* :class:`RichLog`       — the scrollable ``Recent Errors`` panel.

All three read their content from a :class:`~valistream.terminal.display.LiveDisplay`,
which holds the mutable session state. Errors are *appended* to the ``RichLog``
as they arrive so its own scrollback and scroll position are preserved; the
scanner and table are rebuilt from state on each refresh cycle.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Awaitable, Callable

from rich.text import Text
from textual.app import App, ComposeResult
from textual.css.query import NoMatches
from textual.widgets import DataTable, RichLog, Static

if TYPE_CHECKING:
    from valistream.terminal.display import LiveDisplay


class ScannerWidget(Static):
    """Single-line animated scanner bar driven by the display's ScannerBar."""

    def __init__(self, display: LiveDisplay) -> None:
        super().__init__()
        self._live_display = display

    def on_mount(self) -> None:
        self.set_interval(1 / 20, self._tick)
        self._tick()

    def _tick(self) -> None:
        self.update(self._live_display._scanner.render())


class StatusTable(DataTable[Text | str]):
    """Rendition status table, rebuilt from display state on each refresh."""

    # The errors log is the scroll target; the table should not grab focus.
    can_focus = False

    def __init__(self, display: LiveDisplay) -> None:
        super().__init__(cursor_type="none", zebra_stripes=False)
        self._live_display = display

    def on_mount(self) -> None:
        self.add_columns("Rendition", "Refs", "Last Seq", "Findings", "Last Fetch")
        self.set_interval(1 / 4, self._refresh_rows)
        self._refresh_rows()

    def _refresh_rows(self) -> None:
        self.clear()
        for status in self._live_display._statuses.values():
            seq = str(status.last_sequence) if status.last_sequence is not None else "-"
            fetch = status.last_fetch.strftime("%H:%M:%S") if status.last_fetch else "-"
            findings_style = "red" if status.finding_count > 0 else "green"
            self.add_row(
                Text(status.label, style="cyan"),
                str(status.refresh_count),
                seq,
                Text(str(status.finding_count), style=findings_style),
                fetch,
            )


class ValistreamApp(App[None]):
    """Full-screen live monitoring dashboard."""

    CSS = """
    Screen {
        layout: vertical;
    }
    ScannerWidget {
        height: 1;
        content-align: center middle;
    }
    StatusTable {
        height: auto;
        max-height: 40%;
    }
    #errors {
        height: 1fr;
        border: round #6b7c93;
        padding: 0 1;
    }
    """

    BINDINGS = [
        ("q", "quit", "Quit"),
        ("ctrl+c", "quit", "Quit"),
    ]

    def __init__(
        self,
        display: LiveDisplay,
        *,
        work: Callable[[], Awaitable[None]] | None = None,
    ) -> None:
        super().__init__()
        self._live_display = display
        self._work = work

    def compose(self) -> ComposeResult:
        yield ScannerWidget(self._live_display)
        yield StatusTable(self._live_display)
        log = RichLog(id="errors", wrap=True, markup=False, max_lines=1000, auto_scroll=True)
        log.border_title = "Recent Errors"
        yield log

    def on_mount(self) -> None:
        self._live_display._attach(self)
        self.query_one("#errors", RichLog).focus()
        if self._work is not None:
            self.run_worker(self._run_work(), name="monitor", exclusive=False)

    async def _run_work(self) -> None:
        assert self._work is not None
        try:
            await self._work()
        finally:
            # Session is finished (or was cancelled) — tear the UI down.
            self.exit()

    def write_error(self, markup: str) -> None:
        """Append one pre-formatted error line to the scrollable errors log."""
        try:
            log = self.query_one("#errors", RichLog)
        except NoMatches:
            return
        log.write(Text.from_markup(markup))
