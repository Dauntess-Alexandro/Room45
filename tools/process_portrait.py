#!/usr/bin/env python3
"""Chroma-key a magenta portrait and apply a mild VOTV-style crunch."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from slice_assets import key_magenta  # noqa: E402

TARGET = (525, 416)  # same footprint as the old wall decal


def votv_crunch(img: Image.Image, pixel_w: int = 88) -> Image.Image:
	"""Downscale + nearest upscale + color crush — face reads less clearly."""
	img = img.convert("RGBA")
	r, g, b, a = img.split()
	rgb = Image.merge("RGB", (r, g, b))
	w, h = rgb.size
	small_h = max(1, round(h * pixel_w / w))
	tiny = rgb.resize((pixel_w, small_h), Image.LANCZOS)
	crunchy = tiny.resize((w, h), Image.NEAREST)
	# Limited palette + tiny blur smears facial detail.
	crunchy = crunchy.quantize(colors=36, method=Image.Quantize.MEDIANCUT).convert("RGB")
	crunchy = crunchy.filter(ImageFilter.GaussianBlur(radius=0.85))
	tiny2 = crunchy.resize((pixel_w, small_h), Image.BILINEAR)
	crunchy = tiny2.resize((w, h), Image.NEAREST)
	r2, g2, b2 = crunchy.split()
	return Image.merge("RGBA", (r2, g2, b2, a))


def fit_canvas(img: Image.Image, size: tuple[int, int]) -> Image.Image:
	tw, th = size
	kw, kh = img.size
	scale = min(tw / kw, th / kh)
	nw, nh = max(1, int(kw * scale)), max(1, int(kh * scale))
	fitted = img.resize((nw, nh), Image.LANCZOS)
	canvas = Image.new("RGBA", size, (0, 0, 0, 0))
	canvas.paste(fitted, ((tw - nw) // 2, (th - nh) // 2), fitted)
	return canvas


def process(src: Path, out: Path, pixel_w: int = 88) -> None:
	img = Image.open(src)
	keyed = key_magenta(img)
	print(f"  keyed: {keyed.size}")
	crunched = votv_crunch(keyed, pixel_w=pixel_w)
	final = fit_canvas(crunched, TARGET)
	final.save(out)
	print(f"  saved: {out} ({final.size})")


if __name__ == "__main__":
	src = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "_raw" / "portrait.png"
	out = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "decal_frames.png"
	pw = int(sys.argv[3]) if len(sys.argv) > 3 else 88
	if not src.exists():
		raise SystemExit(f"Missing source: {src}")
	process(src, out, pw)
