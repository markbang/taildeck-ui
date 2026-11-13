#!/usr/bin/env python3
"""Screenshot the web build at phone and desktop sizes.

Usage: python3 tool/shots.py [--base-url URL] [--out DIR]
"""

import argparse
import pathlib
import sys

from playwright.sync_api import sync_playwright

PAGES = [
    ("nodes-en", "?lang=en"),
    ("services", "?tab=1"),
    ("agents", "?tab=2"),
    ("settings", "?tab=3"),
    ("nodes-zh", "?lang=zh"),
]

VIEWPORTS = [(414, 896, "phone"), (1440, 900, "desktop")]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8099/taildeck-ui/")
    parser.add_argument("--out", default="shots")
    parser.add_argument("--wait-ms", type=int, default=4000)
    parser.add_argument("--executable", help="browser binary; defaults to the Playwright build")
    args = parser.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        # CI containers often run as root, where the sandbox is unavailable.
        browser = p.chromium.launch(executable_path=args.executable, args=["--no-sandbox"])
        for width, height, label in VIEWPORTS:
            page = browser.new_page(viewport={"width": width, "height": height})
            errors = []
            page.on("pageerror", lambda exc: errors.append(str(exc)))
            for name, query in PAGES:
                page.goto(f"{args.base_url}{query}", wait_until="load")
                page.wait_for_timeout(args.wait_ms)
                target = out / f"{name}-{label}-{width}x{height}.png"
                page.screenshot(path=str(target))
                print(f"{target} {target.stat().st_size} bytes")
            if errors:
                print("page errors:", *errors, sep="\n  ", file=sys.stderr)
            page.close()
        browser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
