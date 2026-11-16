#!/usr/bin/env python3
"""Fails when the herdr error card paints before the Agents page woke herdr.

Inputs are the raw gray 48x48 frames of a screencap series (ffmpeg:
scale=48:48,format=gray over frames/frame-*.png), the capture time of each
frame, when the tab was tapped, and one raw still per error card the run can
show (the failure left by an earlier dial and the one the visit's own dial
makes). A frame counts as a card only when both its grey layout and its ink
match a reference, so the loading skeleton never passes for one.

Exit 1 when a card is painted inside the lead-in window the tap owns (a stale
failure before the skeleton) or when no card appears after it (the wake never
failed), 2 on unreadable input.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from frame_check import edges, edge_mad, frames, grey_mad  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", required=True, help="raw gray frames of the series")
    parser.add_argument("--times", required=True, help="epoch ms per frame, one per line")
    parser.add_argument("--tap", required=True, type=int, help="epoch ms of the tap")
    parser.add_argument(
        "--error", required=True, action="append",
        help="raw gray still of an error card; repeat for each card the run shows",
    )
    parser.add_argument("--lead", type=int, default=3000, help="ms the tap owns")
    parser.add_argument(
        "--stills-only", action="store_true",
        help="only check the cards the stills carry; a run whose screencaps "
             "were too slow to cover the lead-in is reported, not failed",
    )
    # The loading skeleton sits in the same place as the card and shares its
    # title, so the card has to match tightly: the same card scores ~0.3, the
    # skeleton ~3.0.
    parser.add_argument("--grey", type=float, default=1.5)
    parser.add_argument("--edge", type=float, default=1.5)
    args = parser.parse_args()

    run = frames(args.frames)
    times = [int(line) for line in Path(args.times).read_text().split()]
    if not run or len(times) != len(run):
        print(f"read {len(run)} frames and {len(times)} times", file=sys.stderr)
        return 2
    cards = []
    for path in args.error:
        reference = frames(path)
        if not reference:
            print(f"no frames read from {path}", file=sys.stderr)
            return 2
        cards.append((reference[0], edges(reference[0])))

    stale, seen = [], None
    for index, frame in enumerate(run):
        at = times[index] - args.tap
        ink = edges(frame)
        grey, edge = min(
            (grey_mad(frame, card), edge_mad(ink, card_edges))
            for card, card_edges in cards
        )
        is_card = grey < args.grey and edge < args.edge
        if is_card and seen is None:
            seen = at
        if is_card and 0 <= at < args.lead:
            stale.append((at, grey, edge))
        if -1000 <= at < args.lead + 2000:
            print(f"frame {index} at {at} ms grey={grey:.1f} edge={edge:.2f} "
                  f"{'card' if is_card else 'other'}")

    inside = sum(1 for at in times if 0 <= at - args.tap < args.lead)
    if args.stills_only:
        if stale:
            print(f"FAIL: the card is painted {len(stale)} time(s) inside the "
                  f"{args.lead} ms the tap owns:")
            for at, grey, edge in stale:
                print(f"  at {at} ms (grey={grey:.1f} edge={edge:.2f})")
            return 1
        print(f"ok: {inside} still(s) inside the {args.lead} ms after the tap, "
              f"none of them a card")
        return 0
    if seen is None:
        print("no error card after the tap: the wake never failed")
        return 1
    print(f"error card first seen {seen} ms after the tap")
    if stale:
        print(f"FAIL: the card is painted {len(stale)} time(s) inside the "
              f"{args.lead} ms the tap owns:")
        for at, grey, edge in stale:
            print(f"  at {at} ms (grey={grey:.1f} edge={edge:.2f})")
        return 1
    if seen < args.lead:
        print(f"FAIL: the card at {seen} ms is inside the {args.lead} ms lead-in")
        return 1
    print(f"ok: no card in the {args.lead} ms after the tap")
    return 0


if __name__ == "__main__":
    sys.exit(main())
