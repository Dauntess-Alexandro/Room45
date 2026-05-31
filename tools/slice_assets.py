#!/usr/bin/env python3
"""
Slice the Nano-Banana texture/decal sheets into individual, correctly-named
game textures for the Godot project.

INPUT  (put your 4 generated images here, any of .png/.jpg/.jpeg/.webp):
    _raw/monitor.*    - the Windows-2000 desktop screenshot
    _raw/surfaces.*   - 5-cell sheet: wallpaper | wood floor
                                       ceiling | countertop | wardrobe
    _raw/fabrics.*    - 6-cell sheet: rug | brown curtain | lace tulle
                                       sofa-beige | sofa-navy | white board
    _raw/decals.*     - 4-cell MAGENTA sheet: world map | clock
                                              photo frames | door

OUTPUT (written to project root res://):
    Surfaces -> tex_*.jpg   (square, 512 px)
    Monitor  -> tex_monitor.jpg
    Decals   -> decal_*.png (magenta keyed to transparent, auto-cropped)

Run from the project root:  python tools/slice_assets.py
"""

from pathlib import Path
from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "_raw"

# Trim this fraction off each cell edge to dodge the thin divider lines
# that the image model sometimes draws between tiles.
INSET = 0.018

# Magenta chroma-key thresholds (the background is a hot magenta ~#E000FF).
KEY_R_MIN = 140   # red must be high
KEY_B_MIN = 140   # blue must be high
KEY_G_MAX = 110   # green must be low

# ---- Sheet layouts, as fractional (x0, y0, x1, y1) rectangles --------------
# mode: "tile"   -> centered-square crop, resize to 512, save .jpg
#       "screen" -> resize to 1024 square, save .jpg
#       "decal"  -> key magenta -> alpha, auto-crop, save .png
THIRD = 1.0 / 3.0
JOBS = [
    # --- surfaces sheet (top: 2 cells, bottom: 3 cells) ---
    ("surfaces", "tile",  "tex_wallpaper.jpg",  (0.0,   0.0, 0.5,    0.5)),
    ("surfaces", "tile",  "tex_floor.jpg",      (0.5,   0.0, 1.0,    0.5)),
    ("surfaces", "tile",  "tex_ceiling.jpg",    (0.0,   0.5, THIRD,  1.0)),
    ("surfaces", "tile",  "tex_countertop.jpg", (THIRD, 0.5, 2*THIRD,1.0)),
    ("surfaces", "tile",  "tex_wardrobe.jpg",   (2*THIRD,0.5,1.0,    1.0)),

    # --- fabrics sheet (2 rows x 3 cols) ---
    ("fabrics",  "tile",  "tex_rug.jpg",        (0.0,   0.0, THIRD,  0.5)),
    ("fabrics",  "tile",  "tex_curtain.jpg",    (THIRD, 0.0, 2*THIRD,0.5)),
    ("fabrics",  "tile",  "tex_tulle.jpg",      (2*THIRD,0.0,1.0,    0.5)),
    ("fabrics",  "tile",  "tex_sofa_beige.jpg", (0.0,   0.5, THIRD,  1.0)),
    ("fabrics",  "tile",  "tex_sofa_navy.jpg",  (THIRD, 0.5, 2*THIRD,1.0)),
    ("fabrics",  "tile",  "tex_shelf_white.jpg",(2*THIRD,0.5,1.0,    1.0)),

    # --- monitor (whole image) ---
    ("monitor",  "screen","tex_monitor.jpg",    (0.0,   0.0, 1.0,    1.0)),

    # --- decals sheet (2x2, magenta background) ---
    ("decals",   "decal", "decal_worldmap.png", (0.0,   0.0, 0.5,    0.5)),
    ("decals",   "decal", "decal_clock.png",    (0.5,   0.0, 1.0,    0.5)),
    ("decals",   "decal", "decal_frames.png",   (0.0,   0.5, 0.5,    1.0)),
    ("decals",   "decal", "decal_door.png",     (0.5,   0.5, 1.0,    1.0)),
]


def find_source(name: str) -> Path | None:
    for ext in (".png", ".jpg", ".jpeg", ".webp", ".bmp"):
        p = RAW / f"{name}{ext}"
        if p.exists():
            return p
    return None


def crop_cell(img: Image.Image, frac, inset=INSET) -> Image.Image:
    w, h = img.size
    x0, y0, x1, y1 = frac
    cw, ch = (x1 - x0) * w, (y1 - y0) * h
    box = (
        round(x0 * w + cw * inset),
        round(y0 * h + ch * inset),
        round(x1 * w - cw * inset),
        round(y1 * h - ch * inset),
    )
    return img.crop(box)


def center_square(img: Image.Image) -> Image.Image:
    w, h = img.size
    s = min(w, h)
    left, top = (w - s) // 2, (h - s) // 2
    return img.crop((left, top, left + s, top + s))


def key_magenta(img: Image.Image) -> Image.Image:
    """Turn the magenta background transparent and auto-crop to the object."""
    img = img.convert("RGBA")
    r, g, b, _ = img.split()
    r_hi = r.point(lambda v: 255 if v > KEY_R_MIN else 0)
    b_hi = b.point(lambda v: 255 if v > KEY_B_MIN else 0)
    g_lo = g.point(lambda v: 255 if v < KEY_G_MAX else 0)
    magenta = ImageChops.multiply(ImageChops.multiply(r_hi, b_hi), g_lo)
    alpha = ImageChops.invert(magenta)        # 0 on magenta, 255 on object
    # Erode the mask a couple of pixels to chew off the coloured fringe ring
    # left at anti-aliased object/background edges.
    for _ in range(2):
        alpha = alpha.filter(ImageFilter.MinFilter(3))
    # De-spill: kill any residual purple/blue halo on the kept pixels by
    # clamping blue to the (lower) green channel. Warm wood/skin (b<g) is
    # untouched; magenta spill (b>g) gets neutralised.
    b = ImageChops.darker(b, g)
    img = Image.merge("RGBA", (r, g, b, alpha))
    bbox = img.getbbox()                       # alpha-based tight box (Pillow >=9.2)
    if bbox:
        img = img.crop(bbox)
    return img


def main() -> int:
    if not RAW.exists():
        print(f"!! Put the 4 generated images into: {RAW}")
        return 1

    cache: dict[str, Image.Image] = {}
    missing, written = set(), 0

    for src, mode, out_name, frac in JOBS:
        if src not in cache:
            path = find_source(src)
            if path is None:
                missing.add(src)
                continue
            cache[src] = Image.open(path)
        cell = crop_cell(cache[src], frac)

        if mode == "tile":
            out = center_square(cell).resize((512, 512), Image.LANCZOS).convert("RGB")
            out.save(ROOT / out_name, quality=90)
        elif mode == "screen":
            out = cell.resize((1024, 1024), Image.LANCZOS).convert("RGB")
            out.save(ROOT / out_name, quality=92)
        elif mode == "decal":
            out = key_magenta(cell)
            out.thumbnail((1024, 1024), Image.LANCZOS)
            out.save(ROOT / out_name)
        print(f"  + {out_name:22s} {out.size}")
        written += 1

    if missing:
        print("\n!! Missing source sheets in _raw/ : " + ", ".join(sorted(missing)))
        print("   (expected base names: monitor, surfaces, fabrics, decals)")
    print(f"\nDone. Wrote {written} file(s) to {ROOT}")
    return 0 if not missing else 1


if __name__ == "__main__":
    raise SystemExit(main())
