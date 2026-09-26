#!/usr/bin/env python3
"""Regenerate the Morsel app icon (1024x1024 PNG, no alpha).

Design: solid accent background (#2F8F5B) with a centered white ring (stroke ~70 px)
that echoes the calorie ring. The ring has a small gap at 12 o'clock with a filled
dot sitting in it -- the "current position" marker on the ring. No text.

Usage:  python3 scripts/make_icon.py            # writes the asset-catalog PNG
        python3 scripts/make_icon.py out.png    # writes somewhere else

Uses Pillow when importable (`pip install --user pillow`); otherwise falls back to a
tiny pure-python rasterizer + PNG encoder (zlib/struct) so the icon can always be
rebuilt in a bare environment.
"""
from __future__ import annotations

import math
import os
import struct
import sys
import zlib

SIZE = 1024
BACKGROUND = (0x2F, 0x8F, 0x5B)   # Color.mAccent (light)
FOREGROUND = (0xFF, 0xFF, 0xFF)

CENTER = (SIZE / 2, SIZE / 2)
RING_RADIUS = 330.0                # centre-line radius of the ring
STROKE = 70.0                      # ring stroke width
GAP_DEGREES = 44.0                 # angular gap at 12 o'clock
DOT_RADIUS = 46.0                  # filled dot inside the gap, on the ring track

DEFAULT_OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Morsel", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png",
)


def _ring_endpoints(scale: float):
    """Return the two arc endpoints (in scaled pixels) that bound the 12 o'clock gap."""
    cx, cy = CENTER[0] * scale, CENTER[1] * scale
    r = RING_RADIUS * scale
    half = math.radians(GAP_DEGREES / 2)
    # Angles measured clockwise from 12 o'clock; image y grows downward.
    pts = []
    for a in (-half, half):
        pts.append((cx + r * math.sin(a), cy - r * math.cos(a)))
    return pts


def render_pillow(path: str) -> None:
    from PIL import Image, ImageDraw

    ss = 4  # supersample for smooth edges
    big = SIZE * ss
    img = Image.new("RGB", (big, big), BACKGROUND)
    draw = ImageDraw.Draw(img)

    cx, cy = CENTER[0] * ss, CENTER[1] * ss
    r, w = RING_RADIUS * ss, STROKE * ss
    # Pillow strokes an arc *inward* from its bounding box, so the box is the OUTER edge.
    ro = r + w / 2
    box = [cx - ro, cy - ro, cx + ro, cy + ro]

    # Pillow measures angles clockwise from 3 o'clock. 12 o'clock is 270 deg.
    start = 270 + GAP_DEGREES / 2
    end = 270 - GAP_DEGREES / 2 + 360
    draw.arc(box, start=start, end=end, fill=FOREGROUND, width=int(w))

    # Round caps at both arc ends.
    for (px, py) in _ring_endpoints(ss):
        draw.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=FOREGROUND)

    # The dot at 12 o'clock, on the ring track.
    d = DOT_RADIUS * ss
    draw.ellipse([cx - d, cy - r - d, cx + d, cy - r + d], fill=FOREGROUND)

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(path, "PNG", optimize=True)


def _coverage(dist: float, edge: float, soft: float = 0.9) -> float:
    """Anti-aliased coverage: 1 inside the shape edge, 0 outside, linear ramp across `soft` px."""
    t = (edge - dist) / soft + 0.5
    return 0.0 if t <= 0 else 1.0 if t >= 1 else t


def render_pure_python(path: str) -> None:
    cx, cy = CENTER
    half_gap = math.radians(GAP_DEGREES / 2)
    caps = _ring_endpoints(1.0)
    dot = (cx, cy - RING_RADIUS)
    inner, outer = RING_RADIUS - STROKE / 2, RING_RADIUS + STROKE / 2

    rows = []
    bg, fg = BACKGROUND, FOREGROUND
    for y in range(SIZE):
        row = bytearray()
        row.append(0)  # PNG filter type 0 for this scanline
        py = y + 0.5
        for x in range(SIZE):
            px = x + 0.5
            dx, dy = px - cx, py - cy
            dist = math.hypot(dx, dy)
            a = 0.0
            # Ring band, excluding the gap centred on 12 o'clock.
            if inner - 1 <= dist <= outer + 1:
                ang = math.atan2(dx, -dy)  # 0 at 12 o'clock, clockwise positive
                if abs(ang) >= half_gap:
                    a = min(_coverage(dist, outer), _coverage(inner, dist))
            # Round caps.
            for (kx, ky) in caps:
                a = max(a, _coverage(math.hypot(px - kx, py - ky), STROKE / 2))
            # Dot.
            a = max(a, _coverage(math.hypot(px - dot[0], py - dot[1]), DOT_RADIUS))
            if a <= 0:
                row += bytes(bg)
            else:
                row += bytes(int(round(b * (1 - a) + f * a)) for b, f in zip(bg, fg))
        rows.append(bytes(row))

    raw = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    try:
        import PIL  # noqa: F401
        render_pillow(out)
        how = "Pillow"
    except ImportError:
        render_pure_python(out)
        how = "pure-python fallback"
    print(f"wrote {out} ({how})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
