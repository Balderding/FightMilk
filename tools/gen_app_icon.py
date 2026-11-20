"""Draws the FightMilk launcher icon: a green circle with FIGHT MILK written over it, on the app's dark
background. Font: Roboto Black (Apache 2.0, from Flutter's own font cache).

    python tools/gen_app_icon.py preview          -> work/icon/preview.png (both layouts, big and small)
    python tools/gen_app_icon.py install one|two  -> writes the Android launcher icons for that layout

Needs Pillow, and Flutter (FLUTTER_ROOT set, or flutter on PATH) for the font.
"""
import os, pathlib, shutil, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _flutter_root():
    if os.environ.get("FLUTTER_ROOT"):
        return pathlib.Path(os.environ["FLUTTER_ROOT"])
    f = shutil.which("flutter")
    return pathlib.Path(f).resolve().parent.parent if f else pathlib.Path(".")


FONT = str(_flutter_root() / "bin/cache/artifacts/material_fonts/roboto-black.ttf")
RES = ROOT / "app/android/app/src/main/res"
BG = (15, 20, 24)        # C.bg
CIRCLE = (34, 160, 80)   # green (the user chose green; no teal)
CIRCLE_DK = (20, 105, 50)
WHITE = (245, 248, 250)
INK = (15, 20, 24)


def fit(draw, text, width, start):
    s = start
    while s > 4:
        f = ImageFont.truetype(FONT, s)
        l, t, r, b = draw.textbbox((0, 0), text, font=f)
        if r - l <= width:
            return f
        s -= 1
    return ImageFont.truetype(FONT, 4)


def text_center(draw, cx, cy, text, font, stroke):
    l, t, r, b = draw.textbbox((0, 0), text, font=font, stroke_width=stroke)
    draw.text((cx - (r - l) / 2 - l, cy - (b - t) / 2 - t), text, font=font, fill=WHITE, stroke_width=stroke, stroke_fill=INK)


def draw(layout, size, bg=True, safe=1.0):
    """safe < 1 shrinks the art for Android's adaptive-icon safe zone (foreground layer)."""
    k = 4  # draw big, then shrink: smooth edges
    S = size * k
    im = Image.new("RGBA", (S, S), BG + (255,) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    r = S * 0.40 * safe
    ring = max(2, int(S * 0.035 * safe))
    d.ellipse((c - r, c - r, c + r, c + r), fill=CIRCLE, outline=CIRCLE_DK, width=ring)
    stroke = max(1, int(S * 0.018 * safe))
    if layout == "one":
        f = fit(d, "FIGHTMILK", S * 0.94 * safe, int(S * 0.3))
        text_center(d, c, c, "FIGHTMILK", f, stroke)
    else:
        f = fit(d, "FIGHT", S * 0.84 * safe, int(S * 0.4))
        l, t, rr, b = d.textbbox((0, 0), "FIGHT", font=f)
        h = b - t
        text_center(d, c, c - h * 0.58, "FIGHT", f, stroke)
        text_center(d, c, c + h * 0.58, "MILK", f, stroke)
    return im.resize((size, size), Image.LANCZOS)


def circle_mask(im):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, im.size[0] - 1, im.size[1] - 1), fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def preview():
    out = ROOT / "work/icon"
    out.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (760, 330), (236, 240, 243, 255))
    d = ImageDraw.Draw(sheet)
    lab = ImageFont.truetype(FONT, 20)
    for i, lay in enumerate(("one", "two")):
        x = 20 + i * 380
        d.text((x, 6), "%s: %s" % ("A" if lay == "one" else "B", "one line" if lay == "one" else "two lines"), font=lab, fill=INK)
        sheet.paste(circle_mask(draw(lay, 192)), (x, 40), circle_mask(draw(lay, 192)))
        sheet.paste(draw(lay, 96), (x + 210, 40))           # square launcher
        sheet.paste(circle_mask(draw(lay, 48)), (x + 210, 160), circle_mask(draw(lay, 48)))  # real phone size
        d.text((x + 210, 215), "phone size", font=ImageFont.truetype(FONT, 14), fill=INK)
    sheet.save(out / "preview.png")
    print(out / "preview.png")


def install(layout):
    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, px in sizes.items():
        dd = RES / ("mipmap-" + dpi)
        dd.mkdir(exist_ok=True)
        draw(layout, px).save(dd / "ic_launcher.png")
        circle_mask(draw(layout, px)).save(dd / "ic_launcher_round.png")
        # adaptive foreground: 108 dp canvas, art inside the 66 dp safe circle
        # (0.62: the word's corners stay inside the 66 dp circle, so round launchers don't clip them)
        draw(layout, px * 108 // 48, bg=False, safe=0.62).save(dd / "ic_launcher_foreground.png")
    a = RES / "mipmap-anydpi-v26"
    a.mkdir(exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@color/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n</adaptive-icon>\n')
    (a / "ic_launcher.xml").write_text(xml)
    (a / "ic_launcher_round.xml").write_text(xml)
    (RES / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#0F1418</color>\n</resources>\n')
    print("installed layout", layout)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "preview":
        preview()
    elif len(a) == 2 and a[0] == "install" and a[1] in ("one", "two"):
        install(a[1])
    else:
        print(__doc__)
