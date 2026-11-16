#!/usr/bin/env python3
"""Fails when the herdr error card paints before the Agents page woke herdr.

Inputs are the raw gray 48x48 frames of the tab-switch clip (ffmpeg:
fps=12,scale=48:48,format=gray) and the same encoding of a still taken after
the real failure of the wake, plus where in the clip the tap landed.

The failure card and the loading skeleton share the page header, so a frame
counts as the error only when both its grey layout and its ink match the
reference. Exit 1 when the card is painted inside the lead-in window after the
tap (a stale failure before the skeleton), 2 on unreadable input.
"""
import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from frame_check import edges, edge_mad, frames, grey_mad  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", required=True, help="raw gray frames of the clip")
    parser.add_argument(
        "--error", required=True, action="append",
        help="raw gray still of an error card; repeat for each failure the run shows",
    )
    parser.add_argument("--tap", type=float, default=0.8, help="seconds into the clip")
    parser.add_argument("--fps", type=float, default=12.0)
    parser.add_argument("--lead", type=int, default=12, help="frames the tap owns")
    parser.add_argument("--grey", type=float, default=3.0)
    parser.add_argument("--edge", type=float, default=1.5)
    args = parser.parse_args()

    run = frames(args.frames)
    if not run:
        print("no frames read", file=sys.stderr)
        return 2
    cards = []
    for path in args.error:
        reference = frames(path)
        if not reference:
            print(f"no frames read from {path}", file=sys.stderr)
            return 2
        cards.append((reference[0], edges(reference[0])))
    tap = int(math.floor(args.tap * args.fps))

    stale, seen = [], None
    for index, frame in enumerate(run):
        ink = edges(frame)
        pairs = [(grey_mad(frame, card), edge_mad(ink, card_edges)) for card, card_edges in cards]
        grey, edge = min(pairs)
        is_card = grey < args.grey and edge < args.edge
        if is_card and seen is None:
            seen = index
        if is_card and tap <= index < tap + args.lead:
            stale.append((index, grey, edge))
        if tap - 2 <= index < tap + args.lead + 6:
            print(f"frame {index} at {index / args.fps:.2f}s "
                  f"grey={grey:.1f} edge={edge:.2f} {'card' if is_card else 'other'}")

    if seen is not None:
        print(f"error card first seen at {seen / args.fps:.2f}s (tap {args.tap:.2f}s)")
    else:
        print("error card never seen: the clip does not carry the real failure")
    if stale:
        print(f"FAIL: the error card is painted {len(stale)} frame(s) after the tap:")
        for index, grey, edge in stale:
            print(f"  frame {index} at {index / args.fps:.2f}s "
                  f"(grey={grey:.1f} edge={edge:.2f})")
        return 1
    if seen is None or seen < tap + args.lead:
        print("FAIL: no settled error card after the tap; the wake never failed")
        return 1
    print(f"ok: no error card in the {args.lead / args.fps:.1f}s after the tap")
    return 0


if __name__ == "__main__":
    sys.exit(main())
