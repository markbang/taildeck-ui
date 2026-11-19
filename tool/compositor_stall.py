#!/usr/bin/env python3
"""Reads `adb logcat -d` on stdin and tells whether an ANR of <app> was the
emulator's compositor stalling rather than the app.

Both must hold: a frame of another process (system UI, the launcher) stuck for
3 s or more across the 5 s the input dispatcher waited on the app, and the app
absent from the CPU list of the ANR report. Prints one line with both
processes' numbers either way; exits 0 for a stall, 1 for an app-only ANR.
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
cpu_start_re = re.compile(r"ActivityManager: CPU usage from .* ago")
cpu_row_re = re.compile(r"ActivityManager:\s+([\d.]+)% (\d+)/(\S+?):")

app_pids = set()
names = {}
anr_at = None
stalls = []  # (start_ms, end_ms, pid, what)
cpu_rows = None  # rows of the ANR report's CPU list before the ANR
in_cpu = False
for raw in sys.stdin:
    raw = raw.rstrip("\r\n")
    m = line_re.match(raw)
    if not m:
        continue
    h, mi, s, ms, pid, text = m.groups()
    t = ((int(h) * 60 + int(mi)) * 60 + int(s)) * 1000 + int(ms)
    p = proc_re.search(text)
    if p:
        app_pids.add(p.group(1))
    if anr_at is None and anr_re.search(text):
        anr_at = t
    if cpu_rows is None and anr_at is not None and cpu_start_re.search(text):
        cpu_rows, in_cpu = [], True
        continue
    r = cpu_row_re.search(text)
    if r:
        names.setdefault(r.group(2), r.group(3))
    if in_cpu:
        if "TOTAL" in text or not r:
            in_cpu = False
        else:
            cpu_rows.append((float(r.group(1)), r.group(2), r.group(3)))
    d = davey_re.search(text)
    k = skipped_re.search(text)
    if d:
        stuck, what = int(d.group(1)), f"Davey {d.group(1)} ms"
    elif k:
        stuck, what = int(int(k.group(1)) * VSYNC_MS), f"Skipped {k.group(1)} frames"
    else:
        continue
    if stuck >= STUCK_MS:
        stalls.append((t - stuck, t, pid, what))


def overlaps(start, end):
    return start <= anr_at and end >= anr_at - WAIT_MS


if anr_at is None:
    print(f"app-only ANR: no ANR of {app} in the log")
    sys.exit(1)
ours = [x for x in stalls if x[2] in app_pids and overlaps(x[0], x[1])]
other = [x for x in stalls if x[2] not in app_pids and overlaps(x[0], x[1])]
app_froze = (
    f"app pid {ours[0][2]} froze {ours[0][1] - ours[0][0]} ms ({ours[0][3]})"
    if ours else "app: no frozen-frame line"
)
if cpu_rows is None:
    cpu = None
    cpu_text = "the ANR report has no CPU list from before the ANR"
else:
    cpu = [r for r in cpu_rows if r[1] in app_pids or r[2] == app]
    top = ", ".join(
        f"{'composer3' if 'composer' in n else n.split('.')[-1]} {c:g}%"
        for c, _, n in cpu_rows[:2]
    )
    cpu_text = (
        f"app at {cpu[0][0]:g}% in the ANR CPU top ({top})" if cpu
        else f"app absent from the ANR CPU top ({top})"
    )
if other:
    start, end, pid, what = max(other, key=lambda x: x[1] - x[0])
    other_text = f"{names.get(pid, 'a process')} (pid {pid}) froze {end - start} ms ({what})"
else:
    other_text = "no other process froze ≥ 3 s"
if other and cpu == []:
    print(f"compositor stall: {other_text}; {app_froze}; {cpu_text}")
    sys.exit(0)
print(f"app-only ANR: {other_text}; {app_froze}; {cpu_text}")
sys.exit(1)
