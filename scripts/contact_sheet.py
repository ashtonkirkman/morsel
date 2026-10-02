#!/usr/bin/env python3
"""Tile every PNG in a directory into one contact sheet (needs Pillow; silently skips without it).
Usage: contact_sheet.py <dir> <out.png>
"""
import sys, pathlib
try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow not installed; skipping contact sheet")
    sys.exit(0)

src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
files = sorted(p for p in src.glob("*.png") if p.name != out.name)
if not files:
    sys.exit(0)
thumb_w = 360
imgs = []
for f in files:
    im = Image.open(f).convert("RGB")
    im.thumbnail((thumb_w, 10_000))
    imgs.append((f.stem, im))
cols = min(4, len(imgs))
rows = (len(imgs) + cols - 1) // cols
cell_h = max(im.height for _, im in imgs) + 40
sheet = Image.new("RGB", (cols * (thumb_w + 24) + 24, rows * (cell_h + 24) + 24), (250, 249, 246))
draw = ImageDraw.Draw(sheet)
for i, (name, im) in enumerate(imgs):
    x = 24 + (i % cols) * (thumb_w + 24)
    y = 24 + (i // cols) * (cell_h + 24)
    sheet.paste(im, (x + (thumb_w - im.width) // 2, y))
    draw.text((x, y + im.height + 12), name, fill=(60, 60, 60))
sheet.save(out)
print(f"wrote {out} ({len(imgs)} images)")
