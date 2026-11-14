#!/usr/bin/env python3
"""Compare the launcher icon resources of two APKs.

Usage: tool/compare_apk_icons.py <apk-a> <apk-b>

Dumps mipmap/ic_launcher, its adaptive-icon XML and the foreground vector with
aapt2, resolves colour references to their hex values and diffs the result.
Exits non-zero when anything differs. aapt2 comes from $ANDROID_SDK_ROOT or
$ANDROID_HOME (newest build-tools).
"""

import glob
import os
import re
import subprocess
import sys
import tempfile


def aapt2() -> str:
    for root in (os.environ.get("ANDROID_SDK_ROOT"), os.environ.get("ANDROID_HOME")):
        if root:
            found = sorted(glob.glob(os.path.join(root, "build-tools", "*", "aapt2")))
            if found:
                return found[-1]
    sys.exit("aapt2 not found; set ANDROID_SDK_ROOT")


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def table(apk: str) -> tuple[dict[str, str], dict[str, str]]:
    """name -> file or colour value, and resource id -> name."""
    files: dict[str, str] = {}
    ids: dict[str, str] = {}
    current = None
    for line in run(aapt2(), "dump", "resources", apk).splitlines():
        m = re.match(r"\s+resource 0x([0-9a-f]+) ([\w/.-]+)$", line)
        if m:
            current = m.group(2)
            ids["0x" + m.group(1)] = current
            files[current] = ""
            continue
        if current is None:
            continue
        m = re.search(r"\(file\) (\S+)", line)
        if m:
            files[current] = m.group(1)
        elif m := re.match(r"\s+\(\) (#[0-9a-fA-F]{6,8})$", line):
            files[current] = m.group(1)
    return files, ids


def xmltree(apk: str, path: str, colors: dict[str, str], ids: dict[str, str]) -> list[str]:
    out = []
    for line in run(aapt2(), "dump", "xmltree", apk, "--file", path).splitlines():
        line = re.sub(r"\(line=\d+\)", "", line)
        line = re.sub(r"0x[0-9a-f]{8}", lambda m: ids.get(m.group(0), m.group(0)), line)
        out.append(re.sub(r"@0x[0-9a-f]{8}", lambda m: colors.get(ids.get(m.group(0)[1:], ""), m.group(0)), line))
    return out


def icon(apk: str) -> list[str]:
    files, ids = table(apk)
    colors = {n: v for n, v in files.items() if n.startswith("color/") and v.startswith("#")}
    lines = []
    for name in sorted(files):
        if name != "mipmap/ic_launcher" and not name.endswith("/ic_launcher_fg"):
            continue
        lines.append(f"# {name} -> {os.path.basename(files[name])}")
        lines += xmltree(apk, files[name], colors, ids)
    return lines


def badging(apk: str) -> str:
    prefix = ("package:", "application-label:", "application-icon-", "application:")
    return "\n".join(l for l in run(aapt2(), "dump", "badging", apk).splitlines() if l.startswith(prefix))


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    a, b = sys.argv[1], sys.argv[2]
    fa, fb = icon(a), icon(b)
    if not fa:
        sys.exit(f"no ic_launcher resources in {a}")
    if fa == fb:
        print(f"ic_launcher resources identical ({len(fa)} lines): {a} == {b}")
        print(badging(a))
        return 0
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for name, lines in (("a.txt", fa), ("b.txt", fb)):
            paths.append(os.path.join(tmp, name))
            with open(paths[-1], "w") as fh:
                fh.write("\n".join(lines) + "\n")
        diff = subprocess.run(["diff", "-u", *paths], capture_output=True, text=True)
        print(diff.stdout)
    return 1


if __name__ == "__main__":
    sys.exit(main())
