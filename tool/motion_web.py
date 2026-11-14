#!/usr/bin/env python3
"""Records the motion of the web build with Playwright, one clip per effect.

The Android emulator renders with SwiftShader and its encoder drops most of the
frames an animation has, so the clips that need real motion come from the web
build instead; the Kotlin comparison clips still come from
`tool/motion_record.sh` on the emulator.

Usage: python3 tool/motion_web.py [base-url] [out-dir]
"""
import pathlib
import sys

from playwright.sync_api import sync_playwright

DOCK = {"nodes": (78, 847), "services": (163, 847), "agents": (250, 847)}
BACK = (38, 108)
CONTROL_SERVER = (207, 605)
CONTINUE_IN_BROWSER = (207, 460)

# Each clip waits for the app to boot, then plays its gestures with the pauses
# the UI needs to settle; the recorded video starts at page load.
CLIPS = [
    ("flutter-tabs", "?preview=1&tab=0&lang=en", [
        (DOCK["services"], 1600),
        (DOCK["agents"], 1600),
        (DOCK["nodes"], 1400),
    ]),
    ("flutter-detail", "?preview=1&tab=0&lang=en", [
        ((200, 748), 2400),
        (BACK, 1800),
    ]),
    ("flutter-login-expand", "?login=1&lang=en", [
        (CONTROL_SERVER, 2200),
    ]),
    ("flutter-start", "?login=1&lang=en", [
        (CONTINUE_IN_BROWSER, 3000),
    ]),
]


def record(out: pathlib.Path, base: str, name: str, query: str, steps) -> None:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            args=["--no-sandbox", "--enable-unsafe-swiftshader"]
        )
        context = browser.new_context(
            viewport={"width": 414, "height": 896},
            record_video_dir=str(out),
            record_video_size={"width": 414, "height": 896},
        )
        page = context.new_page()
        page.goto(base + query)
        page.wait_for_timeout(5000)
        for point, wait in steps:
            page.mouse.click(*point)
            page.wait_for_timeout(wait)
        video = page.video
        context.close()
        pathlib.Path(video.path()).rename(out / f"{name}.webm")
        browser.close()
        print(f"{name}.webm")


def main() -> None:
    base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8099/taildeck-ui/"
    out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "motion")
    out.mkdir(parents=True, exist_ok=True)
    for name, query, steps in CLIPS:
        record(out, base, name, query, steps)


if __name__ == "__main__":
    main()
