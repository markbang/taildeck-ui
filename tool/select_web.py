#!/usr/bin/env python3
"""Records a select closing in the web build, one clip per flow and build.

The emulator's software encoder drops most frames of these animations, so the
frame-by-frame evidence comes from the same build served to Chromium here: the
clip holds every frame of the menu returning into the value.

Usage: select_web.py <after-url> <before-url> [out-dir]
Writes <build>-language-close.webm, <build>-ssh-close.webm and their stills.
"""
import pathlib
import sys
from urllib.parse import urljoin

from playwright.sync_api import sync_playwright

WIDTH, HEIGHT = 414, 896
LANGUAGE_VALUE = (345, 542)
OUTSIDE = (52, 90)
SSH_VALUE = (300, 762)
SSH_OUTSIDE = (207, 60)
SLOW = 4

# Where the value and the menu above it sit in each flow, for the frame check.
LANGUAGE_BOX = "270,506,130,66"
SSH_BOX = "240,730,150,66"


def record(out: pathlib.Path, base: str, build: str) -> None:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            args=["--no-sandbox", "--enable-unsafe-swiftshader"]
        )
        for name, query, value, outside in (
            ("language", "?preview=1&tab=3&lang=en&slow=%d" % SLOW,
             LANGUAGE_VALUE, OUTSIDE),
            ("ssh", "?preview=1&tab=0&lang=en&sheet=ssh&splash=0&slow=%d" % SLOW,
             SSH_VALUE, SSH_OUTSIDE),
        ):
            context = browser.new_context(
                viewport={"width": WIDTH, "height": HEIGHT},
                has_touch=True,
                record_video_dir=str(out / "raw"),
                record_video_size={"width": WIDTH, "height": HEIGHT},
            )
            page = context.new_page()
            page.goto(urljoin(base, query))
            page.wait_for_timeout(6000)
            page.touchscreen.tap(*value)
            page.wait_for_timeout(SLOW * 700)
            page.screenshot(path=str(out / f"{build}-{name}-open.png"))
            page.touchscreen.tap(*outside)
            page.wait_for_timeout(SLOW * 900)
            page.screenshot(path=str(out / f"{build}-{name}-closed.png"))
            video = page.video
            context.close()
            pathlib.Path(video.path()).rename(out / f"{build}-{name}-close.webm")


def main() -> int:
    after = sys.argv[1]
    before = sys.argv[2]
    out = pathlib.Path(sys.argv[3] if len(sys.argv) > 3 else "select")
    (out / "raw").mkdir(parents=True, exist_ok=True)
    record(out, after, "after")
    record(out, before, "before")
    print(f"clips in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
