"""Generate Lumen brand assets (app icon, foreground, splash mark, demo artwork).

Kept deterministic so repeated runs produce identical files.
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND_DIR = os.path.join(ROOT, "assets", "images", "brand")
DEMO_DIR = os.path.join(ROOT, "assets", "images", "demo")
os.makedirs(BRAND_DIR, exist_ok=True)
os.makedirs(DEMO_DIR, exist_ok=True)

SIZE = 2048
C1 = np.array([66, 110, 254], dtype=np.float64)   # DeepSeek-like aperture blue
C2 = np.array([116, 92, 255], dtype=np.float64)   # violet
C3 = np.array([64, 208, 255], dtype=np.float64)   # cyan highlight


def diagonal_gradient(size: int) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size]
    t = np.clip((x * 0.62 + y * 0.38) / (size - 1), 0, 1)
    t = t[..., None]
    rgb = C1 * (1 - t) + C2 * t
    # Soft cyan glow at the top-left, subtle inner light at bottom-right.
    dist = np.sqrt((x - size * 0.24) ** 2 + (y - size * 0.18) ** 2) / (size * 0.6)
    glow = np.clip(1 - dist, 0, 1)[..., None] ** 2 * 0.38
    rgb = rgb * (1 - glow) + C3 * glow
    return Image.fromarray(np.uint8(np.clip(rgb, 0, 255)), "RGB")


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def spark_points(cx: float, cy: float, radius: float, quality: int = 1440) -> list[tuple[float, float]]:
    """Four-point sparkle with inward-curved edges."""
    pts: list[tuple[float, float]] = []
    for i in range(quality):
        theta = 2 * math.pi * i / quality
        r = radius * (0.22 + 0.78 * abs(math.cos(2 * theta)) ** 2.2)
        pts.append((cx + r * math.cos(theta), cy + r * math.sin(theta)))
    return pts


def draw_spark(draw: ImageDraw.ImageDraw, cx: float, cy: float, radius: float, fill) -> None:
    draw.polygon(spark_points(cx, cy, radius), fill=fill)


def make_icon() -> None:
    grad = diagonal_gradient(SIZE)
    # Fine noise keeps large flat areas from banding on low-bit displays.
    rng = np.random.default_rng(20261025)
    noise = rng.normal(0, 1.7, (SIZE, SIZE, 1))
    arr = np.clip(np.asarray(grad, dtype=np.float64) + noise, 0, 255).astype(np.uint8)
    icon = Image.fromarray(arr, "RGB").convert("RGBA")
    icon.putalpha(rounded_mask(SIZE, int(SIZE * 0.225)))

    star = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(star)
    draw_spark(sd, SIZE * 0.5, SIZE * 0.5, SIZE * 0.33, (255, 255, 255, 255))
    # A small companion spark keeps the mark from feeling like a generic star.
    draw_spark(sd, SIZE * 0.735, SIZE * 0.275, SIZE * 0.072, (255, 255, 255, 205))
    star = star.filter(ImageFilter.GaussianBlur(SIZE * 0.0015))

    composed = Image.alpha_composite(icon, star)
    composed.resize((1024, 1024), Image.LANCZOS).save(os.path.join(BRAND_DIR, "app_icon.png"))

    # Adaptive icon foreground: transparent, star inside the 66% safe zone.
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fg)
    draw_spark(fd, SIZE * 0.5, SIZE * 0.5, SIZE * 0.26, (255, 255, 255, 255))
    draw_spark(fd, SIZE * 0.675, SIZE * 0.33, SIZE * 0.055, (255, 255, 255, 200))
    fg.resize((1024, 1024), Image.LANCZOS).save(
        os.path.join(BRAND_DIR, "app_icon_foreground.png")
    )

    # Splash mark: the same spark in brand blue on transparent.
    splash = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pd = ImageDraw.Draw(splash)
    draw_spark(pd, SIZE * 0.5, SIZE * 0.5, SIZE * 0.30, (66, 110, 254, 255))
    draw_spark(pd, SIZE * 0.71, SIZE * 0.29, SIZE * 0.062, (116, 92, 255, 220))
    splash.resize((512, 512), Image.LANCZOS).save(os.path.join(BRAND_DIR, "splash_mark.png"))

    # A monochrome white mark for dark surfaces.
    mono = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    md = ImageDraw.Draw(mono)
    draw_spark(md, SIZE * 0.5, SIZE * 0.5, SIZE * 0.30, (255, 255, 255, 255))
    mono.resize((512, 512), Image.LANCZOS).save(os.path.join(BRAND_DIR, "mark_white.png"))


def make_demo_art() -> None:
    w = h = 1600
    y, x = np.mgrid[0:h, 0:w]
    yy = y / (h - 1)
    xx = x / (w - 1)
    # Dusk gradient.
    top = np.array([20, 28, 64], dtype=np.float64)
    mid = np.array([75, 67, 200], dtype=np.float64)
    bottom = np.array([251, 146, 168], dtype=np.float64)
    t = yy[..., None]
    rgb = np.where(t < 0.58, top * (1 - t / 0.58) + mid * (t / 0.58), mid * (1 - (t - 0.58) / 0.42) + bottom * ((t - 0.58) / 0.42))
    # Sun disc with bloom.
    cx, cy, radius = 0.66 * w, 0.42 * h, 0.17 * w
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    sun = np.clip(1 - dist / radius, 0, 1)[..., None] ** 1.4
    sun_color = np.array([255, 224, 178], dtype=np.float64)
    rgb = rgb * (1 - sun * 0.88) + sun_color * (sun * 0.88)
    halo = np.clip(1 - dist / (radius * 2.6), 0, 1)[..., None] ** 3
    rgb = np.clip(rgb + np.array([255, 183, 120]) * halo * 0.35, 0, 255).astype(np.uint8)
    img = Image.fromarray(rgb, "RGB")
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    # Add a few translucent glass arcs to make the demo image feel designed.
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    d.ellipse((w * 0.06, h * 0.46, w * 0.58, h * 1.1), outline=(255, 255, 255, 96), width=5)
    d.ellipse((w * 0.34, h * 0.18, w * 0.98, h * 0.88), outline=(255, 255, 255, 64), width=3)
    d.arc((w * 0.18, h * 0.30, w * 0.80, h * 0.98), 210, 330, fill=(255, 255, 255, 130), width=4)
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
    img.save(os.path.join(DEMO_DIR, "demo_art.jpg"), quality=88, optimize=True)


if __name__ == "__main__":
    make_icon()
    make_demo_art()
    print("brand assets written")
