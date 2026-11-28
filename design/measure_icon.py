"""Measures an icon's mark against the Warhound sizing brief (74% span, 10% stroke, centred).
Reads transparent icons by opacity and opaque ones by brightness, so every variant can be checked.
Usage: python3 design/measure_icon.py icon.png [--watch]"""
import sys
import numpy as np
from PIL import Image

path = sys.argv[1]
watch = "--watch" in sys.argv
img = Image.open(path).convert("RGBA")
a = np.asarray(img).astype(float) / 255
rgb, alpha = a[..., :3], a[..., 3]
# Transparent icons (dark, tinted): the mark is whatever is opaque. Opaque icons: the mark is
# anything brighter than the dark background and its glow, which works for pale and grey themes too.
mask = alpha > 0.5 if (alpha < 0.5).any() else rgb.max(-1) > 0.45
h, w = mask.shape
ys, xs = np.nonzero(mask)
x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
span = max(x1 - x0, y1 - y0) / w
cx, cy = (x0 + x1) / 2 / w - 0.5, (y0 + y1) / 2 / h - 0.5
row = mask[h // 2]
first = np.argmax(row)
stroke = (np.argmax(~row[first:])) / w
reach = np.sqrt(((xs + 0.5 - w / 2) ** 2 + (ys + 0.5 - h / 2) ** 2).max()) / w

ok = lambda c: "OK" if c else "FAIL"
if watch:
    print(f"reach       {reach*100:.1f}%  target <= 43%           {ok(reach <= 0.43 + 0.005)}")
else:
    print(f"mark span   {span*100:.1f}%  target 74% ±2%   {ok(abs(span - 0.74) <= 0.02)}")
print(f"stroke      {stroke*100:.1f}%  target 10% ±1%   {ok(abs(stroke - 0.10) <= 0.01)}")
print(f"off-centre  x {cx*100:+.1f}%, y {cy*100:+.1f}%   target within ±1.5%   {ok(abs(cx) <= 0.015 and abs(cy) <= 0.015)}")
