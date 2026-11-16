#!/usr/bin/env python3
"""Measures a popup menu's row pitch from a uiautomator dump.

The menu's own card is not a node, so the rows are read off their labels: two
labels a known number of rows apart give the pitch in pixels, which the
density turns into the dp FlClash's popup uses.

Usage: menu_metrics.py <dump.xml> <top-label> <top-rows> <bottom-label> <density>
Prints "rows <px> dp <dp> <top> <bottom> <x1> <y1> <x2> <y2>".
"""
import subprocess
import sys


def boxes(path, needle):
    out = subprocess.run(
        [sys.executable, str(__file__).replace('menu_metrics.py', 'ui.py'),
         path, 'all', needle],
        capture_output=True, text=True,
    )
    rows = []
    for line in out.stdout.splitlines():
        *box, = (int(value) for value in line.split())
        rows.append(tuple(box))
    return rows


def main() -> int:
    path, top, rows, bottom, density = sys.argv[1:6]
    span = int(rows)
    top_boxes = boxes(path, top)
    bottom_boxes = boxes(path, bottom)
    if not top_boxes or not bottom_boxes:
        print(f"no bounds for {top!r} or {bottom!r}", file=sys.stderr)
        return 1
    # The menu's copy is the one below the row's value, when both are on screen.
    upper = top_boxes[0]
    lower = max(bottom_boxes, key=lambda box: box[1])
    pitch = (lower[1] - upper[1]) / span
    dp = pitch * 160 / float(density)
    print(f"rows {pitch:.1f} dp {dp:.1f} {top} {lower[1]} "
          f"text {upper[0]},{upper[1]},{upper[2]},{upper[3]}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
