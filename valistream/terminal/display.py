"""Live monitoring display state, rendered by a Textual app.

:class:`LiveDisplay` holds the mutable session state (per-rendition status and
the scanner animation) and exposes mutation methods that the monitor loop calls
as data arrives. The actual rendering — including the scrollable ``Recent
Errors`` panel — is done by :class:`~valistream.terminal.app.ValistreamApp`,
which reads this state on its refresh timers.
"""

from __future__ import annotations

from collections import Counter
from datetime import datetime
from typing import TYPE_CHECKING, Awaitable, Callable, Iterable

from rich.console import Console

from valistream.terminal.scanner import ScannerBar

if TYPE_CHECKING:
    from valistream.parser.models import Rendition
    from valistream.terminal.app import ValistreamApp


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


class LiveDisplay:
    """Holds live monitoring state; rendered by a Textual app."""

    def __init__(self, console: Console, *, color: bool = True) -> None:
        self._console = console
        self._statuses: dict[str, RenditionStatus] = {}  # keyed by rendition URI
        self._scanner = ScannerBar(color=color)
        self._app: ValistreamApp | None = None

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
        if self._app is not None:
            self._app.write_error(line)

    def refresh(self) -> None:
        """No-op: the Textual widgets refresh from state on their own timers."""

    def _attach(self, app: ValistreamApp) -> None:
        """Called by the Textual app once its widgets are mounted."""
        self._app = app

    async def run_until_complete(self, work: Callable[[], Awaitable[None]]) -> None:
        """Run the Textual dashboard, driving ``work`` as a background worker.

        The app exits when ``work`` completes (session ended, time limit hit, or
        cancelled), returning control to the caller.
        """
        from valistream.terminal.app import ValistreamApp

        app = ValistreamApp(self, work=work)
        try:
            await app.run_async()
        finally:
            self._app = None


def create_live_display(console: Console | None = None, *, color: bool = True) -> LiveDisplay:
    """Create a LiveDisplay for monitoring status."""
    if console is None:
        console = Console()
    return LiveDisplay(console, color=color)
