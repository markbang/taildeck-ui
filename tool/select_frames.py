#!/usr/bin/env python3
"""Cuts every frame of a select-close clip and measures the value's box.

The box is given in screen pixels (x,y,w,h). Each frame's grey pixels in that
box are compared against the clip's last frame, so the menu, the drop returning
into the value and anything left behind show up as a difference. The last run
of differing frames is the close: the clip then ends on the settled row.

Usage: select_frames.py <clip.mp4> <out-dir> <x,y,w,h> [--name label]
                        [--quiet 1.5] [--late 6.0]

Writes frames/, close/ (the close's frames, timestamps burnt in),
close-frames.png (their contact sheet) and close-diff.txt (one line per frame)
into <out-dir>. Exits 1 when the close still differs by more than --late in its
last frames, which is what a block left at the value's place measures.
"""
import argparse
import pathlib
import shutil
import subprocess
import sys


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("clip")
    parser.add_argument("out")
    parser.add_argument("box")
    parser.add_argument("--name", default="select")
    parser.add_argument("--quiet", type=float, default=1.5)
    parser.add_argument("--late", type=float, default=6.0)
    args = parser.parse_args()

    x, y, w, h = (int(value) for value in args.box.split(","))
    out = pathlib.Path(args.out)
    frames = out / "frames"
    crops = out / "crops"
    close = out / "close"
    frames.mkdir(parents=True, exist_ok=True)
    crops.mkdir(parents=True, exist_ok=True)
    if close.exists():
        shutil.rmtree(close)
    close.mkdir()

    # Every frame as it came, and the value's corner of it with the frame's
    # time burnt in for the contact sheet.
    run([
        "ffmpeg", "-loglevel", "error", "-y", "-i", args.clip, "-vsync", "0",
        str(frames / "%06d.png"),
    ])
    crop_x, crop_y = max(0, x - 40), max(0, y - 70)
    crop_w, crop_h = w + 80, h + 140
    run([
        "ffmpeg", "-loglevel", "error", "-y", "-i", args.clip, "-vsync", "0",
        "-vf", f"crop={crop_w}:{crop_h}:{crop_x}:{crop_y},"
               "drawtext=text='%{pts\\:hms}':x=8:y=8:fontsize=22:"
               "fontcolor=white:box=1:boxcolor=black@0.65",
        str(crops / "%06d.png"),
    ])
    raw = out / "box.raw"
    run([
        "ffmpeg", "-loglevel", "error", "-y", "-i", args.clip, "-vsync", "0",
        "-vf", f"crop={w}:{h}:{x}:{y},format=gray",
        "-f", "rawvideo", "-pix_fmt", "gray", str(raw),
    ])
    data = raw.read_bytes()
    raw.unlink()
    size = w * h
    boxes = [data[i:i + size] for i in range(0, len(data) - size + 1, size)]
    times = [
        float(value)
        for value in subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "frame=pts_time", "-of", "csv=p=0", args.clip],
            capture_output=True, text=True, check=True,
        ).stdout.replace(",", " ").split()
    ]
    while len(times) < len(boxes):
        times.append(times[-1] if times else 0.0)

    settled = boxes[-1]
    diffs = [
        sum(abs(a - b) for a, b in zip(box, settled)) / size for box in boxes
    ]

    # The close is the last run of frames that differ from the settled row.
    dirty = [index for index, diff in enumerate(diffs) if diff > args.quiet]
    if not dirty:
        print(f"{args.name}: no close found in {args.clip}")
        return 1
    last = dirty[-1]
    first = last
    while first - 1 >= 0 and diffs[first - 1] > args.quiet / 3:
        first -= 1
    window = range(max(0, first - 3), min(len(boxes), last + 4))

    digits = 6
    for index in window:
        source = crops / f"{index + 1:0{digits}d}.png"
        if source.exists():
            shutil.copy(source, close / source.name)
    sheet = out / "close-frames.png"
    files = sorted(str(path) for path in close.glob("*.png"))
    run(["montage", *files, "-tile", "8x", "-geometry", "230x+2+2",
         "-background", "#222", str(sheet)])

    with (out / "close-diff.txt").open("w") as handle:
        handle.write(f"{args.name}: {args.clip}, box {x},{y},{w},{h}\n")
        for index in window:
            mark = "*" if diffs[index] > args.quiet else " "
            handle.write(f"{mark} frame {index + 1:4d} {times[index]:7.3f}s "
                         f"{diffs[index]:6.2f}\n")

    late = max(diffs[max(first, last - 4):last + 1])
    print(f"{args.name}: close frames {first + 1}-{last + 1} of {len(boxes)}, "
          f"last-frames worst {late:.2f} (limit {args.late})")
    print(f"sheet {sheet}, table {out / 'close-diff.txt'}")
    return 1 if late > args.late else 0


if __name__ == "__main__":
    sys.exit(main())
