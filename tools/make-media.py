#!/usr/bin/env python3
"""Draw the addon's textures as white masks that the theme tints at run time.

The client only loads textures from an addon folder as TGA: 32 bit with alpha,
uncompressed, power-of-two sides. Anything else fails silently and looks like
a button that works but draws nothing, so every file is checked after writing.
Standard library only.
"""
import math
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "TaxTheFools", "media")
SS = 4  # supersamples per axis, for antialiased edges


def write_tga(path, w, h, alpha):
    # 18-byte header: uncompressed true colour (type 2), 32 bpp, 8 alpha bits,
    # bottom-left origin -- so rows are written bottom first.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    body = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            body += bytes((255, 255, 255, alpha(x, y)))
    with open(path, "wb") as f:
        f.write(header + bytes(body))


def coverage(inside):
    def alpha(x, y):
        hit = 0
        for i in range(SS):
            for j in range(SS):
                if inside(x + (i + 0.5) / SS, y + (j + 0.5) / SS):
                    hit += 1
        return round(255 * hit / (SS * SS))
    return alpha


def rrect(w, h, r):
    """Signed distance to a rounded rectangle covering [0,w] x [0,h]."""
    def sd(px, py):
        qx = abs(px - w / 2) - (w / 2 - r)
        qy = abs(py - h / 2) - (h / 2 - r)
        return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    return sd


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def strokes(segments, width):
    return lambda x, y: any(seg_dist(x, y, *s) <= width / 2 for s in segments)


def dots(points, radius):
    return lambda x, y: any(math.hypot(x - cx, y - cy) <= radius for cx, cy in points)


PANEL = rrect(32, 32, 10)
TAB = rrect(32, 32, 5)

# name: (width, height, inside(x, y)) with y measured from the top
SHAPES = {
    "solid": (8, 8, lambda x, y: True),
    "panel-fill": (32, 32, lambda x, y: PANEL(x, y) <= 0),
    "panel-border": (32, 32, lambda x, y: -1 <= PANEL(x, y) <= 0),
    "tab-fill": (32, 32, lambda x, y: TAB(x, y) <= 0),
    "tab-border": (32, 32, lambda x, y: -1 <= TAB(x, y) <= 0),
    "circle": (32, 32, lambda x, y: math.hypot(x - 16, y - 16) <= 15.5),
    "icon-close": (32, 32, strokes([(9, 9, 23, 23), (23, 9, 9, 23)], 3)),
    "icon-check": (32, 32, strokes([(8, 17, 14, 23), (14, 23, 24, 9)], 3)),
    "icon-caret-down": (32, 32, strokes([(9, 12, 16, 20), (16, 20, 23, 12)], 3)),
    "icon-caret-up": (32, 32, strokes([(9, 20, 16, 12), (16, 12, 23, 20)], 3)),
    "icon-arrow-left": (32, 32, strokes([(20, 8, 12, 16), (12, 16, 20, 24)], 3)),
    "icon-arrow-right": (32, 32, strokes([(12, 8, 20, 16), (20, 16, 12, 24)], 3)),
    "icon-grip": (16, 16, dots([(12, 4), (12, 8), (8, 8), (12, 12), (8, 12), (4, 12)], 1.3)),
}


def check(path, w, h):
    with open(path, "rb") as f:
        head = f.read(18)
    kind, bpp = head[2], head[16]
    pw, ph = struct.unpack("<HH", head[12:16])
    assert kind == 2, f"{path}: not uncompressed true colour (type {kind})"
    assert bpp == 32, f"{path}: not 32 bit ({bpp})"
    assert (pw, ph) == (w, h) and pw & (pw - 1) == 0 and ph & (ph - 1) == 0, f"{path}: bad size {pw}x{ph}"


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (w, h, inside) in SHAPES.items():
        path = os.path.join(OUT, name + ".tga")
        write_tga(path, w, h, coverage(inside))
        check(path, w, h)
        print(f"{name}.tga ok ({w}x{h})")


if __name__ == "__main__":
    main()
