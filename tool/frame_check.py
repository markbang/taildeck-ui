#!/usr/bin/env python3
"""Flags cold-start frames that show the login page.

Inputs are raw gray 48x48 frames (ffmpeg: fps=8,scale=48:48,format=gray) of a
run, plus the same encoding of a login reference and a home reference.

Two independent signatures must both match the login page: the grey layout
(its card and text rows) and the edge energy per 8x8 cell (where that ink
sits). The launch screen is as dark as the login page but carries ink only at
its centre, and the shell always differs in both.

Usage: frame_check.py --login login.raw --home home.raw --frames run.raw
Exits 1 when a frame is the login page, 2 when the input is unreadable.
"""
import argparse
import statistics
import sys

SIDE = 48
CELL = 8
SIZE = SIDE * SIDE


def frames(path):
    with open(path, "rb") as handle:
        data = handle.read()
    return [data[i:i + SIZE] for i in range(0, len(data) - SIZE + 1, SIZE)]


def grey_mad(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / SIZE


def edges(frame):
    values = list(frame)
    cells = []
    for top in range(0, SIDE, CELL):
        for left in range(0, SIDE, CELL):
            total = count = 0
            for y in range(top, min(top + CELL, SIDE - 1)):
                for x in range(left, min(left + CELL, SIDE - 1)):
                    at = y * SIDE + x
                    total += abs(values[at + 1] - values[at])
                    total += abs(values[at + SIDE] - values[at])
                    count += 1
            cells.append(total / max(count, 1))
    return cells


def edge_mad(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--login", required=True)
    parser.add_argument("--home", required=True)
    parser.add_argument("--frames", required=True)
    parser.add_argument("--grey", type=float, default=3.0)
    parser.add_argument("--edge", type=float, default=1.5)
    args = parser.parse_args()

    login = frames(args.login)[0]
    home = frames(args.home)[0]
    login_edges = edges(login)
    run = frames(args.frames)
    if not run:
        print("no frames read", file=sys.stderr)
        return 2

    scored = []
    flagged = []
    for index, frame in enumerate(run):
        grey = grey_mad(frame, login)
        edge = edge_mad(edges(frame), login_edges)
        scored.append((grey, edge, index))
        if grey < args.grey and edge < args.edge:
            flagged.append((index, grey, edge, grey_mad(frame, home)))

    grey_best, edge_best, at = min(scored)
    print(
        f"frames={len(run)} closest={at} grey={grey_best:.1f} edge={edge_best:.2f} "
        f"median_grey={statistics.median(s[0] for s in scored):.1f}"
    )
    for index, grey, edge, to_home in flagged:
        print(f"login-like frame {index} at {index / 8:.2f}s "
              f"(grey={grey:.1f} edge={edge:.2f} to_home={to_home:.1f})")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
