#!/usr/bin/env python3
"""Project the DineCircle master artwork into every raster brand surface.

`assets/branding/dinecircle_master.png` is the authored lockup: the arc + "D" +
fork mark over a dark field, the DineCircle wordmark, a candlelit table and an
orange sweep. A launcher icon cannot carry the wordmark or the photograph --
at 48dp they collapse into noise -- so this script crops the mark out of the
master, keys its dark field to alpha, and re-plates it on the brand field at
every size the platform asks for. The crop is detected from the art rather than
hardcoded, so a re-exported master (different padding or resolution) still
resolves.

Outputs
    assets/branding/dinecircle_logo.png       1024  legacy + iOS + web icon
    assets/branding/dinecircle_foreground.png 1024  adaptive foreground
    assets/branding/dinecircle_monochrome.png 1024  Android 13+ themed icon
    assets/images/brand_mark.png               512  in-app mark (transparent)
    android/app/src/main/res/drawable-*/launch_logo.png   splash art per density
    web/icons/*.png, web/favicon.png               PWA icons + browser tab icon

Usage:
    python3 tool/branding/generate_brand_assets.py
    /home/til3fishnix001/flutter/bin/dart run flutter_launcher_icons
"""

from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image

# ─── Brand tokens (lib/theme/app_colors.dart) ────────────────────────────────
BG = (0x0A, 0x09, 0x0C)  # AppColors.bg

ROOT = pathlib.Path(__file__).resolve().parents[2]
MASTER = ROOT / "assets" / "branding" / "dinecircle_master.png"
OUT_DIR = ROOT / "assets" / "branding"
APP_MARK = ROOT / "assets" / "images" / "brand_mark.png"
RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"
WEB_DIR = ROOT / "web" / "icons"
WEB_FAVICON = ROOT / "web" / "favicon.png"

# Fraction of the master that holds the mark. The lower band carries the
# wordmark and the photograph, and the right edge carries the orange sweep.
MARK_BAND = (0.12, 0.68, 0.56)  # (top, right, bottom) as fractions of width/height

# Ink is either bright (the white D, the fork) or saturated (the orange arc and
# its end dot); the field stays below 0.16 on every channel. Keying that gap to
# alpha keeps the arc's negative space and the fork tines as true openings.
INK_BRIGHT = 0.50
INK_SATURATION = 0.55
INK_SAT_MIN_VALUE = 0.30
KEY_RANGE = (0.35, 0.60)

PAD = 26  # px of breathing room around the detected ink box

# Adaptive icons: the launcher masks the 108dp layer to 72dp, so every layer
# must keep its content inside the central 66dp (~61%) safe zone.
SAFE_ZONE = 66 / 108

# Android splash art is emitted straight into the resource tree so every
# density bucket resolves to the same physical size: 96dp for the pre-API-31
# window background, and a 288dp canvas with 192dp of art for the API 31+ splash
# API (which masks the icon to a circle, so the art must stay in the 2/3 zone).
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
SPLASH_DP = 96
SPLASH_ANDROID12_DP = 288


# ─── Mark extraction ─────────────────────────────────────────────────────────
def extract_mark(master: Image.Image) -> Image.Image:
    """Keyed, square, transparent mark cropped out of the master lockup."""
    width, height = master.size
    rgb = np.asarray(master.convert("RGB")).astype(np.float32) / 255.0
    value = rgb.max(2)
    chroma = rgb.max(2) - rgb.min(2)
    saturation = np.where(value > 1e-6, chroma / np.maximum(value, 1e-6), 0.0)

    ink = (value > INK_BRIGHT) | (
        (saturation > INK_SATURATION) & (value > INK_SAT_MIN_VALUE)
    )
    # Restrict to the mark band so the wordmark and the orange sweep stay out.
    top, right, bottom = MARK_BAND
    band = np.zeros_like(ink)
    band[int(top * height) : int(bottom * height), : int(right * width)] = True
    rows, cols = np.nonzero(ink & band)
    if rows.size == 0:
        raise SystemExit(f"no mark found in {MASTER}")

    crop = master.crop(
        (
            int(cols.min()) - PAD,
            int(rows.min()) - PAD,
            int(cols.max()) + PAD,
            int(rows.max()) + PAD,
        )
    ).convert("RGB")
    alpha = np.clip(
        (np.asarray(crop).astype(np.float32).max(2) / 255.0 - KEY_RANGE[0])
        / (KEY_RANGE[1] - KEY_RANGE[0]),
        0.0,
        1.0,
    )
    layer = crop.convert("RGBA")
    layer.putalpha(Image.fromarray((alpha * 255).round().astype(np.uint8)))

    side = max(layer.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(layer, ((side - layer.width) // 2, (side - layer.height) // 2))
    return square


def place(mark: Image.Image, size: int, fraction: float) -> Image.Image:
    """The mark scaled to `fraction` of `size`, centred on a transparent square."""
    art_side = int(round(size * fraction))
    art = mark.resize((art_side, art_side), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - art_side) // 2
    canvas.paste(art, (offset, offset))
    return canvas


def on_field(layer: Image.Image, background: tuple[int, int, int]) -> Image.Image:
    """Flatten a transparent layer onto an opaque brand field."""
    canvas = Image.new("RGBA", layer.size, (*background, 255))
    canvas.alpha_composite(layer)
    return canvas


def white(layer: Image.Image) -> Image.Image:
    """Themed icon: white RGB with the mark's alpha, tinted by the launcher."""
    solid = Image.new("RGBA", layer.size, (255, 255, 255, 0))
    solid.putalpha(layer.getchannel("A"))
    return solid


# ─── Outputs ─────────────────────────────────────────────────────────────────
def write_launcher_sources(mark: Image.Image) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    targets = {
        # Legacy launcher icon (<API 26) and the iOS/web icon master.
        "dinecircle_logo.png": on_field(place(mark, 1024, 0.84), BG),
        # Adaptive foreground layer (safe zone only, transparent).
        "dinecircle_foreground.png": place(mark, 1024, SAFE_ZONE),
        # Themed/monochrome layer for One UI "apply themed icons".
        "dinecircle_monochrome.png": white(place(mark, 1024, SAFE_ZONE)),
    }
    for name, image in targets.items():
        path = OUT_DIR / name
        image.save(path, "PNG", optimize=True)
        print(f"{path.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}")

    # In-app mark, drawn on the splash/auth screens over the app background.
    APP_MARK.parent.mkdir(parents=True, exist_ok=True)
    app_mark = place(mark, 512, 0.98)
    app_mark.save(APP_MARK, "PNG", optimize=True)
    print(f"{APP_MARK.relative_to(ROOT)}  {app_mark.size[0]}x{app_mark.size[1]}")


def write_web_icons(mark: Image.Image) -> None:
    """PWA icons and the browser tab icon.

    Maskable variants keep the mark inside the 80% safe circle that Android and
    Chrome crop to, so the arc never loses its outer edge when installed. The
    favicon gets a larger mark because a 32px tab has no room for margins.
    """
    WEB_DIR.mkdir(parents=True, exist_ok=True)
    targets = {
        WEB_DIR / "Icon-192.png": (192, 0.84),
        WEB_DIR / "Icon-512.png": (512, 0.84),
        WEB_DIR / "Icon-maskable-192.png": (192, 0.64),
        WEB_DIR / "Icon-maskable-512.png": (512, 0.64),
        WEB_FAVICON: (64, 0.88),
    }
    for path, (size, fraction) in targets.items():
        icon = on_field(place(mark, size, fraction), BG)
        icon.save(path, "PNG", optimize=True)
        print(f"{path.relative_to(ROOT)}  {size}x{size}")


def write_splash_drawables(mark: Image.Image) -> None:
    for density, scale in DENSITIES.items():
        window = int(SPLASH_DP * scale)
        window_dir = RES_DIR / f"drawable-{density}"
        window_dir.mkdir(parents=True, exist_ok=True)
        place(mark, window, 0.92).save(
            window_dir / "launch_logo.png", "PNG", optimize=True
        )

        splashed = int(SPLASH_ANDROID12_DP * scale)
        v31_dir = RES_DIR / f"drawable-{density}-v31"
        v31_dir.mkdir(parents=True, exist_ok=True)
        place(mark, splashed, 2 / 3).save(
            v31_dir / "launch_logo.png", "PNG", optimize=True
        )
        print(
            f"android/app/src/main/res/drawable-{density}/launch_logo.png  {window}px  "
            f"drawable-{density}-v31/launch_logo.png  {splashed}px"
        )


def main() -> None:
    if not MASTER.exists():
        raise SystemExit(f"missing master artwork: {MASTER}")
    mark = extract_mark(Image.open(MASTER).convert("RGB"))
    print(f"mark crop {mark.size[0]}x{mark.size[1]}")
    write_launcher_sources(mark)
    write_web_icons(mark)
    write_splash_drawables(mark)


if __name__ == "__main__":
    main()
