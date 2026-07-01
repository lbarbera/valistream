"""rich-based live status panel for terminal output."""

from __future__ import annotations

from collections import Counter
from datetime import datetime
from typing import TYPE_CHECKING, Iterable

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

    __slots__ = ("label", "refresh_count", "last_sequence", "finding_count", "last_fetch")

    def __init__(self, label: str) -> None:
        self.label = label
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
        self.last_fetch = datetime.now()


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

    _MAX_ERROR_LINES = 9

    def __init__(self, console: Console, *, color: bool = True) -> None:
        self._console = console
        self._statuses: dict[str, RenditionStatus] = {}  # keyed by rendition URI
        self._live: Live | None = None
        self._scanner = ScannerBar(color=color)
        self._error_lines: list[str] = []

    def add_rendition(self, rendition: Rendition, *, label: str | None = None) -> RenditionStatus:
        display_label = label if label is not None else rendition.alias
        status = RenditionStatus(display_label)
        self._statuses[rendition.uri] = status
        return status

    def add_renditions(self, renditions: Iterable[Rendition]) -> dict[str, RenditionStatus]:
        """Add multiple renditions, appending bandwidth in Mbps to labels that share a resolution."""
        rlist = list(renditions)
        alias_counts = Counter(r.alias for r in rlist)
        result: dict[str, RenditionStatus] = {}
        for r in rlist:
            if alias_counts[r.alias] > 1:
                mbps = r.bandwidth / 1_000_000
                label = f"{r.alias} {mbps:.1f}Mbps"
            else:
                label = r.alias
            result[r.uri] = self.add_rendition(r, label=label)
        return result

    def get_status(self, uri: str) -> RenditionStatus | None:
        return self._statuses.get(uri)

    def add_error(self, rendition_uri: str, message: str) -> None:
        ts = datetime.now().strftime("%H:%M:%S")
        status = self._statuses.get(rendition_uri)
        label = status.label if status is not None else rendition_uri
        line = f"[dim]{ts}[/dim] [cyan]{label}[/cyan] {message}"
        self._error_lines.append(line)
        if len(self._error_lines) > self._MAX_ERROR_LINES:
            self._error_lines.pop(0)

    def _build_table(self) -> Table:
        table = Table(title="Rendition Status", expand=True)
        table.add_column("Rendition", style="cyan", no_wrap=True)
        table.add_column("Refs", justify="right")
        table.add_column("Last Seq", justify="right")
        table.add_column("Findings", justify="right")
        table.add_column("Last Fetch", no_wrap=True)

        for status in self._statuses.values():
            seq = str(status.last_sequence) if status.last_sequence is not None else "-"
            fetch = status.last_fetch.strftime("%H:%M:%S") if status.last_fetch else "-"
            findings_style = "red" if status.finding_count > 0 else "green"
            table.add_row(
                status.label,
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
