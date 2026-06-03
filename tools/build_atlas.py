"""Build tex_korobka.png — the КОРСАР1 box atlas used by tools/texture_petard.py.

Layout (normalized, TOP-LEFT origin) MUST match RECTS in texture_petard.py:
  TOP/BOTTOM = lid art, FRONT/BACK = padded КОРСАР1 strips (text centred with a
  red margin so it never bleeds onto the box's rounded edges), LEFT/RIGHT = the
  striker strip (_raw/cherkalka.png) if present, else plain red.
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN   = os.path.join(ROOT, "_raw", "korobka_gen.png")
LID   = os.path.join(ROOT, "decal_petard.png")
STRIKE = os.path.join(ROOT, "_raw", "cherkalka.png")
OUT   = os.path.join(ROOT, "tex_korobka.png")

S = 2048
RED = (208, 42, 38)

# rects in pixels (must equal norm rects in texture_petard.py * 2048)
RECTS = {
    "TOP":    (41,   41, 1270, 881),
    "BOTTOM": (1352, 41,  655, 614),
    "FRONT":  (41, 1024, 1597, 410),
    "BACK":   (41, 1475, 1597, 410),
    "LEFT":   (41, 1925,  614, 102),
    "RIGHT":  (696,1925,  614, 102),
}


def build_top(lid, strike, w, h, red):
    """TOP tile: a clean striker rectangle along the top edge + КОРСАР1 art below.
    Baking the striker into the tile gives a perfectly straight edge on the model."""
    tile = Image.new("RGB", (w, h), red)
    art_top = 0
    if strike is not None:
        mx = int(w * 0.045)            # side margin
        top = int(h * 0.035)           # gap from the very edge (reads as box rim)
        bh = int(h * 0.205)            # striker height
        art_top = int(h * 0.30)
        tile.paste(strike.resize((w - 2 * mx, bh)), (mx, top))
    tile.paste(lid.resize((w, h - art_top)), (0, art_top))
    return tile


def build_front(text_img, strike_img, w, h, red):
    """Long-side panel: КОРСАР1 in the upper part, a brown striker band in the
    lower part (this is where the model has the recessed groove)."""
    panel = Image.new("RGB", (w, h), red)
    # КОРСАР1 text, upper area
    tw = int(w * 0.66)
    th = int(tw * text_img.height / text_img.width)
    if th > int(h * 0.40):
        th = int(h * 0.40)
        tw = int(th * text_img.width / text_img.height)
    panel.paste(text_img.resize((tw, th)), ((w - tw) // 2, int(h * 0.07)))
    # striker band, lower area (the groove)
    if strike_img is not None:
        bw, bh = int(w * 0.92), int(h * 0.34)
        panel.paste(strike_img.resize((bw, bh)), ((w - bw) // 2, h - bh - int(h * 0.07)))
    return panel


def main():
    gen = Image.open(GEN).convert("RGB")
    lid = Image.open(LID).convert("RGB")

    # КОРСАР1 text crop from the bottom strip (already on red, so seams vanish)
    text = gen.crop((400, 1545, 1740, 1795))
    red = text.getpixel((5, 5))            # match panel red to the crop's red

    atlas = Image.new("RGB", (S, S), (235, 235, 233))

    def put(name, img):
        x, y, w, h = RECTS[name]
        atlas.paste(img.resize((w, h)), (x, y))

    # striker removed — plain lid on top. (Set strike to the loaded image to bring
    # the striker rectangle back; see build_top.)
    strike = None
    print("striker: disabled -> plain lid")
    tw, th = RECTS["TOP"][2], RECTS["TOP"][3]
    put("TOP", build_top(lid, strike, tw, th, red))
    put("BOTTOM", lid)

    # КОРСАР1 long sides (plain, padded); short ends plain red.
    fw, fh = RECTS["FRONT"][2], RECTS["FRONT"][3]
    strip = build_front(text, None, fw, fh, red)
    put("FRONT", strip)
    put("BACK", strip)
    for nm in ("LEFT", "RIGHT"):
        x, y, w, h = RECTS[nm]
        atlas.paste(Image.new("RGB", (w, h), RED), (x, y))

    atlas.save(OUT)
    print("wrote", OUT)


main()
