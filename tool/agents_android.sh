#!/usr/bin/env bash
# Agents cold-start gate: launch straight into the Agents tab before the
# tailnet is Running, then fail when an error or the connection form shows up
# while the node is still coming up. Uses the debug build, which can show the
# shell without a signed-in node (`?preview=1`).
# Usage: tool/agents_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/agents_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-agents}
mkdir -p "$out"

fail() {
  echo "FAIL: $*" | tee -a "$out/summary.txt"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui-fail.xml" > /dev/null 2>&1 || true
  exit 1
}
pass() { echo "ok: $*" | tee -a "$out/summary.txt"; }
note() { echo "$*" | tee -a "$out/summary.txt"; }

adb wait-for-device
activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

# A fresh install has no saved herdr target and no node key: the exact cold
# start the report describes.
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"

shot() { adb exec-out screencap -p > "$out/$1.png" || true; }

ui() {
  local attempt
  for attempt in 1 2 3; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if python3 tool/ui.py "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

# Every string the page must never show while the node is not Running.
forbidden() {
  local needle
  for needle in \
    "no such host" \
    "lookup " \
    "Can't find node" \
    "Could not connect to herdr" \
    "Connect herdr" \
    "Retry"; do
    if ui has "$needle"; then
      fail "the Agents page shows \"$needle\" before the tailnet is Running"
    fi
  done
}

launch() {
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 3
  adb logcat -c > /dev/null 2>&1 || true
  # Straight into the Agents tab, with the shell shown but no node behind it.
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&tab=2&lang=en' -n $activity" \
    > "$out/launch.txt" 2>&1 || return 1
  grep -q "Activity: $app/" "$out/launch.txt" || return 1
  local _i
  for _i in $(seq 1 60); do
    if adb logcat -d 2>/dev/null | grep -q "taildeck agents: "; then return 0; fi
    sleep 1
  done
  return 1
}

# A cold start on a loaded emulator can ANR the debug build; one retry.
if ! launch; then
  sleep 5
  launch || fail "the Agents tab never opened; see launch.txt and logcat-fail.txt"
fi

phase=$(adb logcat -d 2>/dev/null | grep -oE 'taildeck agents: [a-z]+' | tail -1 | awk '{print $3}')
note "first phase in logcat: ${phase:-none}"
[ "$phase" = "tailnet" ] || fail "the page did not start on the tailnet loading state (got '${phase:-none}')"

sleep 2
shot agents-start
ui has "Connecting to the tailnet" || fail "the loading state is not on screen"
forbidden

# Still no node after the retry budget in the logs: no error may have appeared.
sleep 8
shot agents-late
forbidden
phases=$(adb logcat -d 2>/dev/null | grep -oE 'taildeck agents: [a-z]+' | awk '{print $3}' | sort -u | tr '\n' ' ')
note "phases seen: $phases"
case " $phases " in
  *" failed "*) fail "the page reported a herdr failure before the tailnet was Running" ;;
esac

exceptions=$(adb logcat -d 2>/dev/null \
  | grep -hE -e 'EXCEPTION CAUGHT BY' -e 'Another exception was thrown' -e 'Bad state: ' \
  | head -n 5 || true)
if [ -n "$exceptions" ]; then
  printf '%s\n' "$exceptions" | tee -a "$out/summary.txt"
  fail "a Flutter exception was logged while the Agents page was open"
fi

pass "Agents cold start waits on the tailnet with no error and no form (screenshots agents-start.png, agents-late.png)"
