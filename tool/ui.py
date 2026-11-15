#!/usr/bin/env python3
"""Finds a uiautomator node by text and prints its tap point.

Usage: ui.py dump.xml tap <needle>     -> prints "x y" for the smallest match
       ui.py dump.xml has <needle>     -> exit 0 when a match exists
       ui.py dump.xml text <needle>    -> prints the smallest match's label
       ui.py dump.xml bounds <needle>  -> prints "x1 y1 x2 y2"
       ui.py dump.xml texts <ymax>     -> every labelled node above ymax
       ui.py dump.xml edits            -> prints every text-field point, top first
       ui.py dump.xml edit <index>     -> prints "x y" for one of those fields
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
    """A label, exact match first: a caption that merely contains the words
    ("Works with ... control servers") must not win over the button."""
    root = ET.parse(path).getroot()
    wanted = needle.lower()
    exact, partial = [], []
    for node in root.iter("node"):
        labels = [
            value.lower()
            for value in (node.get("text") or "", node.get("content-desc") or "")
            if value
        ]
        if not any(wanted in label for label in labels):
            continue
        box = bounds(node)
        if box is None:
            continue
        x1, y1, x2, y2 = box
        entry = ((x2 - x1) * (y2 - y1), box, " ".join(labels).strip())
        if any(label == wanted for label in labels):
            exact.append(entry)
        else:
            partial.append(entry)
    return [entry[1:] for entry in sorted(exact) + sorted(partial)]


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


def texts(path, ymax):
    """Every labelled node above ymax: "text x1 y1 x2 y2", one per line."""
    root = ET.parse(path).getroot()
    for node in root.iter("node"):
        box = bounds(node)
        if box is None or center(box)[1] >= ymax:
            continue
        label = (node.get("text") or node.get("content-desc") or "").strip()
        if label:
            print(label.replace("\n", " "), *box)


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
    if command == "texts":
        texts(path, int(sys.argv[3]))
        return 0
    needle = sys.argv[3]
    found = matches(path, needle)
    if command == "has":
        return 0 if found else 1
    if not found:
        print(f"no node matches {needle!r}", file=sys.stderr)
        return 1
    box, label = found[0]
    if command == "text":
        print(label)
    elif command == "bounds":
        print(*box)
    else:
        print(*center(box))
    return 0


if __name__ == "__main__":
    sys.exit(main())
