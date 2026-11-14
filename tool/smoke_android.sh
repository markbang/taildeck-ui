#!/usr/bin/env bash
# Cold-start smoke test for a release APK on a running emulator: fresh install,
# launch, wait, then fail on a dead process or an AndroidRuntime crash.
# Usage: tool/smoke_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/smoke_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke}
wait_s=${WAIT_SECONDS:-15}
mkdir -p "$out"

fail() {
  echo "FAIL: $*" | tee -a "$out/summary.txt"
  exit 1
}

adb wait-for-device
adb shell getprop ro.build.version.release > "$out/device.txt"
adb shell getprop ro.product.cpu.abi >> "$out/device.txt"

# A fresh install must not inherit state from an earlier copy.
adb uninstall "$app" > /dev/null 2>&1 || true
# -g grants runtime permissions so a system dialog cannot hide the app screen.
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"

activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

adb logcat -c
adb shell am start -W -n "$activity" > "$out/launch.txt" 2>&1 || fail "am start failed, see launch.txt"
sleep "$wait_s"

adb logcat -d > "$out/logcat.txt" 2>&1 || true
adb logcat -b crash -d > "$out/logcat-crash.txt" 2>&1 || true
adb exec-out screencap -p > "$out/screenshot.png" || true
pid=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
focus=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r' || true)

{
  echo "apk: $apk"
  echo "application id: $app"
  echo "launcher activity: $activity"
  echo "pid after ${wait_s}s: ${pid:-<none>}"
  echo "focus: ${focus:-<none>}"
} | tee "$out/summary.txt"

[ -n "$pid" ] || fail "process $app is gone; the app died within ${wait_s}s of launch"

# The crash buffer keeps the last crash only; scan both buffers for this launch.
crash=$(grep -hE 'FATAL EXCEPTION|Fatal signal|AndroidRuntime.*Process: ' \
  "$out/logcat.txt" "$out/logcat-crash.txt" 2>/dev/null | head -n 5 || true)
if [ -n "$crash" ]; then
  printf '%s\n' "$crash" | tee -a "$out/summary.txt"
  fail "crash in logcat"
fi

anr=$(grep -hE "ANR in $app" "$out/logcat.txt" 2>/dev/null | head -n 3 || true)
if [ -n "$anr" ]; then
  printf '%s\n' "$anr" | tee -a "$out/summary.txt"
  fail "ANR in $app"
fi

echo "ok: $app alive after ${wait_s}s with no crash" | tee -a "$out/summary.txt"
