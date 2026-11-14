#!/usr/bin/env python3
"""Finds a uiautomator node by text and prints its tap point.

Usage: ui.py dump.xml tap <needle>   -> prints "x y" for the smallest match
       ui.py dump.xml has <needle>   -> exit 0 when a match exists
       ui.py dump.xml edits         -> prints every text-field point, top first
       ui.py dump.xml edit <index>  -> prints "x y" for one of those fields
"""
import re
import sys
import xml.etree.ElementTree as ET

BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def bounds(node):
    box = BOUNDS.match(node.get("bounds") or "")
    if not box:
        return None
    x1, y1, x2, y2 = (int(value) for value in box.groups())
    if x2 - x1 <= 0 or y2 - y1 <= 0:
        return None
    return (x1, y1, x2, y2)


def center(box):
    x1, y1, x2, y2 = box
    return (x1 + x2) // 2, (y1 + y2) // 2


def matches(path, needle):
    root = ET.parse(path).getroot()
    wanted = needle.lower()
    found = []
    for node in root.iter("node"):
        label = f"{node.get('text') or ''} {node.get('content-desc') or ''}".strip()
        if wanted not in label.lower():
            continue
        box = bounds(node)
        if box is None:
            continue
        x1, y1, x2, y2 = box
        found.append(((x2 - x1) * (y2 - y1), center(box)))
    return [point for _, point in sorted(found)]


def edits(path):
    """Text fields carry no label of their own, so they are found by class."""
    root = ET.parse(path).getroot()
    fields = []
    for node in root.iter("node"):
        if node.get("class") != "android.widget.EditText":
            continue
        box = bounds(node)
        if box is None:
            continue
        fields.append((box[1], center(box)))
    return [point for _, point in sorted(fields)]


def main():
    path, command = sys.argv[1:3]
    if command == "edits":
        for x, y in edits(path):
            print(x, y)
        return 0
    if command == "edit":
        fields = edits(path)
        index = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        if index >= len(fields):
            print(f"no text field {index} of {len(fields)}", file=sys.stderr)
            return 1
        print(*fields[index])
        return 0
    needle = sys.argv[3]
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
