#!/usr/bin/env python3
"""Make any picture ready to use as an e-ink screensaver.

The image is converted to grayscale and placed, uncropped, in the middle of a
portrait canvas filled with the picture's own background tone.

    pip install pillow
    python3 tools/prepare-screensaver.py photo.jpg minimalhome.koplugin/screensavers/photo.png
    python3 tools/prepare-screensaver.py --size 1072x1448 in.png out.png   # Paperwhite
"""
import argparse
import statistics

from PIL import Image


def edge_tone(img):
    w, h = img.size
    px = [img.getpixel((x, 0)) for x in range(0, w, 7)]
    px += [img.getpixel((x, h - 1)) for x in range(0, w, 7)]
    px += [img.getpixel((0, y)) for y in range(0, h, 7)]
    px += [img.getpixel((w - 1, y)) for y in range(0, h, 7)]
    return int(statistics.median(px))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size", default="1264x1680", help="screen size WxH (default: Kindle Oasis)")
    ap.add_argument("--gamma", type=float, default=1.0,
                    help="values above 1 darken mid-tones (helps light colors survive grayscale)")
    a = ap.parse_args()

    W, H = (int(v) for v in a.size.lower().split("x"))
    img = Image.open(a.src).convert("L")
    if a.gamma != 1.0:
        img = img.point(lambda v: int(255 * ((v / 255) ** a.gamma)))
    bg = edge_tone(img)
    s = min(W / img.width, H / img.height)
    img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    out = Image.new("L", (W, H), bg)
    out.paste(img, ((W - img.width) // 2, (H - img.height) // 2))
    out.save(a.dst, optimize=True)
    print(f"{a.dst}: {W}x{H}")


if __name__ == "__main__":
    main()
