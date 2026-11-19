#!/usr/bin/env python3
"""Reads `adb logcat -d` on stdin and tells whether an ANR of <app> fell inside
a stall of the emulator's compositor rather than the app's own.

The stall freezes every window at once: a frame of another process (system UI,
the launcher) stuck for 3 s or more, overlapping the 5 s the input dispatcher
waited on the app, is that stall. Prints the evidence and exits 0 when found;
exits 1 when only the app froze (or no ANR is in the log).
"""
import re
import sys

STUCK_MS = 3000
WAIT_MS = 5000
VSYNC_MS = 1000 / 60

app = sys.argv[1]
line_re = re.compile(r"^\d\d-\d\d (\d\d):(\d\d):(\d\d)\.(\d{3})\s+(\d+)\s+\d+\s+\w\s+(.*)$")
davey_re = re.compile(r"Davey! duration=(\d+)ms")
skipped_re = re.compile(r"Skipped (\d+) frames!")
anr_re = re.compile(r"ANR in .*" + re.escape(app))
proc_re = re.compile(r"Start proc (\d+):" + re.escape(app) + r"/")

app_pids = set()
anr_at = None
stalls = []  # (start_ms, end_ms, pid, text)
for raw in sys.stdin:
    m = line_re.match(raw.rstrip("\r\n"))
    if not m:
        continue
    h, mi, s, ms, pid, text = m.groups()
    t = ((int(h) * 60 + int(mi)) * 60 + int(s)) * 1000 + int(ms)
    p = proc_re.search(text)
    if p:
        app_pids.add(p.group(1))
    if anr_at is None and anr_re.search(text):
        anr_at = t
    d = davey_re.search(text)
    k = skipped_re.search(text)
    stuck = int(d.group(1)) if d else int(int(k.group(1)) * VSYNC_MS) if k else 0
    if stuck >= STUCK_MS:
        stalls.append((t - stuck, t, pid, text.strip()[:120]))

if anr_at is None:
    sys.exit(1)
for start, end, pid, text in stalls:
    if pid in app_pids:
        continue
    if start <= anr_at and end >= anr_at - WAIT_MS:
        print(f"compositor stall: pid {pid} froze {end - start} ms across the ANR: {text}")
        sys.exit(0)
sys.exit(1)
