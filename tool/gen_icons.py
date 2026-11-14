#!/usr/bin/env python3
"""Render the launcher icon for the non-Android hosts.

The Android resources are the source of truth: the dot geometry and colours are
read from android/app/src/main/res (drawable/ic_launcher_fg.xml, values/colors.xml)
and laid out the way Android draws the adaptive icon, i.e. the 72dp visible
crop of the 108dp viewport. Run after changing those files.

  tool/gen_icons.py            # rewrite every icon asset
"""

import json
import os
import re
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android/app/src/main/res")
ANDROID = "{http://schemas.android.com/apk/res/android}"
SS = 4  # supersampling factor
SQUIRCLE = 0.2237  # macOS icon corner radius relative to its side


def colors() -> dict[str, str]:
    root = ET.parse(os.path.join(RES, "values/colors.xml")).getroot()
    return {c.get("name"): c.text.strip() for c in root.findall("color")}


def dots() -> list[tuple[float, float, float, str, float]]:
    root = ET.parse(os.path.join(RES, "drawable/ic_launcher_fg.xml")).getroot()
    out = []
    for path in root.findall("path"):
        data = path.get(ANDROID + "pathData").replace(" ", "")
        m = re.match(r"M([\d.]+),([\d.]+)m-([\d.]+),0", data)
        if not m:
            sys.exit(f"unexpected pathData: {path.get(ANDROID + 'pathData')}")
        fill = path.get(ANDROID + "fillColor").removeprefix("@color/")
        out.append((float(m[1]), float(m[2]), float(m[3]), fill,
                    float(path.get(ANDROID + "fillAlpha", 1))))
    return out


def rgba(hex_color: str, alpha: float) -> tuple[int, int, int, int]:
    h = hex_color.lstrip("#")[-6:]
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), round(alpha * 255))


def render(size: int, rounded: bool) -> Image.Image:
    c, d = colors(), dots()
    side = size * SS
    image = Image.new("RGBA", (side, side), rgba(c["ic_bg"], 1))
    unit = side / 72  # the 108dp viewport cropped to its 72dp visible area
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for cx, cy, r, name, alpha in d:
        x, y, rr = (cx - 18) * unit, (cy - 18) * unit, r * unit
        draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=rgba(c[name], alpha))
    image.alpha_composite(layer)
    if rounded:
        mask = Image.new("L", image.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, side - 1, side - 1], radius=round(side * SQUIRCLE), fill=255)
        image.putalpha(mask)
    return image.resize((size, size), Image.LANCZOS)


def save(image: Image.Image, path: str, opaque: bool = False) -> None:
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (image.convert("RGB") if opaque else image).save(path, optimize=True)


def main() -> int:
    ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    macos = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for name in sorted(os.listdir(os.path.join(ROOT, ios))):
        m = re.match(r"Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$", name)
        if m:
            save(render(round(float(m[1]) * int(m[2])), False), f"{ios}/{name}", opaque=True)
    for name in sorted(os.listdir(os.path.join(ROOT, macos))):
        m = re.match(r"app_icon_(\d+)\.png$", name)
        if m:
            save(render(int(m[1]), True), f"{macos}/{name}")
    ico = render(256, False)
    ico.save(os.path.join(ROOT, "windows/runner/resources/app_icon.ico"),
             sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    save(render(512, True), "linux/runner/resources/app_icon.png")
    save(render(32, False), "web/favicon.png")
    for size in (192, 512):
        save(render(size, False), f"web/icons/Icon-{size}.png")
        save(render(size, False), f"web/icons/Icon-maskable-{size}.png")
    print("icons written from", os.path.relpath(RES, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
