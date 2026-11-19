#!/usr/bin/env python3
"""Reads `adb logcat -d` on stdin and tells whether an ANR of <app> was the
emulator's compositor stalling rather than the app.

Usage: compositor_stall.py <app> [main-thread samples] [ANR trace] < logcat

Both must hold: a frame of another process (system UI, the launcher) stuck for
3 s or more across the 5 s the input dispatcher waited on the app, and the app
idle meanwhile. Idle is the app absent from the ANR report's CPU list from
before the ANR; a report without that list falls back to the gate's samples
of the app's main thread (back_android.sh watch_main): under 10% CPU, and no
wait on a file, or on a futex outside hwui, EGL or binder in the ANR trace.
Unreadable samples count as busy. Prints one line with both processes'
numbers, the CPU share and the wait channel; exits 0 for a stall, 1 for an
app-only ANR.
"""
import re
import sys

STUCK_MS = 3000
WAIT_MS = 5000
VSYNC_MS = 1000 / 60

IDLE_SHARE = 0.10
HZ = 100
app = sys.argv[1]
samples_path = sys.argv[2] if len(sys.argv) > 2 else None
trace_path = sys.argv[3] if len(sys.argv) > 3 else None
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


FILE_WAIT = re.compile(r"io_schedule|folio|page|filemap|ext4|f2fs|fuse|blk|jbd2|nfs|sync|fsync")
IDLE_WAIT = re.compile(r"ep_poll|epoll|poll_schedule|do_sys_poll|do_select")
GPU_OR_BINDER = re.compile(
    r"libhwui|RenderThread|DrawFrameTask|libEGL|libGLES|eglSwapBuffers|dequeueBuffer|"
    r"BLASTBufferQueue|SurfaceControl|libgui|binder|BinderProxy|IPCThreadState"
)


def read_samples(path):
    """[(uptime_s, state, ticks, wchan, syscall)] up to the ANR mark."""
    try:
        text = open(path).read()
    except OSError:
        return []
    out = []
    for block in text.split("--- ")[1:]:
        lines = block.strip("\n").split("\n")
        if lines[0].startswith("anr"):
            break
        try:
            uptime = float(lines[1].split()[0])
            fields = lines[2].rsplit(")", 1)[1].split()
            state, ticks = fields[0], int(fields[11]) + int(fields[12])
        except (IndexError, ValueError):
            continue
        wchan = lines[3].strip() if len(lines) > 3 else ""
        sys_nr = lines[4].split()[0] if len(lines) > 4 and lines[4].split() else ""
        out.append((uptime, state, ticks, wchan, sys_nr))
    return out


def wait_kind(state, wchan, sys_nr):
    if state == "D" or FILE_WAIT.search(wchan):
        return "file"
    if "binder" in wchan:
        return "binder"
    if "futex" in wchan or sys_nr == "202":
        return "futex"
    if IDLE_WAIT.search(wchan) or sys_nr in ("7", "232", "271", "281"):
        return "idle"
    if sys_nr in ("0", "17", "19", "295", "1", "18", "20", "74", "75"):
        return "file"
    if state == "R" or sys_nr == "running":
        return "running"
    return "unknown"


def main_trace_stack(path):
    """The app's "main" thread block of the ANR trace, or ''."""
    try:
        text = open(path).read()
    except (OSError, TypeError):
        return ""
    for part in text.split("----- pid ")[1:]:
        if f"Cmd line: {app}" not in part.split("\n", 3)[1]:
            continue
        m = re.search(r'^"main".*?(?=^\s*$)', part, re.S | re.M)
        return m.group(0) if m else ""
    return ""


def main_thread():
    """(idle?, text) from the gate's samples and the ANR trace."""
    samples = read_samples(samples_path) if samples_path else []
    if len(samples) < 2 or samples[-1][0] - samples[0][0] < 1:
        return False, "main thread unreadable (app gone or no samples)"
    span = samples[-1][0] - samples[0][0]
    share = (samples[-1][2] - samples[0][2]) / HZ / span
    kinds = [wait_kind(st, w, n) for _, st, _, w, n in samples]
    last = samples[-1]
    waits = "/".join(sorted(set(kinds)))
    text = (
        f"main thread {share * 100:.0f}% CPU over {span:.1f} s, "
        f"state {last[1]}, wchan {last[3] or '?'}, syscall {last[4] or '?'} ({waits})"
    )
    if share >= IDLE_SHARE:
        return False, text + ", busy"
    if "file" in kinds:
        return False, text + ", waiting on a file"
    if "futex" in kinds and not GPU_OR_BINDER.search(main_trace_stack(trace_path)):
        return False, text + ", futex wait outside hwui/EGL/binder in the ANR trace"
    if "unknown" in kinds:
        return False, text + ", unknown wait"
    return True, text


if anr_at is None:
    print(f"app-only ANR: no ANR of {app} in the log")
    sys.exit(1)
ours = [x for x in stalls if x[2] in app_pids and overlaps(x[0], x[1])]
other = [x for x in stalls if x[2] not in app_pids and overlaps(x[0], x[1])]
app_froze = (
    f"app pid {ours[0][2]} froze {ours[0][1] - ours[0][0]} ms ({ours[0][3]})"
    if ours else "app: no frozen-frame line"
)
main_idle, main_text = main_thread()
if cpu_rows is None:
    cpu_idle = main_idle
    cpu_text = f"the ANR report has no CPU list from before the ANR; {main_text}"
else:
    cpu = [r for r in cpu_rows if r[1] in app_pids or r[2] == app]
    cpu_idle = not cpu
    top = ", ".join(
        f"{'composer3' if 'composer' in n else n.split('.')[-1]} {c:g}%"
        for c, _, n in cpu_rows[:2]
    )
    cpu_text = (
        f"app at {cpu[0][0]:g}% in the ANR CPU top ({top})" if cpu
        else f"app absent from the ANR CPU top ({top})"
    ) + f"; {main_text}"
if other:
    start, end, pid, what = max(other, key=lambda x: x[1] - x[0])
    other_text = f"{names.get(pid, 'a process')} (pid {pid}) froze {end - start} ms ({what})"
else:
    other_text = "no other process froze ≥ 3 s"
if other and cpu_idle:
    print(f"compositor stall: {other_text}; {app_froze}; {cpu_text}")
    sys.exit(0)
print(f"app-only ANR: {other_text}; {app_froze}; {cpu_text}")
sys.exit(1)
