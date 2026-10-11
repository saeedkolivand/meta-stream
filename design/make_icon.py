"""Renders the MetaStream icon (iOS AppIcon.png + previews): python design/make_icon.py <out_dir>. The Android vectors in
android/app/src/main/res/drawable/ic_launcher_*.xml and both splash screens use the same geometry and colours."""
import math
import sys
import numpy as np
from PIL import Image, ImageDraw

C = 54.0
BG_A, BG_B = (0x34, 0x0E, 0x9E), (0x06, 0x05, 0x1C)  # top-left -> bottom-right
GLOW = (0x6D, 0x3B, 0xFF)
RED_A, RED_B = (0xFF, 0x7A, 0x3D), (0xFF, 0x1F, 0x5A)
ARCS = [(15.5, 5.0, None), (25.5, 5.0, ((0x3D, 0xE8, 0xFF), (0xC8, 0x4B, 0xFF)))]  # radius, stroke, gradient (None = white)
SPAN = 42  # degrees either side of horizontal
DOT = 7.5


def render(size, k):
    """size px canvas; k scales the mark around the centre (1 = Android geometry)."""
    ss = 4
    n = size * ss
    u = n / 108.0  # px per unit
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    t = np.clip((x + y) / (2 * n), 0, 1)[..., None]
    img = np.array(BG_A) * (1 - t) + np.array(BG_B) * t
    d = np.hypot(x - C * u, y - C * u) / u
    g = np.clip(1 - d / (42 * k), 0, 1)[..., None] ** 2 * 0.65
    img = img * (1 - g) + np.array(GLOW) * g
    g = np.clip(1 - d / (16 * k), 0, 1)[..., None] ** 2 * 0.6
    img = img * (1 - g) + np.array(RED_B) * g
    base = Image.fromarray(img.astype(np.uint8), "RGB").convert("RGBA")

    over = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    for r, w, grad in ARCS:
        r, w = r * k * u, w * k * u
        m = Image.new("L", (n, n), 0)
        ld = ImageDraw.Draw(m)
        for mid in (0, 180):
            box = [C * u - r, C * u - r, C * u + r, C * u + r]
            ld.arc(box, mid - SPAN, mid + SPAN, fill=255, width=int(w))
            for ang in (mid - SPAN, mid + SPAN):
                # cap centre sits mid-stroke (PIL draws the width inward from the box edge)
                rc = r - w / 2
                cx, cy = C * u + rc * math.cos(math.radians(ang)), C * u + rc * math.sin(math.radians(ang))
                ld.ellipse([cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2], fill=255)
        if grad is None:
            fill = Image.new("RGBA", (n, n), (255, 255, 255, 255))
        else:
            tv = np.clip((y - (C * u - r)) / (2 * r), 0, 1)[..., None]
            fill = Image.fromarray((np.array(grad[0]) * (1 - tv) + np.array(grad[1]) * tv).astype(np.uint8), "RGB").convert("RGBA")
        fill.putalpha(m)
        over = Image.alpha_composite(over, fill)
    # dot with a vertical warm gradient + soft highlight
    rr = DOT * k * u
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse([C * u - rr, C * u - rr, C * u + rr, C * u + rr], fill=255)
    tt = np.clip((y - (C * u - rr)) / (2 * rr), 0, 1)[..., None]
    grad = (np.array(RED_A) * (1 - tt) + np.array(RED_B) * tt).astype(np.uint8)
    dot = Image.fromarray(grad, "RGB").convert("RGBA")
    dot.putalpha(mask)
    over = Image.alpha_composite(over, dot)
    hr, hx, hy = 2.4 * k * u, (C - 2.6 * k) * u, (C - 2.6 * k) * u
    hl = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(255, 255, 255, 90))
    over = Image.alpha_composite(over, hl)
    out = Image.alpha_composite(base, over).convert("RGB")
    return out.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1]
    ios = render(1024, 1.32)
    ios.save(f"{out}/AppIcon.png")
    # preview: iOS rounded mask + Android circle mask (adaptive icons crop to the inner 72/108)
    prev = Image.new("RGB", (1100, 560), (240, 240, 240))
    m = Image.new("L", (512, 512), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, 511, 511], 115, fill=255)
    prev.paste(ios.resize((512, 512), Image.LANCZOS), (24, 24), m)
    a = render(768, 1.0).crop((128, 128, 640, 640))
    m2 = Image.new("L", (512, 512), 0)
    ImageDraw.Draw(m2).ellipse([0, 0, 511, 511], fill=255)
    prev.paste(a, (564, 24), m2)
    prev.save(f"{out}/preview.png")
    small = Image.new("RGB", (300, 120), (30, 30, 30))
    for i, s in enumerate((96, 60, 40)):
        small.paste(ios.resize((s, s), Image.LANCZOS), (10 + i * 110, 10))
    small.save(f"{out}/preview_small.png")
