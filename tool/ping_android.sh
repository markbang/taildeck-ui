#!/usr/bin/env bash
# Ping test on a running emulator: opens a node page with `?ping=1`, which runs
# the Ping button on open, and fails when the app stalls (ANR), dies or the
# call never returns. The node is not signed in, so the expected answer is the
# library's fast "not started" error: what this proves is that a ping no longer
# blocks the UI thread.
# Usage: tool/ping_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/ping_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-ping}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
mkdir -p "$out"
: > "$out/summary.txt"

fail() {
  echo "FAIL: $*" | tee -a "$out/summary.txt"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb shell dumpsys activity top > "$out/activity-top.txt" 2>&1 || true
  exit 1
}

adb wait-for-device
activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

if ! adb shell pm path "$app" > /dev/null 2>&1; then
  adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
fi

# A ping that blocks the UI thread ANRs every launch, so a second ANR in a row
# still fails here; one alone is the emulator's cold-start focus stall.
for attempt in 1 2; do
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 3
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&node=devbox&ping=1' -n $activity" \
    > "$out/launch.txt" 2>&1 || fail "am start failed, see launch.txt"
  gate_survived_focus "$app" "$SECONDS" "$out/summary.txt" && break
  [ "$attempt" -eq 1 ] || fail "ANR in $app on two cold starts in a row"
  echo "launch attempt $attempt: the app was killed after an ANR at cold start" | tee -a "$out/summary.txt"
done

# The ping logs its start and its answer; the answer is what proves the FFI call
# returned instead of blocking the UI thread until Android kills us.
result=""
for _ in $(seq 1 40); do
  result=$(adb logcat -d 2>/dev/null | grep -m1 'taildeck ping: done' || true)
  [ -n "$result" ] && break
  sleep 1
done
adb logcat -d > "$out/logcat.txt" 2>&1 || true
adb exec-out screencap -p > "$out/node-ping.png" || true

{
  echo "apk: $apk"
  echo "application id: $app"
  echo "ping: ${result:-<no answer>}"
} | tee -a "$out/summary.txt"

[ -n "$result" ] || fail "the ping never answered within 40s"
echo "$result" | grep -q 'taildeck ping: done' || fail "unexpected ping line: $result"

pid=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
[ -n "$pid" ] || fail "process $app is gone after the ping"
adb shell dumpsys activity activities 2>/dev/null | grep -q "topResumedActivity.*$app" \
  || fail "$app is not the resumed activity after the ping"

main_pid=${pid%% *}
adb logcat -d --pid="$main_pid" > "$out/logcat-app.txt" 2>&1 || true
grep -hE "Process: $app|pid: $main_pid\b|PID: $main_pid\b|>>> $app <<<|Cmdline: $app" \
  "$out/logcat.txt" 2>/dev/null >> "$out/logcat-app.txt" || true

crash=$(grep -hE -e 'FATAL EXCEPTION' -e 'Fatal signal' -e 'Abort message' \
  -e 'JNI DETECTED ERROR' -e '^\*\*\* ' -e 'signal [0-9]+\(SIG' \
  -e ">>> $app <<<" -e "Cmdline: $app" "$out/logcat-app.txt" 2>/dev/null | head -n 5 || true)
[ -z "$crash" ] || { printf '%s\n' "$crash" | tee -a "$out/summary.txt"; fail "crash in $app during ping"; }

anr=$(grep -hE "ANR in $app" "$out/logcat.txt" 2>/dev/null | head -n 3 || true)
[ -z "$anr" ] || { printf '%s\n' "$anr" | tee -a "$out/summary.txt"; fail "ANR in $app during ping"; }

echo "ok: ping answered and $app stayed responsive" | tee -a "$out/summary.txt"
