"""Regenerate docs/brand/mara-neutre/: the Mara seal in black, white, brown and grey.

Needs: pip install cairosvg pillow, and the Unbounded, Cinzel and Space Grotesk
fonts installed on the machine (Google Fonts). Run: python3 build_mara_neutre.py
"""
import os, shutil, cairosvg
from PIL import Image
ROOT = os.path.dirname(os.path.abspath(__file__))

def glyph():
    return f'''<polygon points="28,170 28,30 100,102 100,140 64,104 64,170" fill="{TERRA}"/>
<polygon points="100,102 172,30 172,170 136,170 136,104 100,140" fill="{INDIGO}"/>
<polygon points="64,30 136,30 100,66" fill="{GOLD}"/>'''

def seal(x, y, s, thin=1.0):
    """Seal mark (always with MMXXVI) in a 200-unit box at (x, y), scaled by s."""
    return f'''<g transform="translate({x} {y}) scale({s})">
<circle cx="100" cy="100" r="94" fill="none" stroke="{RING}" stroke-width="{thin}"/>
<circle cx="100" cy="100" r="84" fill="none" stroke="{GOLD}" stroke-width="12" stroke-dasharray="4 18"/>
<circle cx="100" cy="100" r="66" fill="{PANEL}" stroke="{TERRA}" stroke-width="2"/>
<g transform="translate(100 96) scale(0.42) translate(-100 -100)">{glyph()}</g>
<text x="100" y="148" text-anchor="middle" font-family="Cinzel" font-size="10" fill="{YEAR}" letter-spacing="4">MMXXVI</text></g>'''

def kente(x, y, w, h, seg):
    n = int(w // seg) + 1
    return "".join(f'<rect x="{x+i*seg}" y="{y}" width="{seg}" height="{h}" fill="{KENTE[i%5]}"/>' for i in range(n))

def svg(w, h, body, bg="auto"):
    bg = BG if bg == "auto" else bg
    back = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{back}{body}</svg>'

def save(path, w, h, body, bg="auto"):
    bg = BG if bg == "auto" else bg
    full = os.path.join(OUT, path); os.makedirs(os.path.dirname(full), exist_ok=True)
    cairosvg.svg2png(bytestring=svg(w, h, body, bg).encode(), write_to=full, output_width=w, output_height=h)
    if bg:  # stores reject alpha on opaque icons
        Image.open(full).convert("RGB").save(full)

def vector(path, w, h, body, bg=None):
    """Portable SVG (text turned into outlines) + PDF."""
    full = os.path.join(OUT, path); os.makedirs(os.path.dirname(full), exist_ok=True)
    src = svg(w, h, body, bg).encode()
    cairosvg.svg2svg(bytestring=src, write_to=full + ".svg")
    cairosvg.svg2pdf(bytestring=src, write_to=full + ".pdf")

def centered(size, s, thin=2.0):
    off = (size - 200 * s) / 2
    return seal(off, off, s, thin)

# Lockups
def horizontal():  # 1200 x 400
    return seal(40, 40, 1.6, 1.5) + f'<text x="420" y="262" font-family="Unbounded" font-size="170" fill="{CREAM}">mara</text>'
def stacked():     # 800 x 1000
    return seal(100, 50, 3.0, 1.5) + f'<text x="400" y="900" text-anchor="middle" font-family="Unbounded" font-size="170" fill="{CREAM}">mara</text>'

def logos(prefix="logo"):
    for n in (256, 512, 1024, 2048):
        save(f"{prefix}/seal/mara-seal-{n}-transparent.png", n, n, centered(n, n * 0.0049, thin=1.5), bg=None)
    save(f"{prefix}/seal/mara-seal-1024-on-background.png", 1024, 1024, centered(1024, 4.4, thin=1.5))
    vector(f"{prefix}/seal/mara-seal", 200, 200, seal(0, 0, 1))
    for w, tag in ((1200, ""), (2400, "-large")):
        k = w / 1200
        save(f"{prefix}/horizontal/mara-horizontal{tag}-transparent.png", w, int(400 * k), f'<g transform="scale({k})">{horizontal()}</g>', bg=None)
        save(f"{prefix}/horizontal/mara-horizontal{tag}-on-background.png", w, int(400 * k), f'<g transform="scale({k})">{horizontal()}</g>')
    vector(f"{prefix}/horizontal/mara-horizontal", 1200, 400, horizontal())
    for w, tag in ((800, ""), (1600, "-large")):
        k = w / 800
        save(f"{prefix}/stacked/mara-stacked{tag}-transparent.png", w, int(1000 * k), f'<g transform="scale({k})">{stacked()}</g>', bg=None)
        save(f"{prefix}/stacked/mara-stacked{tag}-on-background.png", w, int(1000 * k), f'<g transform="scale({k})">{stacked()}</g>')
    vector(f"{prefix}/stacked/mara-stacked", 800, 1000, stacked())

def build():
    # App Store
    save("app-store/app-icon-1024.png", 1024, 1024, centered(1024, 4.6))
    # Google Play
    save("play-store/app-icon-512.png", 512, 512, centered(512, 2.3))
    save("play-store/adaptive-icon/foreground-432.png", 432, 432, centered(432, 1.4), bg=None)
    save("play-store/adaptive-icon/background-432.png", 432, 432, "")
    save("play-store/feature-graphic-1024x500.png", 1024, 500,
         seal(60, 60, 1.8) +
         f'<text x="470" y="250" font-family="Unbounded" font-size="124" fill="{CREAM}">mara</text>'
         f'<text x="474" y="318" font-family="Space Grotesk" font-size="34" fill="{GREY}">Les boutiques près de vous</text>'
         + kente(0, 476, 1024, 24, 64))
    # YouTube
    save("youtube/profile-picture-800.png", 800, 800, centered(800, 3.7))
    save("youtube/watermark-150.png", 150, 150, centered(150, 0.74, thin=3), bg=None)
    save("youtube/banner-2560x1440.png", 2560, 1440,
         f'<circle cx="790" cy="720" r="620" fill="none" stroke="{GOLD}" stroke-width="40" stroke-dasharray="10 60" opacity="0.10"/>'
         + kente(0, 0, 2560, 28, 128) + kente(0, 1412, 2560, 28, 128) +
         seal(600, 530, 1.9, thin=1.5) +
         f'<text x="1050" y="765" font-family="Unbounded" font-size="190" fill="{CREAM}">mara</text>'
         f'<text x="1058" y="858" font-family="Space Grotesk" font-size="52" fill="{GREY}">Les boutiques près de vous</text>')
    save("youtube/thumbnail-template-1280x720.png", 1280, 720,
         seal(1060, 40, 0.9, thin=2) +
         f'<text x="80" y="330" font-family="Unbounded" font-size="78" fill="{CREAM}">[TITRE DE</text>'
         f'<text x="80" y="430" font-family="Unbounded" font-size="78" fill="{GOLD}">LA VIDÉO]</text>'
         f'<text x="84" y="520" font-family="Space Grotesk" font-size="32" fill="{GREY}">mara · les boutiques près de vous</text>'
         + kente(0, 690, 1280, 30, 80))
    # Store screenshot templates
    def shot(path, w, h):
        m = w * 0.08; boxy = h * 0.22
        save(path, w, h,
             kente(0, 0, w, h * 0.012, w / 10) + seal(w / 2 - w * 0.06, h * 0.025, w * 0.0006, thin=2) +
             f'<text x="{w/2}" y="{h*0.135}" text-anchor="middle" font-family="Unbounded" font-size="{w*0.065}" fill="{CREAM}">[TITRE DE L\'ÉCRAN]</text>'
             f'<text x="{w/2}" y="{h*0.17}" text-anchor="middle" font-family="Space Grotesk" font-size="{w*0.04}" fill="{GREY}">[Une phrase sur ce que l\'écran permet]</text>'
             f'<rect x="{m}" y="{boxy}" width="{w-2*m}" height="{h-boxy-m}" rx="{w*0.06}" fill="{PANEL}" stroke="{TERRA}" stroke-width="{w*0.004}" stroke-dasharray="{w*0.02} {w*0.015}"/>'
             f'<text x="{w/2}" y="{boxy+(h-boxy-m)/2}" text-anchor="middle" font-family="Space Grotesk" font-size="{w*0.04}" fill="{GREY}">[Capture d\'écran de l\'app ici]</text>')
    shot("app-store/screenshot-template-1320x2868.png", 1320, 2868)
    shot("play-store/screenshot-template-1080x1920.png", 1080, 1920)
    # Web app (Flutter web icon names)
    save("web/icons/Icon-512.png", 512, 512, centered(512, 2.3))
    save("web/icons/Icon-192.png", 192, 192, centered(192, 0.86, thin=3))
    save("web/icons/Icon-maskable-512.png", 512, 512, centered(512, 2.1))
    save("web/icons/Icon-maskable-192.png", 192, 192, centered(192, 0.8, thin=3))
    for n in (16, 32, 48):
        save(f"web/_fav{n}.png", n, n, centered(n, n * 0.005, thin=4), bg=None)
    Image.open(f"{OUT}/web/_fav48.png").save(f"{OUT}/web/favicon.ico", sizes=[(16,16),(32,32),(48,48)])
    os.rename(f"{OUT}/web/_fav32.png", f"{OUT}/web/favicon.png")
    for n in (16, 48): os.remove(f"{OUT}/web/_fav{n}.png")
    logos()
    print("done", OUT)

THEMES = {
 "noir":  dict(BG="#0E0D0C", PANEL="#1D1B19", GOLD="#C49A6C", TERRA="#8B5A3C", INDIGO="#A3A09B", GREEN="#6E6B66", RED="#4A3122", CREAM="#F4F2EE", GREY="#8E8B86", RING="#F4F2EE", YEAR="#C49A6C"),
 "blanc": dict(BG="#FFFFFF", PANEL="#F3F0EB", GOLD="#9A6B44", TERRA="#5E3A22", INDIGO="#7C7975", GREEN="#B8B5B0", RED="#3A2A20", CREAM="#141210", GREY="#6E6B66", RING="#141210", YEAR="#5E3A22"),
 "brun":  dict(BG="#4A3122", PANEL="#1D1714", GOLD="#D8B98F", TERRA="#B07C4F", INDIGO="#C9C6C0", GREEN="#8E8B86", RED="#2A1D16", CREAM="#F6F1EA", GREY="#DCCDBE", RING="#F6F1EA", YEAR="#D8B98F"),
 "gris":  dict(BG="#3B3A38", PANEL="#1C1B1A", GOLD="#CDA77C", TERRA="#9C6B45", INDIGO="#D6D3CE", GREEN="#8E8B86", RED="#5E3A22", CREAM="#F4F2EE", GREY="#C4C1BC", RING="#F4F2EE", YEAR="#CDA77C"),
}
BRAND = f"{ROOT}/mara-neutre"
for sub in ("noir", "blanc", "brun", "gris", "monochrome"):
    shutil.rmtree(f"{BRAND}/{sub}", ignore_errors=True)
for name, t in THEMES.items():
    globals().update(t)
    KENTE = [t["GOLD"], t["TERRA"], t["GREEN"], t["INDIGO"], t["RED"]]
    OUT = f"{BRAND}/{name}"
    build()

# One-color logos (stamps, engraving, embroidery, photos)
for name, col, bg in (("blanc", "#FFFFFF", "#0E0D0C"), ("noir", "#0E0D0C", "#FFFFFF"), ("brun", "#8B5A3C", "#F4F2EE"), ("gris", "#7C7975", "#FFFFFF")):
    globals().update(BG=bg, PANEL="none", GOLD=col, TERRA=col, INDIGO=col, RING=col, YEAR=col, CREAM=col)
    OUT = f"{BRAND}/monochrome/{name}"
    logos(prefix=".")
print("mono done")
