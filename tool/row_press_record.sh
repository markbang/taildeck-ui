#!/usr/bin/env bash
# Records a row press on the emulator, on the build before and the build after
# the row highlight fix, in light and dark: Settings' first, middle and last
# rows, the Language select and the lone Sign out row held and released, and a
# drag that starts on a row. Media problems are reported, never failed.
# Usage: tool/row_press_record.sh <after.apk> <before.apk> [out-dir]
set -euo pipefail

after_apk=${1:?usage: tool/row_press_record.sh <after.apk> <before.apk> [out]}
before_apk=${2:?no before APK}
out=${3:-row-press}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
app=top.bangwu.taildeck
component="$app/${TAILDECK_ACTIVITY:-top.bangwu.taildeck_ui.MainActivity}"
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }
# A wedged emulator must not hang the run: every adb call gets 60 s.
adb_bin=$(command -v adb)
adb() { timeout 60 "$adb_bin" "$@"; }

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
sleep 5

ui() {
  local attempt
  for attempt in 1 2 3; do
    rm -f "$out/ui.xml"
    adb shell rm -f /sdcard/ui.xml > /dev/null 2>&1 || true
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if [ -s "$out/ui.xml" ] &&
      python3 "$here/ui.py" "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }
back_key() { adb shell input keyevent 4 > /dev/null 2>&1 || true; }

launch() { # <theme>
  local attempt
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 2
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&tab=3&lang=en&splash=0&theme=$1' -n $component" \
    > /dev/null 2>&1 || true
  sleep 6
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
  for attempt in $(seq 1 45); do
    if gate_in_front "$app" && ui has Language > /dev/null 2>&1; then
      sleep 2
      return 0
    fi
    sleep 2
  done
  shot "launch-fail-$1"
  note "no Settings after 90 s ($1)"
  return 1
}

row_point() { # <label>: a point inside the row, left of its value
  local box x1 y1 x2 y2
  box=$(ui bounds "$1") || return 1
  read -r x1 y1 x2 y2 <<< "$box"
  echo "$(((x1 + x2) / 2)) $(((y1 + y2) / 2))"
}

# Holds a row, takes stills while it is held, releases it and comes back.
hold_row() { # <prefix> <label>
  local prefix=$1 point x y
  point=$(row_point "$2") || { note "$prefix: no '$2' on screen"; return 0; }
  read -r x y <<< "$point"
  adb shell input motionevent DOWN "$x" "$y" > /dev/null 2>&1 || true
  shot "$prefix-held-a"
  sleep 0.4
  shot "$prefix-held-b"
  adb shell input motionevent UP "$x" "$y" > /dev/null 2>&1 || true
  shot "$prefix-released"
  sleep 1.5
  shot "$prefix-opened"
  back_key
  sleep 1.5
  shot "$prefix-back"
}

# A drag that starts on a row, with stills while the finger is still down.
drag_rows() { # <prefix>
  local prefix=$1 point x y step
  point=$(row_point Theme) || { note "$prefix: no Theme row"; return 0; }
  read -r x y <<< "$point"
  adb shell input motionevent DOWN "$x" "$y" > /dev/null 2>&1 || true
  for step in 1 2 3 4 5 6 7 8 9 10 11 12; do
    adb shell input motionevent MOVE "$x" "$((y - step * 40))" > /dev/null 2>&1 || true
  done
  shot "$prefix-dragging"
  for step in 11 10 9 8 7 6 5 4 3 2 1 0; do
    adb shell input motionevent MOVE "$x" "$((y - step * 40))" > /dev/null 2>&1 || true
  done
  shot "$prefix-dragging-back"
  adb shell input motionevent UP "$x" "$y" > /dev/null 2>&1 || true
  sleep 1
  shot "$prefix-after-drag"
}

clip_presses() {
  local point x y
  for label in 'Tailnet & device' Theme About Language 'Sign out of the tailnet'; do
    point=$(row_point "$label") || continue
    read -r x y <<< "$point"
    adb shell input motionevent DOWN "$x" "$y" > /dev/null 2>&1 || true
    sleep 0.6
    adb shell input motionevent UP "$x" "$y" > /dev/null 2>&1 || true
    sleep 1.2
    back_key
    sleep 1.2
  done
  # Quick taps, as a thumb taps.
  point=$(row_point Theme) && {
    read -r x y <<< "$point"
    adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
    sleep 1.2
    back_key
    sleep 1.2
  }
}

clip_drag() {
  local point x y step
  point=$(row_point Theme) || return 0
  read -r x y <<< "$point"
  for _ in 1 2; do
    adb shell input swipe "$x" "$y" "$x" "$((y - 700))" 500 > /dev/null 2>&1 || true
    sleep 0.6
    adb shell input swipe "$x" "$((y - 700))" "$x" "$y" 500 > /dev/null 2>&1 || true
    sleep 0.6
  done
}

record() { # <name> <seconds> <function>
  local name=$1 seconds=$2
  adb shell rm -f "/sdcard/$name.mp4" > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$seconds" --bit-rate 12000000 \
    "/sdcard/$name.mp4" > /dev/null 2>&1 &
  local recorder=$!
  sleep 0.8
  "$3" || note "$name: the step reported a miss"
  wait "$recorder" 2> /dev/null || true
  sleep 0.5
  adb pull "/sdcard/$name.mp4" "$out/$name.mp4" > /dev/null 2>&1 || true
  if [ -s "$out/$name.mp4" ]; then
    note "clip $name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "clip $name: none"
  fi
}

run_build() { # <tag> <apk>
  local tag=$1 apk=$2 theme
  adb uninstall "$app" > /dev/null 2>&1 || true
  adb install -r "$apk" > /dev/null || { note "$tag: install failed"; return 0; }
  for theme in light dark; do
    launch "$theme" || continue
    shot "$tag-$theme-settings"
    hold_row "$tag-$theme-first" 'Tailnet & device'
    hold_row "$tag-$theme-middle" Theme
    hold_row "$tag-$theme-last" About
    hold_row "$tag-$theme-language" Language
    hold_row "$tag-$theme-single" 'Sign out of the tailnet'
    record "$tag-$theme-press" 28 clip_presses
    # Larger text, so Settings is a list that scrolls.
    adb shell settings put system font_scale 1.3 > /dev/null 2>&1 || true
    if launch "$theme"; then
      drag_rows "$tag-$theme"
      record "$tag-$theme-drag" 10 clip_drag
    fi
    adb shell settings put system font_scale 1.0 > /dev/null 2>&1 || true
  done
}

run_build after "$after_apk"
run_build before "$before_apk"

# Before and after side by side, for each held row.
for theme in light dark; do
  for row in first middle last language single; do
    if [ -s "$out/before-$theme-$row-held-b.png" ] && [ -s "$out/after-$theme-$row-held-b.png" ]; then
      montage "$out/before-$theme-$row-held-a.png" "$out/before-$theme-$row-held-b.png" \
        "$out/after-$theme-$row-held-a.png" "$out/after-$theme-$row-held-b.png" \
        -tile 4x -geometry 360x+4+4 -background '#222' \
        "$out/compare-$theme-$row.png" 2> /dev/null || note "no montage $theme $row"
    fi
  done
done
ls -l "$out" | tee -a "$summary" > /dev/null
