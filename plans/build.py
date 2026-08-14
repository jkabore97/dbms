#!/usr/bin/env python3
"""Assembles a Kaj plan into a single self-contained HTML file.

The Artifact CSP blocks font CDNs, so the faces are inlined as data URIs
rather than linked — a linked webfont fails silently and the page falls back
to whatever the viewer happens to have, which is exactly the "silent fallback"
the design brief warns about.

Usage:  build.py <source.html> <out.html>

The source carries its own token block and body; this only substitutes
@FONTS@ (the @font-face rules) and @SHARED@ (the shared stylesheet).
"""
import base64
import pathlib
import sys

FONT_DIR = pathlib.Path('/mnt/skills/examples/canvas-design/canvas-fonts')
HERE = pathlib.Path(__file__).parent

# family, style, weight, file
FACES = [
    ("IBM Plex Serif", "normal", 700, "IBMPlexSerif-Bold.ttf"),
    ("Work Sans", "normal", 400, "WorkSans-Regular.ttf"),
    ("Work Sans", "normal", 700, "WorkSans-Bold.ttf"),
    ("IBM Plex Mono", "normal", 400, "IBMPlexMono-Regular.ttf"),
]


def font_face_rules() -> str:
    out = []
    for family, style, weight, filename in FACES:
        raw = (FONT_DIR / filename).read_bytes()
        b64 = base64.b64encode(raw).decode("ascii")
        out.append(
            f"@font-face{{font-family:'{family}';font-style:{style};"
            f"font-weight:{weight};font-display:swap;"
            f"src:url(data:font/ttf;base64,{b64}) format('truetype');}}"
        )
    return "\n".join(out)


def main() -> None:
    src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    html = src.read_text()
    html = html.replace("/*@SHARED@*/", (HERE / "_shared.css").read_text())
    html = html.replace("/*@FONTS@*/", font_face_rules())
    dst.write_text(html)
    print(f"{dst}  {dst.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
