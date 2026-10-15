"""Make the app's own copies of the brand kit's marks (build_mara_neutre.py).

  app/assets/brand/mara_horizontal.webp       the white set's horizontal logo (1200 x 400)
  app/assets/brand/mara_horizontal_dark.webp  the black set's (1200 x 400)
  app/assets/brand/mara_stacked.webp          the grey set's stacked logo (480 x 600)
  app/web/brand/mara-stacked.png              the same, 320 x 400 (the welcome e-mail's logo)
  app/web/brand/og.jpg                        the grey set's feature graphic (the link preview)
  app/web/index.html                          the splash's inline stacked logo (vector)
  Android mipmap-*/launch_image.png, iPhone LaunchImage*.png
                                              the stacked logo, as tall as the square, centred

The seal alone (mara_seal.webp, the launcher and web icons) carries no word
and is not touched here. File names keep « mara »: the code refers to them.

Needs what build_mara_neutre.py needs. Run: python3 build_app_brand.py
"""
import io, os, re
import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
APP = os.path.normpath(os.path.join(ROOT, "..", "..", "app"))
KIT = os.path.join(ROOT, "build_mara_neutre.py")

# The kit's drawing functions and colours, without running its build.
src = open(KIT).read()
k = {"__file__": KIT}
exec(src.split("THEMES = {")[0], k)
exec("THEMES = {" + src.split("THEMES = {")[1].split("BRAND =")[0], k)


def theme(name):
    t = k["THEMES"][name]
    k.update(t)
    k["KENTE"] = [t["GOLD"], t["TERRA"], t["GREEN"], t["INDIGO"], t["RED"]]


def png(w, h, body, bg=None, out_w=None, out_h=None):
    svg = k["svg"](w, h, body, bg)
    data = cairosvg.svg2png(bytestring=svg.encode(), output_width=out_w or w, output_height=out_h or h)
    return Image.open(io.BytesIO(data)).convert("RGBA")


def webp(img, path):
    img.save(os.path.join(APP, path), "WEBP", lossless=True, quality=100, method=6)


theme("blanc")
webp(png(1200, 400, k["horizontal"]()), "assets/brand/mara_horizontal.webp")
theme("noir")
webp(png(1200, 400, k["horizontal"]()), "assets/brand/mara_horizontal_dark.webp")

theme("gris")
stacked = png(800, 1000, k["stacked"](), out_w=1600, out_h=2000)
webp(stacked.resize((480, 600), Image.LANCZOS), "assets/brand/mara_stacked.webp")
stacked.resize((320, 400), Image.LANCZOS).save(os.path.join(APP, "web/brand/mara-stacked.png"), optimize=True)

# Launch images: the stacked logo as tall as the square, centred.
def launch(n, path):
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    s = stacked.resize((round(n * 0.8), n), Image.LANCZOS)
    img.alpha_composite(s, ((n - s.size[0]) // 2, 0))
    img.save(os.path.join(APP, path), optimize=True)

for d, n in (("mdpi", 120), ("hdpi", 180), ("xhdpi", 240), ("xxhdpi", 360), ("xxxhdpi", 480)):
    launch(n, f"android/app/src/main/res/mipmap-{d}/launch_image.png")
for suffix, n in (("", 120), ("@2x", 240), ("@3x", 360)):
    launch(n, f"ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png")

# The link preview: the feature graphic, as JPEG.
fg_body = (k["seal"](60, 60, 1.8)
           + f'<text x="470" y="242" font-family="Unbounded" font-weight="700" font-size="96" fill="{k["CREAM"]}">{k["WORD"]}</text>'
           f'<text x="474" y="318" font-family="Space Grotesk" font-size="34" fill="{k["GREY"]}">Les boutiques près de vous</text>'
           + k["kente"](0, 476, 1024, 24, 64))
png(1024, 500, fg_body, bg="auto").convert("RGB").save(os.path.join(APP, "web/brand/og.jpg"), quality=90, optimize=True)

# The splash's logo, inside index.html: the stacked logo as outlines, every
# number to one decimal (3 KB compressed, painted with the page).
vec = cairosvg.svg2svg(bytestring=k["svg"](800, 1000, k["stacked"](), None).encode()).decode()
vec = re.sub(r"<\?xml[^>]*>\s*", "", vec)
vec = re.sub(r"rgb\(([\d.]+)%, ([\d.]+)%, ([\d.]+)%\)",
             lambda m: "#" + "".join("%02x" % round(float(v) * 2.55) for v in m.groups()), vec)
vec = re.sub(r"-?\d+\.\d+", lambda m: ("%.1f" % float(m.group(0))).rstrip("0").rstrip("."), vec)
vec = re.sub(r">\s+<", "><", vec).strip()
vec = re.sub(r'<svg [^>]*>',
             '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
             'viewBox="0 0 800 1000" width="160" height="200" role="img" aria-label="Marakaj">', vec, count=1)
index = os.path.join(APP, "web/index.html")
html = open(index).read()
html2 = re.sub(r'    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink[^\n]*</svg>', lambda _: "    " + vec, html, count=1)
assert html2 != html or vec in html, "the splash's <svg> line was not found"
open(index, "w").write(html2)
print("done")
