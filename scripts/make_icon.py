#!/usr/bin/env python3
"""Regenerate the Free Track app icon (1024x1024 PNG) and its iOS 18 variants.

Concept -- "the ring that lets go"
    One continuous stroke weight, two strokes. A progress ring (the app's CalorieRing)
    is opened at about 1:30, and a check mark sits inside it whose long leg climbs up
    and out through that opening. Ring = tracking, check = logged / done, the leg
    leaving the ring = progress breaking free of the loop. It is a single mark with no
    text, reads at 60 px as "ring with a tick", and at 1024 px as a deliberate
    geometric signature. Tile: accent green with a very soft radial lift top-left.

Geometry lives in ONE place (`Mark`), expressed in a 1024 design space and scaled to
any size. `FreeTrack/DesignSystem/Components/BrandLogo.swift` draws the same numbers
as a SwiftUI `Shape`; keep the two in sync when tuning.

Usage:
    python3 scripts/make_icon.py                 # regenerate the whole asset catalog:
                                                 #   AppIcon-1024.png (light, RGB, no alpha)
                                                 #   AppIcon-1024-dark.png (iOS 18 dark, RGBA)
                                                 #   AppIcon-1024-tinted.png (iOS 18 tinted, grey+alpha)
                                                 #   Contents.json (appearance entries)
    python3 scripts/make_icon.py out.png         # just the light icon, somewhere else
    python3 scripts/make_icon.py out.png --dark --tinted
                                                 # also out-dark.png / out-tinted.png
    python3 scripts/make_icon.py --preview p.png # legibility sheet at 1024/180/120/60 px

Requires Pillow (`pip install --user pillow`); numpy is used when present for the
gradient / preview compositing, with a plain Pillow path otherwise.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

SIZE = 1024
SUPERSAMPLE = 4

# --- palette (mirrors Theme.swift) ---------------------------------------------------
ACCENT_LIGHT = (0x2F, 0x8F, 0x5B)      # Color.mAccent light
ACCENT_DARK = (0x4C, 0xC3, 0x8A)       # Color.mAccent dark
TILE_LIFT = (0x3A, 0xA3, 0x6C)         # soft highlight towards top-left of the tile
TILE_SHADE = (0x27, 0x7E, 0x4F)        # soft shade towards bottom-right of the tile
WHITE = (0xFF, 0xFF, 0xFF)
BG_LIGHT = (0xFA, 0xF9, 0xF6)          # Color.mBackground light (preview only)
BG_DARK = (0x0F, 0x0F, 0x10)           # Color.mBackground dark (preview only)

DEFAULT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "FreeTrack", "Resources", "Assets.xcassets", "AppIcon.appiconset",
)
DEFAULT_OUT = os.path.join(DEFAULT_DIR, "AppIcon-1024.png")


class Mark:
    """The mark in a 1024 x 1024 design space. All numbers are multiples of the ring
    radius so the proportions survive any retune of R. Angles are degrees measured
    clockwise from 12 o'clock (screen coordinates, y down)."""

    # Optical centre: the check's exit leg adds mass top-right, so the ring sits a
    # touch down and left of the geometric centre to balance the silhouette.
    CX = 512.0
    CY = 512.0 + 22.0
    R = 308.0                      # ring centre-line radius
    STROKE = 0.27 * R              # one stroke weight everywhere (~83 px)

    GAP_CENTER = 43.5              # opening at ~1:30
    GAP_HALF = 28.0                # half the angular opening (centre-line to centre-line)

    # Check mark: short leg down-right into the vertex, long leg up and out of the gap.
    P0 = (-0.62 * R, 0.02 * R)
    V = (-0.20 * R, 0.44 * R)
    P2 = (0.98 * R, -1.14 * R)

    @classmethod
    def arc_angles(cls):
        """(start, end) in degrees clockwise from 12 o'clock, start < end, drawn clockwise."""
        return cls.GAP_CENTER + cls.GAP_HALF, cls.GAP_CENTER - cls.GAP_HALF + 360.0

    @classmethod
    def point_on_ring(cls, deg: float, scale: float = 1.0):
        a = math.radians(deg)
        return ((cls.CX + cls.R * math.sin(a)) * scale, (cls.CY - cls.R * math.cos(a)) * scale)

    @classmethod
    def check_points(cls, scale: float = 1.0):
        return [((cls.CX + x) * scale, (cls.CY + y) * scale) for (x, y) in (cls.P0, cls.V, cls.P2)]


def _require_pillow():
    try:
        from PIL import Image, ImageDraw  # noqa: F401
    except ImportError:
        sys.exit("make_icon.py needs Pillow: pip install --user pillow")


def mark_mask(size: int, ss: int = SUPERSAMPLE):
    """Anti-aliased 8-bit coverage mask of the mark at `size` px (white = mark)."""
    from PIL import Image, ImageDraw

    big = size * ss
    scale = big / SIZE
    img = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(img)

    w = Mark.STROKE * scale
    cx, cy, r = Mark.CX * scale, Mark.CY * scale, Mark.R * scale

    def dot(p, radius):
        draw.ellipse([p[0] - radius, p[1] - radius, p[0] + radius, p[1] + radius], fill=255)

    # Ring: Pillow strokes inward from the bounding box, so the box is the OUTER edge,
    # and its angles run clockwise from 3 o'clock (12 o'clock = 270).
    ro = r + w / 2
    start, end = Mark.arc_angles()
    draw.arc([cx - ro, cy - ro, cx + ro, cy + ro],
             start=270 + start, end=270 + end, fill=255, width=int(round(w)))
    for deg in (start, end):
        dot(Mark.point_on_ring(deg, scale), w / 2)       # round caps

    # Check: two legs, round joint and caps.
    pts = Mark.check_points(scale)
    draw.line(pts, fill=255, width=int(round(w)), joint="curve")
    for p in pts:
        dot(p, w / 2)

    return img.resize((size, size), Image.LANCZOS)


def tile_image(size: int):
    """Accent tile with a soft radial lift (top-left) and shade (bottom-right)."""
    from PIL import Image

    try:
        import numpy as np
        ys, xs = np.mgrid[0:size, 0:size].astype(np.float32) / float(size)
        d = np.sqrt((xs - 0.30) ** 2 + (ys - 0.25) ** 2) / 1.05
        t = np.clip(d, 0.0, 1.0)[..., None]
        # ease so the middle of the tile stays essentially flat accent green
        t = t * t * (3 - 2 * t)
        lift, shade = np.array(TILE_LIFT, np.float32), np.array(TILE_SHADE, np.float32)
        base = np.array(ACCENT_LIGHT, np.float32)
        rgb = np.where(t < 0.5,
                       lift + (base - lift) * (t / 0.5),
                       base + (shade - base) * ((t - 0.5) / 0.5))
        return Image.fromarray(np.clip(rgb + 0.5, 0, 255).astype(np.uint8), "RGB")
    except ImportError:
        g = Image.radial_gradient("L").resize((int(size * 2.1), int(size * 2.1)), Image.BILINEAR)
        g = g.crop((int(size * 2.1 * 0.5) - int(size * 0.30), int(size * 2.1 * 0.5) - int(size * 0.25),
                    int(size * 2.1 * 0.5) - int(size * 0.30) + size,
                    int(size * 2.1 * 0.5) - int(size * 0.25) + size))
        return Image.composite(Image.new("RGB", (size, size), TILE_SHADE),
                               Image.new("RGB", (size, size), TILE_LIFT), g)


def render_light(size: int = SIZE):
    """Opaque RGB icon: white mark on the accent tile (App Store primary)."""
    from PIL import Image
    tile = tile_image(size)
    white = Image.new("RGB", (size, size), WHITE)
    return Image.composite(white, tile, mark_mask(size))


def render_dark(size: int = SIZE):
    """iOS 18 dark appearance: accent-green mark on a transparent background; the
    system supplies the dark gradient tile behind it."""
    from PIL import Image
    img = Image.new("RGBA", (size, size), ACCENT_DARK + (0,))
    img.putalpha(mark_mask(size))
    return img


def render_tinted(size: int = SIZE):
    """iOS 18 tinted appearance: greyscale + alpha (saved as RGBA for actool's sake).
    White = full tint strength; the system supplies the dark tile behind it."""
    from PIL import Image
    img = Image.new("RGBA", (size, size), WHITE + (0,))
    img.putalpha(mark_mask(size))
    return img


# --- asset catalog -------------------------------------------------------------------

CONTENTS = {
    "images": [
        {"filename": "AppIcon-1024.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}],
         "filename": "AppIcon-1024-dark.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "tinted"}],
         "filename": "AppIcon-1024-tinted.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def write_contents_json(directory: str) -> str:
    path = os.path.join(directory, "Contents.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(CONTENTS, fh, indent=2)
        fh.write("\n")
    return path


# --- preview sheet -------------------------------------------------------------------

def _rounded_mask(size: int):
    """iOS home-screen corner mask (continuous-ish corners, radius ~22.4 %)."""
    from PIL import Image, ImageDraw
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size * ss - 1, size * ss - 1],
                                        radius=size * ss * 0.2237, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def _system_dark_tile(size: int):
    """Approximation of the dark gradient iOS puts behind transparent dark icons."""
    from PIL import Image
    top, bottom = (0x3A, 0x3A, 0x3E), (0x1C, 0x1C, 0x1F)
    g = Image.linear_gradient("L").rotate(0).resize((size, size))
    return Image.composite(Image.new("RGB", (size, size), bottom),
                           Image.new("RGB", (size, size), top), g)


def render_preview(path: str) -> None:
    from PIL import Image, ImageDraw

    sizes = [1024, 180, 120, 60]
    pad = 48
    col_w = 1024 + pad + 180 + pad + 120 + pad + 60 + pad * 2
    row_h = 1024 + pad * 2
    sheet = Image.new("RGB", (col_w, row_h * 2 + 240), BG_LIGHT)
    draw = ImageDraw.Draw(sheet)

    light = render_light()
    dark = render_dark()
    tinted = render_tinted()

    def place(img_rgba, size, x, y):
        icon = img_rgba.resize((size, size), Image.LANCZOS)
        sheet.paste(icon, (x, y), _rounded_mask(size))

    # Row 1: light icon on the app's light background.
    x = pad
    for s in sizes:
        place(light, s, x, pad + (1024 - s) // 2 if s != 1024 else pad)
        x += s + pad

    # Row 2: on the dark background, the light icon and the dark variant composited the
    # way iOS does it (over its own dark gradient), plus the tinted one in grey.
    draw.rectangle([0, row_h, col_w, row_h * 2 + 240], fill=BG_DARK)
    y0 = row_h + pad
    x = pad
    for s in sizes:
        place(light, s, x, y0 + (1024 - s) // 2 if s != 1024 else y0)
        x += s + pad

    # Third strip: dark + tinted variants at 180 / 120 / 60 and the mark alone.
    y1 = row_h * 2 + 20
    x = pad
    for s in (180, 120, 60):
        base = _system_dark_tile(s)
        base.paste(dark.resize((s, s), Image.LANCZOS), (0, 0), dark.resize((s, s), Image.LANCZOS))
        sheet.paste(base, (x, y1 + (180 - s) // 2), _rounded_mask(s))
        x += s + pad
    x += pad
    for s in (180, 120, 60):
        base = _system_dark_tile(s)
        grey = Image.new("RGB", (s, s), (0x9A, 0x9A, 0xA0))   # a typical system tint
        t = tinted.resize((s, s), Image.LANCZOS)
        base.paste(grey, (0, 0), t.getchannel("A"))
        sheet.paste(base, (x, y1 + (180 - s) // 2), _rounded_mask(s))
        x += s + pad
    x += pad
    for s, colour in ((180, ACCENT_DARK), (96, ACCENT_DARK)):
        m = mark_mask(s)
        sheet.paste(Image.new("RGB", (s, s), colour), (x, y1 + (180 - s) // 2), m)
        x += s + pad

    sheet.save(path, "PNG", optimize=True)


# --- CLI -----------------------------------------------------------------------------

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("out", nargs="?", default=None,
                    help="output PNG (default: the asset catalog, all variants)")
    ap.add_argument("--dark", action="store_true", help="also write the iOS 18 dark variant")
    ap.add_argument("--tinted", action="store_true", help="also write the iOS 18 tinted variant")
    ap.add_argument("--all", action="store_true", help="light + dark + tinted")
    ap.add_argument("--preview", metavar="PNG", help="write a legibility preview sheet and exit")
    args = ap.parse_args(argv)

    _require_pillow()

    if args.preview:
        os.makedirs(os.path.dirname(os.path.abspath(args.preview)), exist_ok=True)
        render_preview(args.preview)
        print(f"wrote {args.preview}")
        return 0

    to_catalog = args.out is None
    out = os.path.abspath(args.out or DEFAULT_OUT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    stem, ext = os.path.splitext(out)
    want_dark = args.dark or args.all or to_catalog
    want_tinted = args.tinted or args.all or to_catalog

    render_light().save(out, "PNG", optimize=True)
    print(f"wrote {out}")
    if want_dark:
        p = f"{stem}-dark{ext}"
        render_dark().save(p, "PNG", optimize=True)
        print(f"wrote {p}")
    if want_tinted:
        p = f"{stem}-tinted{ext}"
        render_tinted().save(p, "PNG", optimize=True)
        print(f"wrote {p}")
    if to_catalog:
        print(f"wrote {write_contents_json(os.path.dirname(out))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
