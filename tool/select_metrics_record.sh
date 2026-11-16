#!/usr/bin/env bash
# Records the Language menu of a non-debug build and of FlClash 0.9.3 on one
# emulator, at the same device size, and measures both menus' row pitch so the
# two can be compared in dp. The Taildeck build is the release APK: no DEBUG
# banner, and About reads the version from PackageInfo.
# Usage: tool/select_metrics_record.sh <taildeck-release.apk> <flclash.apk> [out-dir]
set -euo pipefail

apk=${1:?usage: tool/select_metrics_record.sh <apk> <flclash.apk> [out]}
flclash_apk=${2:?no FlClash APK}
out=${3:-select-metrics}
here=$(cd "$(dirname "$0")" && pwd)
app=top.bangwu.taildeck
flclash=com.follow.clash
component="$app/${TAILDECK_ACTIVITY:-top.bangwu.taildeck_ui.MainActivity}"
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }
fail() {
  echo "FAIL: $*" | tee -a "$summary"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  exit 1
}

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
sleep 5

W= SH= DEN=
geometry() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  DEN=$(adb shell wm density | sed -n 's/.*Physical density: \([0-9]*\).*/\1/p' | tr -d '\r')
  [ -n "${W:-}" ] && [ -n "${DEN:-}" ] || fail "no screen geometry"
  note "device: ${W}x${SH} at ${DEN} dpi, $(awk -v w="$W" -v d="$DEN" 'BEGIN { printf "%.1f", w * 160 / d }') dp wide"
}
geometry

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }
back_key() { adb shell input keyevent 4 > /dev/null 2>&1 || true; }

ui() {
  local attempt
  for attempt in 1 2 3; do
    rm -f "$out/ui.xml"
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if [ -s "$out/ui.xml" ] && python3 "$here/ui.py" "$out/ui.xml" "$@" 2> /dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

tap_point() { # 'x y' [settle seconds]
  # shellcheck disable=SC2086
  adb shell input tap $1 > /dev/null 2>&1 || true
  sleep "${2:-1}"
}

wait_for() { # <text> [seconds]
  local waited=0 limit=${2:-30}
  while [ "$waited" -lt "$limit" ]; do
    ui has "$1" > /dev/null 2>&1 && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

value_point() { # <row label>: the row's value, where a select opens from
  local box x1 y1 x2 y2
  box=$(ui bounds "$1") || return 1
  read -r x1 y1 x2 y2 <<< "$box"
  echo "$((x2 - 40)) $(((y1 + y2) / 2))"
}

dismiss_system_dialogs() {
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
  for label in Allow 允许 OK; do
    if point=$(ui tap "$label" 2> /dev/null); then
      # shellcheck disable=SC2086
      tap_point "$point" 1
    fi
  done
}

# The menu's geometry, from the two labels that appear only inside it.
measure() { # <tag> <top label> <rows between> <bottom label>
  local tag=$1 top=$2 rows=$3 bottom=$4 line
  ui all "$top" > /dev/null 2>&1 || return 0
  line=$(python3 "$here/menu_metrics.py" "$out/ui.xml" "$top" "$rows" "$bottom" "$DEN" 2> /dev/null) || line=""
  if [ -n "$line" ]; then
    note "$tag menu: $line"
  else
    note "$tag menu: no bounds for $top and $bottom"
  fi
}

version_of() { # the app's own About subtitle
  ui has Version > /dev/null 2>&1 && python3 "$here/ui.py" "$out/ui.xml" texts "$SH" |
    grep -m1 -i 'version' || true
}

# ---- Taildeck, release APK ------------------------------------------------

adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install-taildeck.txt" 2>&1 ||
  fail "adb install of the release APK failed, see install-taildeck.txt"
adb shell am force-stop "$app" > /dev/null 2>&1 || true
sleep 1
adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&tab=3&lang=en&splash=0' -n $component" \
  > /dev/null 2>&1 || true
sleep 6
dismiss_system_dialogs
wait_for Language 60 || fail "no Language row in the release build"
sleep 1
shot taildeck-settings
note "taildeck about: $(version_of)"
detail=$(ui bounds Language) || fail "no bounds for Language"
read -r lx1 ly1 lx2 ly2 <<< "$detail"
note "taildeck language row: $detail"
tap_point "$(value_point Language)" 2
ui has 中文 > /dev/null 2>&1 || fail "the release build's language menu did not open"
shot taildeck-open
ui all System > /dev/null 2>&1 && note "taildeck system: $(ui all System | head -1)"
measure taildeck System 2 中文
tap_point "$((W / 8)) $((SH / 10))" 2
shot taildeck-closed
ui has 中文 > /dev/null 2>&1 && note "taildeck language menu stayed open"
back_key
sleep 1

# ---- FlClash --------------------------------------------------------------

disclaimer="The Software itself does not provide any proxy server, node, subscription, or network access service, and has no partnership, agency, or guarantee relationship with any provider of such services."
type_pieces() { # <text>
  local text=$1 offset=0 piece
  while [ "$offset" -lt "${#text}" ]; do
    piece=${text:offset:24}
    adb shell input text "$(printf '%s' "$piece" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
    offset=$((offset + 24))
    sleep 0.25
  done
}
accept_flclash_disclaimer() {
  local point
  point=$(ui tap Agree 2> /dev/null) || point=$(ui tap 同意 2> /dev/null) || return 0
  tap_point "$point" 2
  if ui has Confirm > /dev/null 2>&1; then
    if point=$(ui edit 0 2> /dev/null); then
      tap_point "$point" 1
      type_pieces "$disclaimer"
      sleep 2
    elif point=$(ui tap "I have read" 2> /dev/null); then
      tap_point "$point" 1
    fi
    point=$(ui tap Confirm 2> /dev/null) && tap_point "$point" 3
  fi
}

adb install -g "$flclash_apk" > "$out/install-flclash.txt" 2>&1 ||
  fail "FlClash install failed, see install-flclash.txt"
adb shell am force-stop "$flclash" > /dev/null 2>&1 || true
sleep 2
adb shell monkey -p "$flclash" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
sleep 12
dismiss_system_dialogs
accept_flclash_disclaimer
sleep 3
dismiss_system_dialogs
shot flclash-home

# Its Tools tab holds the Settings list with the Language row; the label is
# not always published, so the tab's corner is the fallback.
open_tools() {
  local attempt
  for attempt in 1 2 3; do
    if point=$(ui tap Tools 2> /dev/null); then
      # shellcheck disable=SC2086
      tap_point "$point" 3
    else
      tap_point "$((W * 7 / 8)) $((SH - 160))" 3
    fi
    if ui has Language > /dev/null 2>&1; then return 0; fi
    # A list longer than the page keeps the row below the fold.
    adb shell input swipe "$((W / 2))" "$((SH * 3 / 5))" "$((W / 2))" "$((SH / 5))" 300 \
      > /dev/null 2>&1 || true
    sleep 2
    ui has Language > /dev/null 2>&1 && return 0
  done
  return 1
}

if open_tools; then
  shot flclash-settings
  ui bounds Language > "$out/flclash-language-row.txt" 2> /dev/null || true
  note "flclash language row: $(ui bounds Language 2> /dev/null || echo none)"
  tap_point "$(value_point Language)" 3
  ui has English > /dev/null 2>&1 || note "FlClash: no English entry in its menu"
  shot flclash-open
  measure flclash Default 6 Russian
  tap_point "$((W / 8)) $((SH / 10))" 3
  shot flclash-closed
else
  shot flclash-fail
  note "FlClash: no Language row; see flclash-home.png and flclash-fail.png"
fi
back_key
sleep 1

# ---- the same frame, side by side ----------------------------------------

for name in open closed settings; do
  [ -s "$out/taildeck-$name.png" ] && [ -s "$out/flclash-$name.png" ] || continue
  convert "$out/taildeck-$name.png" "$out/flclash-$name.png" +append \
    "$out/metrics-$name.png" 2> /dev/null ||
    note "$name: no side-by-side"
done
for name in open closed; do
  [ -s "$out/metrics-$name.png" ] || continue
  # The page's lower half, around the Language row and the menu out of it.
  convert "$out/metrics-$name.png" -crop "$((W * 2))x$((SH * 45 / 100))+0+$((SH * 45 / 100))" \
    +repage "$out/crop-$name.png" 2> /dev/null ||
    note "$name: no crop"
done

note "files: $(ls "$out"/*.png 2> /dev/null | wc -l) stills"
