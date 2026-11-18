#!/usr/bin/env bash
# Stills of the settings redesign on a running emulator: the grouped list, a
# section page, an open picker, a long value at the row's end, the foot of the
# logs above the floating dock, and content scrolled under the status bar.
# A missing shot is reported, never failed.
# Usage: tool/screenshots_android.sh <flutter-apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/screenshots_android.sh <flutter-apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-shots}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
sleep 20
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
timeout 590 adb logcat -v threadtime > "$out/logcat.txt" 2>&1 &

# The CI emulator can freeze on a page's first frames and lose qemu a minute
# later; every adb call after that would block until the gate's timeout.
alive() { timeout 15 adb shell true > /dev/null 2>&1; }

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

shot() { # <name>
  timeout 30 adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"
  if [ -s "$out/$1.png" ]; then
    note "$1: $(stat -c%s "$out/$1.png") bytes"
  else
    note "$1: no screenshot"
  fi
}

tap() { # <needle> [x offset from the row's end, in dp]
  local point bounds density x1 _x2 y1 y2
  if point=$(ui tap "$1"); then
    if [ -n "${2:-}" ]; then
      density=$(adb shell wm density 2> /dev/null | sed -n 's/.*Physical density: \([0-9]*\).*/\1/p' | tr -d '\r')
      bounds=$(ui bounds "$1") || bounds=""
      if [ -n "$bounds" ]; then
        read -r x1 y1 _x2 y2 <<< "$bounds"
        point="$((_x2 - $(awk -v dp="$2" -v dpi="${density:-420}" 'BEGIN { printf "%d", dp * dpi / 160 }'))) $(( (y1 + y2) / 2 ))"
      fi
    fi
    adb shell input tap $point > /dev/null 2>&1 || true
    sleep 2
    return 0
  fi
  note "tap: no row matching '$1'"
  return 1
}

swipe_up() { adb shell input swipe 540 1800 540 900 280 > /dev/null 2>&1 || true; sleep 1; }
swipe_down() { adb shell input swipe 540 900 540 1800 280 > /dev/null 2>&1 || true; sleep 1; }

record() { # <name> <seconds> <shell function>
  local name=$1 seconds=$2 action=$3
  adb shell pkill -f screenrecord > /dev/null 2>&1 || true
  sleep 0.7
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$((seconds + 2))" --bit-rate 6000000 \
    /sdcard/rec.mp4 > /dev/null 2>&1 &
  local recorder=$!
  sleep 0.4
  "$action" || true
  wait "$recorder" 2> /dev/null || true
  sleep 0.5
  adb pull /sdcard/rec.mp4 "$out/$name-raw.mp4" > /dev/null 2>&1 || true
  if [ -s "$out/$name-raw.mp4" ]; then
    ffmpeg -loglevel error -y -ss 0.2 -i "$out/$name-raw.mp4" -t "$seconds" \
      -an -vf 'scale=360:-2' "$out/$name.mp4" || true
    [ -s "$out/$name.mp4" ] && note "$name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "$name: no recording"
  fi
}

launch() { # [url]
  local url=${1:-} attempt resumed shown anrs=0
  for attempt in 1 2 3; do
    if ! alive; then
      note "launch failed: the emulator stopped answering adb"
      exit 1
    fi
    adb shell am force-stop "$app" > /dev/null 2>&1 || true
    sleep 1
    adb logcat -c > /dev/null 2>&1 || true
    if [ -n "$url" ]; then
      timeout 60 adb shell "am start -W -a android.intent.action.VIEW -d '$url' '$app'" > /dev/null 2>&1 || true
    else
      adb shell monkey -p "$app" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
    fi
    shown=$SECONDS
    sleep 6
    resumed=$(adb shell dumpsys activity activities 2> /dev/null \
      | grep -m1 -E 'mResumedActivity|topResumedActivity' || true)
    case "$resumed" in
      *"$app"*)
        if gate_survived_focus "$app" "$shown" "$summary"; then return 0; fi
        anrs=$((anrs + 1))
        if [ "$anrs" -ge 2 ]; then
          note "launch failed: $app stopped answering input on two cold starts in a row"
          return 1
        fi
        note "launch attempt $attempt: the app was killed after an ANR at cold start"
        continue
        ;;
    esac
    anrs=0
    note "launch attempt $attempt: ${resumed:-no resumed activity}"
    sleep 3
  done
  note "launch failed"
  return 1
}

settings_url="taildeck://preview/?preview=1&tab=3&lang=en"

flow() { # the settings flow, for the recording
  tap 'Tailnet & device' || true
  sleep 1.5
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 1.5
  tap 'Theme' || true
  sleep 2.5
  tap 'Light' || true
  sleep 1.5
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 1
}

# Each still starts from the same screen: a fresh launch costs a few seconds
# and makes a failed shot point at the page, not at the one before it.

adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || { note "install failed, see install.txt"; exit 0; }

launch "$settings_url"
if ui has 'Tailnet & device' > /dev/null 2>&1; then
  note "settings list: opened"
else
  note "settings list: the grouped list did not show"
fi
shot settings-grouped

# ---- a section page, and the long control server at the row's end ---------
if tap 'Tailnet & device'; then
  sleep 1
  if ui has 'controlplane' > /dev/null 2>&1; then
    note "control server: $(ui text 'controlplane' | tr -d '\n')"
  fi
  shot settings-tailnet
fi

# ---- the theme page, and an open picker ---------------------------------
launch "$settings_url"
if tap 'Theme'; then
  sleep 2
  shot settings-theme
  tap 'Light' || true
  sleep 1.5
  shot settings-theme-light
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 1
fi
launch "$settings_url"
# The menu opens from the row's value, not its label.
if tap 'Language' 48; then
  sleep 2
  if ! ui has 'English' > /dev/null 2>&1; then
    note "picker: the menu did not open, tapping again"
    tap 'Language' 48 || true
    sleep 2
  fi
  shot settings-picker
fi

# ---- the logs page -------------------------------------------------------
launch "$settings_url"
if tap 'Logs'; then
  sleep 2
  shot settings-logs
fi

# ---- the foot of a long page, above the floating dock -------------------
launch "taildeck://preview/?preview=1&tab=3&lang=en&scale=1.3"
for _ in 1 2 3 4 5 6 7 8; do swipe_up; done
shot settings-bottom-dock
# ... and the same page scrolled only a little, so its title runs under the
# status bar behind the scrim.
launch "taildeck://preview/?preview=1&tab=3&lang=en&scale=1.3"
swipe_up
sleep 2
shot settings-statusbar
sleep 1
shot settings-statusbar-settled
launch "taildeck://preview/?preview=1&tab=3&lang=en&scale=1.3&theme=light"
sleep 3
swipe_up
sleep 2
shot settings-statusbar-light

# ---- a longer list's foot: the agents page, with its floating button -----
launch "taildeck://preview/?preview=1&tab=2&lang=en&scale=1.3"
for _ in 1 2 3 4 5 6 7 8; do swipe_up; done
sleep 2
shot agents-bottom-dock

# ---- the key sheet, over the dock ---------------------------------------
launch "taildeck://preview/?preview=1&sheet=key&lang=en"
sleep 2
shot settings-key-sheet

# ---- the recorded flow --------------------------------------------------
launch "$settings_url"
record settings-flow 14 flow

note "done"
