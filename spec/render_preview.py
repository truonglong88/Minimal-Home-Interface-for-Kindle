"""Turn the paint operations recorded by smoke_home.lua into PNG previews.

Approximate: text widths come from the real fonts here, but line breaking and
truncation were decided in Lua with estimated widths. Use it to review the
layout, not as a pixel-exact KOReader screenshot.

Usage: python3 spec/render_preview.py screens.json out_dir [covers_dir]
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT_DIR = os.path.join(os.path.dirname(__file__), "..", "minimalhome.koplugin", "fonts")
_fonts = {}


def font(path, size):
    name = os.path.basename(path)
    key = (name, size)
    if key not in _fonts:
        try:
            _fonts[key] = ImageFont.truetype(os.path.join(FONT_DIR, name), size)
        except OSError:
            _fonts[key] = ImageFont.load_default()
    return _fonts[key]


def gray(v):
    return int(round(255 * (1 - float(v))))


def render(screen, covers_dir):
    screen_img = Image.new("L", (1264, 1680), 255)
    layer, clip = None, None

    def flush():
        nonlocal layer, clip
        if layer is not None:
            x, y, w, h = clip
            screen_img.paste(layer.crop((x, y, x + w, y + h)), (x, y))
        layer, clip = None, None

    for op in screen["ops"]:
        op = list(op)
        this_clip = None
        if op and isinstance(op[-1], list) and op[-1] and op[-1][0] == "clip":
            this_clip = tuple(op.pop()[1:])
        if this_clip != clip:
            flush()
            if this_clip:
                clip, layer = this_clip, Image.new("L", (1264, 1680), 255)
        img = layer if layer is not None else screen_img
        d = ImageDraw.Draw(img)
        kind = op[0]
        if kind == "rect":
            _, x, y, w, h, c = op[:6]
            r = op[6] if len(op) > 6 else 0
            if w > 0 and h > 0:
                d.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=r or 0, fill=gray(c))
        elif kind == "border":
            _, x, y, w, h, bw, c, r = op
            d.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius=r or 0, outline=gray(c), width=bw)
        elif kind == "text":
            _, x, y, text, path, size, c = op[:7]
            f = font(path, size)
            if len(op) > 8 and op[7] == "center":
                x = x + (op[8] - d.textlength(text, font=f)) / 2
            d.text((x, y + size * 0.1), text, font=f, fill=gray(c))
        elif kind == "image":
            _, x, y, w, h, name = op
            title = os.path.splitext(os.path.basename(name))[0]
            path = os.path.join(covers_dir, title + ".png") if covers_dir else None
            if path and os.path.exists(path):
                cov = Image.open(path).convert("L")
                s = max(w / cov.width, h / cov.height)
                cov = cov.resize((max(1, int(cov.width * s)), max(1, int(cov.height * s))))
                l, t = (cov.width - w) // 2, (cov.height - h) // 2
                img.paste(cov.crop((l, t, l + w, t + h)), (x, y))
            else:
                d.rectangle([x, y, x + w - 1, y + h - 1], fill=200)
        elif kind == "icon":
            _, x, y, w, h, name = op
            if "search" in name:
                d.ellipse([x + w * 0.12, y + w * 0.12, x + w * 0.68, y + w * 0.68], outline=0, width=max(2, w // 12))
                d.line([x + w * 0.6, y + w * 0.6, x + w * 0.9, y + w * 0.9], fill=0, width=max(2, w // 10))
            else:
                for i, yy in enumerate((0.25, 0.5, 0.75)):
                    d.line([x + w * 0.15, y + h * yy, x + w * 0.85, y + h * yy], fill=0, width=max(2, w // 14))
                    cx = x + w * (0.65, 0.35, 0.72)[i]
                    d.ellipse([cx - w * 0.09, y + h * yy - w * 0.09, cx + w * 0.09, y + h * yy + w * 0.09], fill=255, outline=0, width=max(2, w // 16))
    flush()
    return screen_img


def main():
    src, out = sys.argv[1], sys.argv[2]
    covers = sys.argv[3] if len(sys.argv) > 3 else None
    os.makedirs(out, exist_ok=True)
    seen = set()
    for s in json.load(open(src)):
        key = (s["scenario"], s["page"])
        if key in seen:
            continue
        seen.add(key)
        name = f"{s['scenario']}-p{s['page']}.png"
        render(s, covers).save(os.path.join(out, name))
        print(name)


if __name__ == "__main__":
    main()
