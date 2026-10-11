"""Renders the MetaStream icon: python design/make_icon.py <out_dir> [android_layer.png].

A titanium-rimmed camera lens on graphite with a red "live" tally light in the glass. Writes <out_dir>/AppIcon.png
(iOS, 1024, opaque) and preview.png; with a second argument also the Android adaptive-icon layer (432 px = 108 dp at
xxxhdpi). The splash screens on both platforms draw the same lens (radii below, scaled) and open it onto the camera.
"""
import math
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

BG_TOP, BG_BOT = (0x22, 0x22, 0x25), (0x0A, 0x0A, 0x0C)
RIM_OUT, RIM_IN, HAIRLINE, DOT = 0.335, 0.300, 0.205, 0.062  # radii as fractions of the icon side


def render(size, k=1.0, ss=3):
    """k scales the lens: 1 for iOS; 72/108 for the Android layer, whose launcher mask shows only the inner 72 dp."""
    n = size * ss
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = n / 2
    dist = np.hypot(x - c, y - c) / n

    def disc(r, cx=0.5, cy=0.5):
        d = np.hypot(x / n - cx, y / n - cy)
        return np.clip((r * k - d) / 0.0012 + 0.5, 0, 1)[..., None]

    def ring(r, w):
        return np.clip((w * k / 2 - np.abs(dist - r * k)) / 0.0012 + 0.5, 0, 1)[..., None]

    def blur(a, sigma):
        im = Image.fromarray(np.clip(a[..., 0] * 255, 0, 255).astype(np.uint8), "L")
        return (np.asarray(im.filter(ImageFilter.GaussianBlur(sigma * k * n)), np.float32) / 255)[..., None]

    def over(img, col, a):
        return img * (1 - a) + np.array(col, np.float32) * a

    t = (y / n)[..., None]
    img = np.array(BG_TOP, np.float32) * (1 - t) + np.array(BG_BOT, np.float32) * t
    # Titanium rim, lit from the top-left.
    light = (0.5 + 0.5 * np.cos(np.arctan2(y - c, x - c) + 3 * math.pi / 4))[..., None]
    rim = disc(RIM_OUT) - disc(RIM_IN)
    rim_col = np.array((0x3A, 0x3A, 0x3E), np.float32) * (1 - light) + np.array((0xC8, 0xC8, 0xCE), np.float32) * light
    img = img * (1 - rim) + rim_col * rim
    # Dark glass, a faint inner element ring and a soft reflection arc.
    glass = disc(RIM_IN)
    g = np.clip(dist / (RIM_IN * k), 0, 1)[..., None]
    img = img * (1 - glass) + (np.array((0x16, 0x18, 0x1E), np.float32) * (1 - g) + np.array((2, 2, 3), np.float32) * g) * glass
    img = over(img, (255, 255, 255), ring(HAIRLINE, 0.004) * 0.07 * glass)
    off = 0.03 * k
    arc = (disc(0.27, 0.5 - off, 0.5 - off) - disc(0.27, 0.5, 0.5 + 0.02 * k)).clip(0, 1) * glass
    img = over(img, (255, 255, 255), blur(arc, 0.01) * 0.16)
    # Red tally light: additive bloom, warm vertical gradient, glassy top highlight.
    img = img + np.array((255, 40, 20), np.float32) * blur(disc(DOT * 1.05), DOT * 0.9) * 0.81
    m = disc(DOT)
    td = np.clip((y / n - (0.5 - DOT * k)) / (2 * DOT * k), 0, 1)[..., None]
    img = img * (1 - m) + (np.array((0xFF, 0x5A, 0x3C), np.float32) * (1 - td) + np.array((0xE8, 0x10, 0x1E), np.float32) * td) * m
    hl = blur(disc(DOT * 0.72, 0.5, 0.5 - DOT * 0.32 * k) * m, DOT * 0.12) * 0.28
    img = over(img, (255, 255, 255), hl)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1]
    ios = render(1024)
    ios.save(f"{out}/AppIcon.png")
    if len(sys.argv) > 2:
        render(432, 72 / 108).save(sys.argv[2])
    prev = Image.new("RGB", (1100, 560), (128, 128, 132))
    m = Image.new("L", (512, 512), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, 511, 511], 115, fill=255)
    prev.paste(ios.resize((512, 512), Image.LANCZOS), (24, 24), m)
    a = render(768, 72 / 108).crop((128, 128, 640, 640))  # what an Android launcher circle mask shows
    m2 = Image.new("L", (512, 512), 0)
    ImageDraw.Draw(m2).ellipse([0, 0, 511, 511], fill=255)
    prev.paste(a, (564, 24), m2)
    prev.save(f"{out}/preview.png")
