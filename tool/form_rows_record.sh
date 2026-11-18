#!/usr/bin/env bash
# Stills of the grouped form rows on the emulator, light and dark, on the
# build before and the build after: the Add service, SSH and Import key
# sheets at rest, a text row focused with the keyboard up and a long value,
# a select row held, its menu, and the row after a switch.
# Usage: tool/form_rows_record.sh <after.apk> <before.apk> [out-dir]
set -euo pipefail

after_apk=${1:?usage: tool/form_rows_record.sh <after.apk> <before.apk> [out]}
before_apk=${2:?no before APK}
out=${3:-form-rows}
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

launch() { # <theme> <sheet> <marker>
  local attempt
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 2
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&tab=3&lang=en&splash=0&theme=$1&sheet=$2' -n $component" \
    > /dev/null 2>&1 || true
  sleep 6
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
  for attempt in $(seq 1 45); do
    if gate_in_front "$app" && ui has "$3" > /dev/null 2>&1; then
      sleep 2
      return 0
    fi
    sleep 2
  done
  shot "launch-fail-$1-$2"
  note "no '$3' after 90 s ($1 $2)"
  return 1
}

center() { # <label>
  local box x1 y1 x2 y2
  box=$(ui bounds "$1") || return 1
  read -r x1 y1 x2 y2 <<< "$box"
  echo "$(((x1 + x2) / 2)) $(((y1 + y2) / 2))"
}

tap() { # <label> [settle]
  local point
  point=$(center "$1") || { note "no '$1' to tap"; return 0; }
  # shellcheck disable=SC2086
  adb shell input tap $point > /dev/null 2>&1 || true
  sleep "${2:-1.5}"
}

hide_keyboard() {
  adb shell input keyevent 111 > /dev/null 2>&1 || true
  sleep 1
}

run_build() { # <tag> <apk>
  local tag=$1 apk=$2 theme point x y
  adb uninstall "$app" > /dev/null 2>&1 || true
  adb install -r "$apk" > /dev/null || { note "$tag: install failed"; return 0; }
  for theme in light dark; do
    if launch "$theme" service Scheme; then
      shot "$tag-$theme-service"
      # A grouped text row's label is the field's own semantics label, not a
      # text node, so the Name field is found as the first EditText.
      if point=$(ui edit 0); then
        # shellcheck disable=SC2086
        adb shell input tap $point > /dev/null 2>&1 || true
        sleep 1.5
      else
        note "$tag: no text field to focus"
      fi
      adb shell input text 'A%svery%slong%sservice%sname%sthat%sdoes%snot%sfit' > /dev/null 2>&1 || true
      sleep 1
      shot "$tag-$theme-service-focused-keyboard"
      hide_keyboard
      shot "$tag-$theme-service-focused"
      if point=$(center Scheme); then
        read -r x y <<< "$point"
        adb shell input motionevent DOWN "$x" "$y" > /dev/null 2>&1 || true
        sleep 0.4
        shot "$tag-$theme-service-held"
        adb shell input motionevent UP "$x" "$y" > /dev/null 2>&1 || true
        sleep 1.5
        shot "$tag-$theme-service-menu"
        tap https
        shot "$tag-$theme-service-switched"
      fi
    fi
    if launch "$theme" ssh Authentication; then
      shot "$tag-$theme-ssh"
      tap Authentication
      tap Password
      shot "$tag-$theme-ssh-password"
    fi
    if launch "$theme" key 'Import key'; then
      shot "$tag-$theme-key"
    fi
  done
}

run_build after "$after_apk"
run_build before "$before_apk"

for theme in light dark; do
  for still in service service-focused-keyboard service-focused service-held service-switched ssh-password key; do
    if [ -s "$out/before-$theme-$still.png" ] && [ -s "$out/after-$theme-$still.png" ]; then
      montage "$out/before-$theme-$still.png" "$out/after-$theme-$still.png" \
        -tile 2x -geometry 420x+4+4 -background '#222' \
        "$out/compare-$theme-$still.png" 2> /dev/null || note "no montage $theme $still"
    fi
  done
done
ls -l "$out" | tee -a "$summary" > /dev/null
