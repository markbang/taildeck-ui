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

adb logcat -b all -c
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

# Only our process counts: unrelated system apps crash on this emulator (a TCG
# googlequicksearchbox SIGILL) and must not fail the gate while we are alive.
main_pid=${pid%% *}
adb logcat -d --pid="$main_pid" > "$out/logcat-app.txt" 2>&1 || true
adb logcat -b crash -d --pid="$main_pid" >> "$out/logcat-app.txt" 2>&1 || true
# --pid drops what the system logs for us under another pid: the stack-trace
# header and the native tombstone. Keep those too, a crash can also restart us.
grep -hE "Process: $app|pid: $main_pid\b|PID: $main_pid\b|>>> $app <<<|Cmdline: $app" \
  "$out/logcat.txt" "$out/logcat-crash.txt" 2>/dev/null >> "$out/logcat-app.txt" || true

crash=$(grep -hE -e 'FATAL EXCEPTION' -e 'Fatal signal' -e 'Abort message' \
  -e 'JNI DETECTED ERROR' -e 'AndroidRuntime.*Process: ' -e '^\*\*\* ' \
  -e 'signal [0-9]+\(SIG' -e ">>> $app <<<" -e "Cmdline: $app" \
  "$out/logcat-app.txt" 2>/dev/null | head -n 5 || true)
if [ -n "$crash" ]; then
  printf '%s\n' "$crash" | tee -a "$out/summary.txt"
  fail "crash in $app (pid $main_pid)"
fi

# ANR reports come from the system, so this stays a global scan for our package.
anr=$(grep -hE "ANR in $app" "$out/logcat.txt" 2>/dev/null | head -n 3 || true)
case "$focus" in
  *"Not Responding: $app"*) anr="${anr:-$focus}" ;;
esac
if [ -n "$anr" ]; then
  printf '%s\n' "$anr" | tee -a "$out/summary.txt"
  fail "ANR in $app"
fi

echo "ok: $app alive after ${wait_s}s with no crash" | tee -a "$out/summary.txt"

# Best-effort evidence for the installed identity: the system's app info page
# shows the launcher icon and label, recents shows the running app.
adb shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:$app" > /dev/null 2>&1 || true
sleep 4
adb exec-out screencap -p > "$out/appinfo.png" || true
sleep 4
adb exec-out screencap -p > "$out/appinfo-late.png" || true
adb shell input keyevent KEYCODE_APP_SWITCH > /dev/null 2>&1 || true
sleep 3
adb exec-out screencap -p > "$out/recents.png" || true
