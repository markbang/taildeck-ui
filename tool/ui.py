#!/usr/bin/env python3
"""Finds a uiautomator node by text and prints its tap point.

Usage: ui.py dump.xml tap <needle>   -> prints "x y" for the smallest match
       ui.py dump.xml has <needle>   -> exit 0 when a match exists
"""
import re
import sys
import xml.etree.ElementTree as ET

BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def matches(path, needle):
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
        found.append(((x2 - x1) * (y2 - y1), (x1 + x2) // 2, (y1 + y2) // 2))
    return [point for _, *point in sorted(found)]


def main():
    path, command, needle = sys.argv[1:4]
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
