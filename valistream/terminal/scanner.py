"""KITT-style pulsating scanner bar for terminal output."""

from __future__ import annotations

import time

from rich.text import Text

# Gradient: distance from beam center → (character, style)
_GRADIENT = [
    ("█", "bold bright_red"),
    ("▓", "bright_red"),
    ("▒", "red"),
    ("░", "dark_red"),
]
_BG_CHAR = "░"
_BG_STYLE = "grey23"

# ASCII fallback when color is disabled
_ASCII_BEAM = ["O", "o", ".", " "]
_ASCII_BG = " "

_SPEED = 20.0  # cells per second


class ScannerBar:
    """Bouncing scanner bar in the style of KITT's anamorphic equalizer.

    Position is derived from wall-clock time so the animation runs at a
    constant speed regardless of how often render() is called.
    """

    def __init__(self, width: int = 60, *, color: bool = True) -> None:
        self._width = width
        self._color = color
        self._start = time.monotonic()

    def _current_pos(self) -> int:
        span = max(self._width - 1, 1)
        period = 2.0 * span / _SPEED
        t = (time.monotonic() - self._start) % period
        half = period / 2.0
        if t < half:
            return int(round(t * _SPEED))
        return int(round((period - t) * _SPEED))

    def render(self) -> Text:
        pos = self._current_pos()
        bar = Text(no_wrap=True, overflow="crop")
        gradient = _GRADIENT if self._color else [
            (c, "") for c in _ASCII_BEAM
        ]
        bg_char = _BG_CHAR if self._color else _ASCII_BG
        bg_style = _BG_STYLE if self._color else ""

        for i in range(self._width):
            dist = abs(i - pos)
            if dist < len(gradient):
                ch, style = gradient[dist]
                bar.append(ch, style=style)
            else:
                bar.append(bg_char, style=bg_style)

        return bar
