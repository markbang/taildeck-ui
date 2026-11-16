#!/usr/bin/env python3
"""Cuts every frame of a select-close clip and measures where its value was.

The box is given in screen pixels (x,y,w,h): the value and the space around it.
Each frame's grey pixels in that box are compared against the clip's last frame,
which is the settled row, so the menu, the drop returning into the value and
anything left behind all show up as a difference. A block left at the value is
lighter or darker than the row, so the frames just before the close settles must
not differ from the settled row's grey by more than --lift levels.

Usage: select_frames.py <clip.mp4> <out-dir> <x,y,w,h> [--name label]
                        [--quiet 1.5] [--lift 0.8]

Writes frames/, close/ (the close's frames, timestamps burnt in),
close-frames.png (their contact sheet), close-diff.txt (one line per frame) and
close-window.txt (start, end, fps) into <out-dir>. Exits 1 when the close's
last frames still carry a block.
"""
import argparse
import pathlib
import shutil
import subprocess
import sys


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def probe(clip: str, entries: str) -> str:
    return subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", entries, "-of", "csv=p=0", clip],
        capture_output=True, text=True, check=True,
    ).stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("clip")
    parser.add_argument("out")
    parser.add_argument("box")
    parser.add_argument("--name", default="select")
    parser.add_argument("--quiet", type=float, default=1.5)
    parser.add_argument("--lift", type=float, default=0.8)
    args = parser.parse_args()

    x, y, w, h = (int(value) for value in args.box.split(","))
    out = pathlib.Path(args.out)
    frames, crops, close = out / "frames", out / "crops", out / "close"
    for path in (frames, crops):
        path.mkdir(parents=True, exist_ok=True)
    if close.exists():
        shutil.rmtree(close)
    close.mkdir()

    run(["ffmpeg", "-loglevel", "error", "-y", "-i", args.clip, "-vsync", "0",
         str(frames / "%06d.png")])
    crop_x, crop_y = max(0, x - 40), max(0, y - 70)
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", args.clip, "-vsync", "0",
         "-vf", f"crop={w + 80}:{h + 140}:{crop_x}:{crop_y},"
                "drawtext=text='%{pts\\:hms}':x=8:y=8:fontsize=22:"
                "fontcolor=white:box=1:boxcolor=black@0.65",
         str(crops / "%06d.png")])

    raw = out / "box.raw"
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", args.clip, "-vsync", "0",
         "-vf", f"crop={w}:{h}:{x}:{y},format=gray",
         "-f", "rawvideo", "-pix_fmt", "gray", str(raw)])
    data = raw.read_bytes()
    raw.unlink()
    size = w * h
    boxes = [data[i:i + size] for i in range(0, len(data) - size + 1, size)]

    # Playwright's clips carry no per-frame timestamps, so the frames are laid
    # out at the clip's average rate.
    duration = float(probe(args.clip, "format=duration").strip() or 0)
    fps = len(boxes) / duration if duration > 0 and boxes else 25.0
    times = [index / fps for index in range(len(boxes))]

    settled = boxes[-1]
    settled_mean = sum(settled) / size
    diffs = [
        sum(abs(a - b) for a, b in zip(box, settled)) / size for box in boxes
    ]
    means = [sum(box) / size for box in boxes]

    dirty = [index for index, diff in enumerate(diffs) if diff > args.quiet]
    if not dirty:
        print(f"{args.name}: no close found in {args.clip}")
        return 1
    last = dirty[-1]
    first = last
    while first - 1 >= 0 and diffs[first - 1] > args.quiet / 3:
        first -= 1
    window = range(max(0, first - 3), min(len(boxes), last + 4))

    for index in window:
        source = crops / f"{index + 1:06d}.png"
        if source.exists():
            shutil.copy(source, close / source.name)
    sheet = out / "close-frames.png"
    files = sorted(str(path) for path in close.glob("*.png"))
    run(["montage", *files, "-tile", "8x", "-geometry", "230x+2+2",
         "-background", "#222", str(sheet)])

    with (out / "close-diff.txt").open("w") as handle:
        handle.write(f"{args.name}: {args.clip}, box {x},{y},{w},{h}, "
                     f"settled mean {settled_mean:.1f}\n")
        for index in window:
            mark = "*" if diffs[index] > args.quiet else " "
            handle.write(f"{mark} frame {index + 1:4d} {times[index]:7.3f}s "
                         f"diff {diffs[index]:6.2f} "
                         f"mean {means[index]:6.2f}\n")
    (out / "close-window.txt").write_text(
        f"{times[first]:.3f} {times[last]:.3f} {fps:.3f}\n")

    lift = max(abs(means[index] - settled_mean) for index in dirty[-6:])
    print(f"{args.name}: close {times[first]:.2f}-{times[last]:.2f}s of "
          f"{times[-1]:.2f}s, last frames differ by {lift:.2f} "
          f"(limit {args.lift})")
    print(f"sheet {sheet}, table {out / 'close-diff.txt'}")
    return 1 if lift > args.lift else 0


if __name__ == "__main__":
    sys.exit(main())
