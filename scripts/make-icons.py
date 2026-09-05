#!/usr/bin/env python3
"""Draws Kaj's launcher and web icons from one description, so every size is
the same mark — the Flutter template logo they replace was byte-identical to
`flutter create` output on every surface the app has.

The mark is the app's own look (see kaj_theme.dart): a paper-white K on an
ink-black rounded square. Maskable variants keep the K inside the 80% safe
zone Android and browsers may crop to, and bleed the ink to the edge.

    pip install pillow && python3 scripts/make-icons.py

Regenerating is idempotent; commit the PNGs it writes.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "app" / "web"
RES = ROOT / "app" / "android" / "app" / "src" / "main" / "res"
FONT = Path("/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Black.ttf")

INK = (0x1F, 0x1F, 0x1F, 255)
PAPER = (0xFF, 0xFF, 0xFF, 255)


def mark(size: int, *, maskable: bool) -> Image.Image:
    """The K on its square at `size` px. Drawn at 4x and downsampled so the
    curves and the glyph edge stay clean at 48px."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    if maskable:
        draw.rectangle((0, 0, s, s), fill=INK)
        glyph_h = 0.42 * s  # inside the 80% safe zone with room to spare
    else:
        radius = int(s * 0.22)
        draw.rounded_rectangle((0, 0, s - 1, s - 1), radius=radius, fill=INK)
        glyph_h = 0.58 * s
    font = ImageFont.truetype(str(FONT), int(glyph_h))
    # Centre on the glyph's ink box, not its advance box, so the K sits
    # optically centred rather than nudged right by its side bearing.
    left, top, right, bottom = draw.textbbox((0, 0), "K", font=font)
    x = (s - (right - left)) / 2 - left
    y = (s - (bottom - top)) / 2 - top
    draw.text((x, y), "K", font=font, fill=PAPER)
    return img.resize((size, size), Image.LANCZOS)


def write(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)
    print(f"  {path.relative_to(ROOT)}  {img.size[0]}px")


def main() -> None:
    print("web/")
    write(mark(192, maskable=False), WEB / "icons" / "Icon-192.png")
    write(mark(512, maskable=False), WEB / "icons" / "Icon-512.png")
    write(mark(192, maskable=True), WEB / "icons" / "Icon-maskable-192.png")
    write(mark(512, maskable=True), WEB / "icons" / "Icon-maskable-512.png")
    write(mark(64, maskable=False), WEB / "favicon.png")

    print("android/")
    for folder, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                       ("xxhdpi", 144), ("xxxhdpi", 192)):
        write(mark(px, maskable=False), RES / f"mipmap-{folder}" / "ic_launcher.png")


if __name__ == "__main__":
    main()
