#!/usr/bin/env python3
"""Finds a uiautomator node by text and prints a tap point.

Usage: ui.py dump.xml tap <needle>          -> "x y", the smallest match
       ui.py dump.xml has <needle>          -> exit 0 when a match exists
       ui.py dump.xml below <needle> <dy>   -> "x y", dy past the widest match
       ui.py dump.xml above <needle> <dy>   -> "x y", dy before it

The below/above forms reach a field that has no text of its own, such as the
text field under a section button.
"""
import re
import sys
import xml.etree.ElementTree as ET

BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def boxes(path, needle):
    root = ET.parse(path).getroot()
    wanted = needle.lower()
    found = []
    for node in root.iter("node"):
        label = f"{node.get('text') or ''} {node.get('content-desc') or ''}".strip()
        if wanted not in label.lower():
            continue
        box = BOUNDS.match(node.get("bounds") or "")
        if not box:
            continue
        x1, y1, x2, y2 = (int(value) for value in box.groups())
        if x2 - x1 <= 0 or y2 - y1 <= 0:
            continue
        found.append((x1, y1, x2, y2))
    return sorted(found, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))


def matches(path, needle):
    return [((x1 + x2) // 2, (y1 + y2) // 2) for x1, y1, x2, y2 in boxes(path, needle)]


def main():
    path, command, needle = sys.argv[1:4]
    if command in ("below", "above"):
        delta = int(sys.argv[4])
        found = boxes(path, needle)
        if not found:
            print(f"no node matches {needle!r}", file=sys.stderr)
            return 1
        # The widest match is the row or section the field sits under.
        x1, y1, x2, y2 = max(found, key=lambda b: b[2] - b[0])
        y = y1 - delta if command == "above" else y2 + delta
        print((x1 + x2) // 2, y)
        return 0
    points = matches(path, needle)
    if command == "has":
        return 0 if points else 1
    if not points:
        print(f"no node matches {needle!r}", file=sys.stderr)
        return 1
    print(*points[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
