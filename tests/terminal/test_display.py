"""Tests for the rich Live status panel."""

from __future__ import annotations

from datetime import datetime, timezone

from rich.console import Console

from valistream.parser.models import Rendition
from valistream.terminal.display import (
    LiveDisplay,
    RenditionStatus,
    create_live_display,
)


def _rendition(uri: str = "720p.m3u8", resolution: str = "1280x720", bandwidth: int = 1280000) -> Rendition:
    return Rendition(uri=uri, bandwidth=bandwidth, resolution=resolution)


class TestRenditionStatus:
    def test_initial_state(self) -> None:
        status = RenditionStatus("video-720p")
        assert status.label == "video-720p"
        assert status.refresh_count == 0
        assert status.last_sequence is None
        assert status.finding_count == 0
        assert status.last_fetch is None

    def test_update_increments_refresh(self) -> None:
        status = RenditionStatus("video-720p")
        status.update()
        assert status.refresh_count == 1

    def test_update_sets_sequence(self) -> None:
        status = RenditionStatus("video-720p")
        status.update(sequence=42)
        assert status.last_sequence == 42

    def test_update_accumulates_findings(self) -> None:
        status = RenditionStatus("video-720p")
        status.update(new_findings=3)
        status.update(new_findings=2)
        assert status.finding_count == 5

    def test_update_sets_last_fetch(self) -> None:
        status = RenditionStatus("video-720p")
        status.update()
        assert status.last_fetch is not None


class TestLiveDisplay:
    def test_add_rendition(self) -> None:
        console = Console(file=None, force_terminal=False)
        display = LiveDisplay(console)
        r = _rendition()
        status = display.add_rendition(r)
        assert status.label == r.alias

    def test_get_status(self) -> None:
        console = Console(file=None, force_terminal=False)
        display = LiveDisplay(console)
        r = _rendition()
        display.add_rendition(r)
        assert display.get_status(r.uri) is not None
        assert display.get_status("nonexistent") is None

    def test_build_table(self) -> None:
        console = Console(file=None, force_terminal=False)
        display = LiveDisplay(console)
        r = _rendition()
        display.add_rendition(r)
        table = display._build_table()
        assert table.title == "Rendition Status"
        assert len(table.columns) == 5

    def test_multiple_renditions(self) -> None:
        console = Console(file=None, force_terminal=False)
        display = LiveDisplay(console)
        display.add_rendition(_rendition("720p.m3u8", "1280x720"))
        display.add_rendition(_rendition("1080p.m3u8", "1920x1080"))
        assert len(display._statuses) == 2

    def test_add_renditions_unique_resolution(self) -> None:
        console = Console(file=None, force_terminal=False)
        display = LiveDisplay(console)
        renditions = [
            _rendition("720p.m3u8", "1280x720", 1280000),
            _rendition("1080p.m3u8", "1920x1080", 5000000),
        ]
        display.add_renditions(renditions)
        assert len(display._statuses) == 2
        assert display.get_status("720p.m3u8").label == "video-720p"
        assert display.get_status("1080p.m3u8").label == "video-1080p"

    def test_add_renditions_duplicate_resolution_appends_mbps(self) -> None:
        console = Console(file=None, force_terminal=False)
        display = LiveDisplay(console)
        renditions = [
            _rendition("1080p_low.m3u8", "1920x1080", 5_000_000),
            _rendition("1080p_high.m3u8", "1920x1080", 8_000_000),
        ]
        display.add_renditions(renditions)
        assert len(display._statuses) == 2
        assert display.get_status("1080p_low.m3u8").label == "video-1080p 5.0Mbps"
        assert display.get_status("1080p_high.m3u8").label == "video-1080p 8.0Mbps"


class TestCreateLiveDisplay:
    def test_returns_live_display(self) -> None:
        display = create_live_display()
        assert isinstance(display, LiveDisplay)

    def test_custom_console(self) -> None:
        console = Console(file=None, force_terminal=False)
        display = create_live_display(console)
        assert display._console is console
