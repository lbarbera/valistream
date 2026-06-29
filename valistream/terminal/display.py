"""rich-based live status panel for terminal output."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import TYPE_CHECKING

from rich.console import Console, ConsoleOptions, RenderResult
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from valistream.terminal.scanner import ScannerBar

if TYPE_CHECKING:
    from valistream.parser.models import Rendition


class RenditionStatus:
    """Mutable status for one rendition in the live panel."""

    __slots__ = ("alias", "refresh_count", "last_sequence", "finding_count", "last_fetch")

    def __init__(self, alias: str) -> None:
        self.alias = alias
        self.refresh_count: int = 0
        self.last_sequence: int | None = None
        self.finding_count: int = 0
        self.last_fetch: datetime | None = None

    def update(
        self,
        *,
        sequence: int | None = None,
        new_findings: int = 0,
    ) -> None:
        self.refresh_count += 1
        if sequence is not None:
            self.last_sequence = sequence
        self.finding_count += new_findings
        self.last_fetch = datetime.now(timezone.utc)


class _DynamicPanel:
    """Dynamic renderable that rebuilds content on every Live refresh cycle."""

    def __init__(self, display: LiveDisplay) -> None:
        self._display = display

    def __rich_console__(self, console: Console, options: ConsoleOptions) -> RenderResult:
        d = self._display
        yield d._scanner.render()
        yield d._build_table()
        yield d._build_error_panel()


class LiveDisplay:
    """Live-updating status panel using rich.Live."""

    _MAX_ERROR_LINES = 10

    def __init__(self, console: Console, *, color: bool = True) -> None:
        self._console = console
        self._statuses: dict[str, RenditionStatus] = {}
        self._live: Live | None = None
        self._scanner = ScannerBar(color=color)
        self._error_lines: list[str] = []

    def add_rendition(self, rendition: Rendition) -> RenditionStatus:
        status = RenditionStatus(rendition.alias)
        self._statuses[rendition.alias] = status
        return status

    def get_status(self, alias: str) -> RenditionStatus | None:
        return self._statuses.get(alias)

    def add_error(self, rendition_alias: str, message: str) -> None:
        ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
        line = f"[dim]{ts}[/dim] [cyan]{rendition_alias}[/cyan] {message}"
        self._error_lines.append(line)
        if len(self._error_lines) > self._MAX_ERROR_LINES:
            self._error_lines.pop(0)

    def _build_table(self) -> Table:
        table = Table(title="Rendition Status", expand=True)
        table.add_column("Rendition", style="cyan", no_wrap=True)
        table.add_column("Refreshes", justify="right")
        table.add_column("Last Seq", justify="right")
        table.add_column("Findings", justify="right")
        table.add_column("Last Fetch", no_wrap=True)

        for status in self._statuses.values():
            seq = str(status.last_sequence) if status.last_sequence is not None else "-"
            fetch = status.last_fetch.strftime("%H:%M:%S") if status.last_fetch else "-"
            findings_style = "red" if status.finding_count > 0 else "green"
            table.add_row(
                status.alias,
                str(status.refresh_count),
                seq,
                f"[{findings_style}]{status.finding_count}[/{findings_style}]",
                fetch,
            )
        return table

    def _build_error_panel(self) -> Panel:
        lines = self._error_lines[-self._MAX_ERROR_LINES:]
        # Pad to always occupy MAX_ERROR_LINES rows so the panel height stays stable
        padded = lines + [""] * (self._MAX_ERROR_LINES - len(lines))
        content = Text.from_markup("\n".join(padded))
        return Panel(content, title="[red]Recent Errors[/red]", expand=True)

    def refresh(self) -> None:
        """No-op: the Live auto-refresh reads fresh data on every cycle."""

    def start(self) -> None:
        self._live = Live(
            _DynamicPanel(self),
            console=self._console,
            refresh_per_second=12,
            auto_refresh=True,
        )
        self._live.start()

    def stop(self) -> None:
        if self._live is not None:
            self._live.stop()
            self._live = None

    def __enter__(self) -> LiveDisplay:
        self.start()
        return self

    def __exit__(self, *args: object) -> None:
        self.stop()


def create_live_display(console: Console | None = None, *, color: bool = True) -> LiveDisplay:
    """Create a LiveDisplay for monitoring status."""
    if console is None:
        console = Console()
    return LiveDisplay(console, color=color)
