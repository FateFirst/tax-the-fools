#!/usr/bin/env python3
"""Cut the logo and the minimap button out of the Gemini artwork.

The source is a JPEG with a transparency checkerboard baked into its pixels,
so there is no real alpha to keep. Removal works like this:

- Logo: every checker-coloured pixel (colourless, mid-grey to white: the
  squares are about #888 and #c8c8c8) goes if it is
  connected to the crop's border, or if it belongs to a large enclosed patch,
  such as the gap between the arm and the fool's head. Small light patches
  (eye whites, coin glints) are part of the art and stay.
- Minimap: the button is a circle with a gold ring, so its circle is found
  from the ring and everything outside it goes.

Output is the only format this client takes from an addon folder: TGA,
32 bit with alpha, uncompressed, power-of-two sides.

Usage: tools/make-icons.py [source image]
Needs ffmpeg (to decode the JPEG). Standard library otherwise.
"""
import math
import os
import struct
import subprocess
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "assets", "Gemini_Generated_Image_ex8hqgex8hqgex8h.jfif")
OUT = os.path.join(ROOT, "TaxTheFools", "media")

# Regions of the 2816x1536 source, found by eye from a preview and padded.
LOGO_BOX = (300, 120, 1720, 1420)      # x0, y0, x1, y1
MINIMAP_BOX = (1900, 500, 2560, 1160)

BIG_PATCH = 3000        # enclosed light patches larger than this are background


def decode(path):
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                            "stream=width,height", "-of", "csv=p=0", path],
                           capture_output=True, text=True, check=True).stdout.strip()
    w, h = (int(v) for v in probe.split(","))
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    return w, h, raw


def crop(w, raw, box):
    x0, y0, x1, y1 = box
    cw, ch = x1 - x0, y1 - y0
    px = []
    for y in range(y0, y1):
        row = raw[(y * w + x0) * 3:(y * w + x1) * 3]
        for x in range(cw):
            px.append((row[x * 3], row[x * 3 + 1], row[x * 3 + 2]))
    return cw, ch, px


def checker(p):
    r, g, b = p
    return max(r, g, b) - min(r, g, b) < 20 and min(r, g, b) > 115


def cut_logo(cw, ch, px):
    light = [checker(p) for p in px]
    alpha = [255] * (cw * ch)
    seen = [False] * (cw * ch)
    for start in range(cw * ch):
        if not light[start] or seen[start]:
            continue
        # one connected light patch
        patch, touches = [], False
        q = deque([start])
        seen[start] = True
        while q:
            i = q.popleft()
            patch.append(i)
            x, y = i % cw, i // cw
            if x == 0 or y == 0 or x == cw - 1 or y == ch - 1:
                touches = True
            for j in (i - 1 if x > 0 else -1, i + 1 if x < cw - 1 else -1, i - cw if y > 0 else -1,
                      i + cw if y < ch - 1 else -1):
                if j >= 0 and not seen[j] and light[j]:
                    seen[j] = True
                    q.append(j)
        if touches or len(patch) > BIG_PATCH:
            for i in patch:
                alpha[i] = 0
    # JPEG fringe: a light-ish pixel next to removed background goes too.
    fringe = []
    for i in range(cw * ch):
        if alpha[i] == 0:
            continue
        r, g, b = px[i]
        if max(r, g, b) - min(r, g, b) < 30 and min(r, g, b) > 100:
            x, y = i % cw, i // cw
            for j in (i - 1, i + 1, i - cw, i + cw):
                if 0 <= j < cw * ch and alpha[j] == 0:
                    fringe.append(i)
                    break
    for i in fringe:
        alpha[i] = 0
    return alpha


def cut_circle(cw, ch, px):
    # The ring is the outermost non-checker shape in the box: its bounding box gives the circle.
    xs, ys = [], []
    for i, p in enumerate(px):
        if not checker(p) and max(p) - min(p) > 25:      # coloured, not grey text
            xs.append(i % cw)
            ys.append(i // cw)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    r = min(x1 - x0, y1 - y0) / 2 - 1
    alpha = []
    for i in range(cw * ch):
        x, y = i % cw + 0.5, i // cw + 0.5
        d = math.hypot(x - cx, y - cy)
        alpha.append(255 if d <= r - 1 else 0 if d >= r else int(255 * (r - d)))
    return alpha, (int(cx - r), int(cy - r), int(cx + r), int(cy + r))


def square_bbox(cw, ch, alpha, pad=8):
    xs = [i % cw for i in range(cw * ch) if alpha[i]]
    ys = [i // cw for i in range(cw * ch) if alpha[i]]
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    side = max(x1 - x0, y1 - y0) + 2 * pad
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    return cx - side // 2, cy - side // 2, side


def resample(cw, ch, px, alpha, x0, y0, side, size):
    """Box-filter a side x side square (origin x0, y0; outside = transparent) down to size x size.
    Colour is averaged weighted by alpha so edges don't pick up dark halos."""
    out = []
    step = side / size
    for oy in range(size):
        for ox in range(size):
            sx0, sx1 = int(x0 + ox * step), int(x0 + (ox + 1) * step)
            sy0, sy1 = int(y0 + oy * step), int(y0 + (oy + 1) * step)
            n = a_sum = r_sum = g_sum = b_sum = 0
            for y in range(sy0, max(sy1, sy0 + 1)):
                for x in range(sx0, max(sx1, sx0 + 1)):
                    n += 1
                    if 0 <= x < cw and 0 <= y < ch:
                        a = alpha[y * cw + x]
                        if a:
                            r, g, b = px[y * cw + x]
                            a_sum += a
                            r_sum += r * a
                            g_sum += g * a
                            b_sum += b * a
            if a_sum:
                out.append((r_sum // a_sum, g_sum // a_sum, b_sum // a_sum, a_sum // n))
            else:
                out.append((0, 0, 0, 0))
    return out


def write_tga(path, size, rgba):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
    body = bytearray()
    for y in range(size - 1, -1, -1):          # bottom-left origin
        for x in range(size):
            r, g, b, a = rgba[y * size + x]
            body += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(header + bytes(body))


def write_preview(path, size, rgba):
    """PNG over a dark panel colour, to eyeball the cut-out."""
    bg = (0x20, 0x20, 0x20)
    raw = bytearray()
    for r, g, b, a in rgba:
        raw += bytes(((r * a + bg[0] * (255 - a)) // 255, (g * a + bg[1] * (255 - a)) // 255,
                      (b * a + bg[2] * (255 - a)) // 255))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{size}x{size}",
                    "-i", "-", path], input=bytes(raw), check=True)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    preview_dir = os.environ.get("PREVIEW_DIR")
    w, h, raw = decode(src)

    cw, ch, px = crop(w, raw, LOGO_BOX)
    alpha = cut_logo(cw, ch, px)
    x0, y0, side = square_bbox(cw, ch, alpha)
    logo = resample(cw, ch, px, alpha, x0, y0, side, 128)
    write_tga(os.path.join(OUT, "logo.tga"), 128, logo)
    print("logo.tga ok (128x128)")

    cw, ch, px = crop(w, raw, MINIMAP_BOX)
    alpha, (bx0, by0, bx1, by1) = cut_circle(cw, ch, px)
    mini = resample(cw, ch, px, alpha, bx0, by0, bx1 - bx0, 64)
    write_tga(os.path.join(OUT, "minimap.tga"), 64, mini)
    print("minimap.tga ok (64x64)")

    if preview_dir:
        write_preview(os.path.join(preview_dir, "logo-preview.png"), 128, logo)
        write_preview(os.path.join(preview_dir, "minimap-preview.png"), 64, mini)


if __name__ == "__main__":
    main()
