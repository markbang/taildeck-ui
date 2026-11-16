#!/usr/bin/env bash
# Agents cold-start gate: launch straight into the Agents tab before the
# tailnet is Running, then fail when an error or the connection form shows up
# while the node is still coming up. `?preview=1` shows the shell without a
# signed-in node; the release APK is enough, since nothing here needs demo data.
# Usage: tool/agents_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/agents_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-agents}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
mkdir -p "$out"

fail() {
  echo "FAIL: $*" | tee -a "$out/summary.txt"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui-fail.xml" > /dev/null 2>&1 || true
  adb uninstall "$app" > /dev/null 2>&1 || true
  exit 1
}
pass() { echo "ok: $*" | tee -a "$out/summary.txt"; }
note() { echo "$*" | tee -a "$out/summary.txt"; }

adb wait-for-device

# A fresh install has no saved herdr target and no node key: the exact cold
# start the report describes.
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"

# After the install: resolve-activity answers for whatever build is on the
# device, and the gates before this one install their own.
activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

shot() { adb exec-out screencap -p > "$out/$1.png" || true; }

# A dump is what the loading spinner blocks, so this reads the window manager.
in_front() { gate_in_front "$app"; }

# The page under test must be our process, in front: a dismissed app would
# make every "no error on screen" check true for the wrong reason.
alive() { # $1: step
  local pid front tries=5
  pid=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
  [ -n "$pid" ] || fail "$1: $app is not running (crashed or was killed)"
  # uiautomator dumps the window that is on screen, so its package is the
  # front window the checks below see. mCurrentFocus can name the launcher
  # while our window is already drawn on this emulator.
  while [ "$tries" -gt 0 ]; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    front=$(sed -n 's/.*package="\([^"]*\)".*/\1/p' "$out/ui.xml" 2>/dev/null | head -n 1)
    if [ "$front" = "$app" ]; then
      echo "front: $front" >> "$out/focus.txt"
      return 0
    fi
    sleep 1
    tries=$((tries - 1))
  done
  fail "$1: $app is not in front (front package: ${front:-none})"
}

ui() {
  local attempt
  # A dump on this emulator costs seconds and fails while the spinner runs, so
  # a miss is retried a few times, not ten.
  for attempt in 1 2 3 4; do
    adb shell uiautomator dump /sdcard/ui.xml > "$out/uiautomator.txt" 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if python3 tool/ui.py "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 1
  done
  return 1
}

# The loading state spins, and uiautomator refuses to dump a window that never
# idles; an empty tree is that, not a page without the text.
tree_readable() { grep -q '<node' "$out/ui.xml" 2>/dev/null; }

# Every string the page must never show while the node is not Running. The
# tree is read once and every string is matched against that dump: one dump
# per check, not one per string.
forbidden() {
  local needle tries=3
  while [ "$tries" -gt 0 ]; do
    rm -f "$out/ui.xml"
    adb shell uiautomator dump /sdcard/ui.xml > "$out/uiautomator.txt" 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    tree_readable && break
    tries=$((tries - 1))
  done
  # Without a tree there is nothing to read, and the summary says so.
  tree_readable || { note "note: no UI tree (uiautomator could not idle); the strings below are unchecked this pass"; return 0; }
  for needle in \
    "no such host" \
    "lookup " \
    "Can't find node" \
    "Could not connect to herdr" \
    "Connect herdr" \
    "Retry"; do
    if python3 tool/ui.py "$out/ui.xml" has "$needle" 2> /dev/null; then
      fail "the Agents page shows \"$needle\" before the tailnet is Running"
    fi
  done
}

launch() {
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 3
  adb logcat -c > /dev/null 2>&1 || true
  # Straight into the Agents tab, with the shell shown but no node behind it.
  # `splash=0` drops the launch animation so the screenshot is the page itself.
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&tab=2&lang=en&splash=0' -n $activity" \
    > "$out/launch.txt" 2>&1 || return 1
  grep -q "Activity: $app/" "$out/launch.txt" || return 1
  local _i
  for _i in $(seq 1 30); do
    if adb logcat -d 2>/dev/null | grep -q "taildeck agents: "; then return 0; fi
    sleep 1
  done
  return 1
}

# A cold start on a loaded emulator can ANR the debug build; one retry.
settled=0
for attempt in 1 2; do
  if launch && wait_home "$app" "$out" "$here" '' 45 && in_front; then
    sleep 2
    if ui has "Connecting to the tailnet"; then settled=1; break; fi
    if ! tree_readable && adb logcat -d 2>/dev/null | grep -q 'taildeck agents: tailnet'; then
      note "note: the tree could not be dumped; the log reports the tailnet loading phase"
      settled=1
      break
    fi
  fi
  note "Agents cold start attempt $attempt did not settle"
  sleep 5
done
[ "$settled" -eq 1 ] || fail "the loading state is not on screen"

phase=$(adb logcat -d 2>/dev/null | grep -oE 'taildeck agents: [a-z]+' | tail -1 | awk '{print $3}')
note "first phase in logcat: ${phase:-none}"
[ "$phase" = "tailnet" ] || fail "the page did not start on the tailnet loading state (got '${phase:-none}')"

alive "after launch"
alive "first check"
shot agents-start
forbidden

# Still no node after the retry budget in the logs: no error may have appeared.
sleep 8
alive "second check"
if tree_readable; then
  ui has "Connecting to the tailnet" || fail "the loading state left the screen without a node"
fi
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
# Leave the device clean: the gates after this one install their own APK, and
# the release build here would block that install with its signature.
adb uninstall "$app" > /dev/null 2>&1 || true
