#!/usr/bin/env bash
# Records Taildeck and FlClash side by side: a settings subpage opened from the
# list, its bar, the content scrolling under it, and back; then a first-level
# list collapsing its large title into the bar. Checks Taildeck's own steps.
# Usage: tool/header_flclash_record.sh <taildeck-apk> <flclash-apk> [out-dir]
set -euo pipefail

apk=${1:?usage: tool/header_flclash_record.sh <taildeck-apk> <flclash-apk> [out-dir]}
flclash_apk=${2:?no FlClash APK}
out=${3:-header-flclash}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
slow=${HEADER_SLOW:-5}
app=top.bangwu.taildeck
flclash=com.follow.clash
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }
fail() {
  echo "FAIL: $*" | tee -a "$summary"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui-fail.xml" > /dev/null 2>&1 || true
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

W= SH=
geometry() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  [ -n "${W:-}" ] || fail "no screen size"
}

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }
back_key() { adb shell input keyevent 4 > /dev/null 2>&1 || true; }

ui() {
  local attempt
  for attempt in 1 2 3; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if python3 "$here/ui.py" "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

tap_point() { # 'x y' [settle seconds]
  # shellcheck disable=SC2086
  adb shell input tap $1 > /dev/null 2>&1 || true
  sleep "${2:-1}"
}

scroll_page() { # [settle seconds]
  adb shell input swipe "$((W / 2))" "$((SH * 2 / 3))" "$((W / 2))" "$((SH / 3))" 300 \
    > /dev/null 2>&1 || true
  sleep "${1:-1}"
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

# Stills as fast as screencap allows, around a tap, to catch the bar arriving.
tap_then_stills() { # <prefix> <'x y'> [settle seconds]
  adb exec-out screencap -p > /dev/null 2>&1 || true
  # shellcheck disable=SC2086
  ( adb shell input tap $2 > /dev/null 2>&1 || true ) &
  local i
  for i in 1 2 3 4 5 6; do
    adb exec-out screencap -p > "$out/$1-$i.png" 2> /dev/null || true
  done
  wait
  sleep "${3:-1}"
}

record() { # <name> <seconds> <command...>
  local name=$1 seconds=$2
  shift 2
  adb shell rm -f "/sdcard/$name.mp4" > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$seconds" --bit-rate 12000000 \
    "/sdcard/$name.mp4" > /dev/null 2>&1 &
  local recorder=$!
  sleep 0.8
  "$@" || note "$name: the step reported a miss"
  wait "$recorder" 2> /dev/null || true
  sleep 0.5
  adb pull "/sdcard/$name.mp4" "$out/$name.mp4" > /dev/null 2>&1 || true
  if [ -s "$out/$name.mp4" ]; then
    note "clip $name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "clip $name: none"
  fi
}

# ---- Taildeck ------------------------------------------------------------

component="$app/${TAILDECK_ACTIVITY:-top.bangwu.taildeck_ui.MainActivity}"
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install-taildeck.txt" 2>&1 || fail "adb install failed, see install-taildeck.txt"

launch_taildeck() { # [time dilation]
  local stretch=${1:-$slow}
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 2
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&tab=3&lang=en&splash=0&slow=$stretch' -n $component" \
    > "$out/launch-taildeck.txt" 2>&1 || true
  if [ "$stretch" -gt 10 ]; then
    sleep 15
    dismiss_system_dialogs
    return 0
  fi
  sleep 3
  dismiss_system_dialogs
  local attempt
  for attempt in $(seq 1 20); do
    if gate_in_front "$app" && ui has Settings > /dev/null 2>&1; then
      sleep 1
      return 0
    fi
    sleep 2
  done
  shot taildeck-launch-fail
  ui texts "$SH" > "$out/taildeck-launch-fail.txt" 2> /dev/null || true
  note "Taildeck: no settings list after 40 s, carrying on"
}

dismiss_system_dialogs() {
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
  for label in Allow 允许 OK; do
    if point=$(ui tap "$label" 2> /dev/null); then
      # shellcheck disable=SC2086
      adb shell input tap $point > /dev/null 2>&1 || true
      sleep 1
    fi
  done
}

theme_point=
theme_step() { tap_then_stills taildeck-push "$theme_point" $((slow + 1)); }
collapse_step() { scroll_page 2; }
back_step() { back_key; sleep 2; }

geometry
launch_taildeck
shot taildeck-settings
wait_for Settings 15 || fail "the settings list does not open"
ui has "Tailnet & device" > /dev/null 2>&1 ||
  note "Taildeck settings: the section rows did not reach the dump"
note "Taildeck settings: large title at rest"

# The list hands its title to the bar as it scrolls.
record taildeck-collapse 10 collapse_step
shot taildeck-settings-scrolled
ui has Settings > /dev/null 2>&1 && note "Taildeck settings: the bar carries the title"
scroll_page
shot taildeck-settings-end

theme_point=$(ui tap Theme) || fail "no Theme row on the settings list"
record taildeck-push 12 theme_step
shot taildeck-theme
wait_for "Theme mode" 15 || fail "the theme page did not open"
note "Taildeck theme page: bar with the back button and the title"

# The content runs under the bar as it scrolls.
record taildeck-scroll 10 scroll_page
shot taildeck-theme-scrolled

back_key
sleep 2
shot taildeck-back
ui has "Tailnet & device" > /dev/null 2>&1 ||
  fail "back from the theme page did not return to the list"
note "Taildeck back: the list, with its title"

alive=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
[ -n "$alive" ] || fail "Taildeck died during the recording"
exceptions=$(adb logcat -d 2> /dev/null | grep -hE -e 'EXCEPTION CAUGHT BY' -e 'Another exception was thrown' | head -n 3 || true)
[ -z "$exceptions" ] || fail "Taildeck logged a Flutter exception: $exceptions"
note "Taildeck: alive, no Flutter exception"

# ---- FlClash -------------------------------------------------------------

disclaimer_statement="The Software itself does not provide any proxy server, node, subscription, or network access service, and has no partnership, agency, or guarantee relationship with any provider of such services."

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
  local point attempt
  point=$(ui tap Agree 2> /dev/null) || point=$(ui tap 同意 2> /dev/null) || return 0
  tap_point "$point" 2
  if ui has Confirm > /dev/null 2>&1; then
    if point=$(ui edit 0 2> /dev/null); then
      tap_point "$point" 1
      type_pieces "$disclaimer_statement"
      sleep 2
    elif point=$(ui tap "I have read" 2> /dev/null); then
      tap_point "$point" 1
    fi
    point=$(ui tap Confirm 2> /dev/null) && tap_point "$point" 3
    ui has Confirm > /dev/null 2>&1 && note "disclaimer: Confirm still disabled"
  fi
}

launch_flclash() {
  adb shell am force-stop "$flclash" > /dev/null 2>&1 || true
  sleep 2
  adb shell monkey -p "$flclash" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
  sleep 10
  dismiss_system_dialogs
  accept_flclash_disclaimer
  sleep 3
  shot flclash-launch
  ui texts "$SH" > "$out/flclash-launch.txt" 2> /dev/null || true
  if wait_for Tools 20 || wait_for 工具 5; then return 0; fi
  adb shell input tap "$((W * 7 / 8))" "$((SH - 160))" > /dev/null 2>&1 || true
  sleep 2
  ui has Language > /dev/null 2>&1 || ui has Theme > /dev/null 2>&1
}

open_tools() {
  if tap_label Tools || tap_label 工具; then
    sleep 2
    return 0
  fi
  adb shell input tap "$((W * 7 / 8))" "$((SH - 160))" > /dev/null 2>&1 || true
  sleep 2
  ui has Language > /dev/null 2>&1 || ui has Theme > /dev/null 2>&1
}

tap_label() { # <text>
  local point
  point=$(ui tap "$1") || return 1
  # shellcheck disable=SC2086
  adb shell input tap $point > /dev/null 2>&1 || true
  sleep 0.8
}

flclash_theme_step() { tap_point "$1" 3; }
flclash_scroll_step() { scroll_page 2; }

adb install -g "$flclash_apk" > "$out/install-flclash.txt" 2>&1 || note "FlClash install failed, see install-flclash.txt"
if launch_flclash; then
  shot flclash-home
  if open_tools; then
    shot flclash-tools
    flclash_theme_point=$(ui tap Theme 2> /dev/null) || flclash_theme_point=""
    if [ -n "$flclash_theme_point" ]; then
      record flclash-push 12 flclash_theme_step "$flclash_theme_point"
      shot flclash-theme
      wait_for "Theme mode" 15 && note "FlClash theme page: mode rows found" ||
        note "FlClash theme page: no 'Theme mode' in the dump"
      record flclash-scroll 10 flclash_scroll_step
      shot flclash-theme-scrolled
      record flclash-back 10 back_key
      sleep 2
      shot flclash-back
      ui has Language > /dev/null 2>&1 && note "FlClash back: the tools list" ||
        note "FlClash back: the list did not come back"
    else
      note "FlClash: no Theme row on its tools page"
    fi
    # Its first-level list, scrolled, for the collapse pair.
    record flclash-collapse 10 flclash_scroll_step
    shot flclash-tools-scrolled
  else
    note "FlClash: no Tools tab"
  fi
  adb logcat -d 2> /dev/null | grep -i "follow.clash" | tail -20 >> "$summary" || true
else
  note "FlClash never showed its Tools tab; only Taildeck is recorded"
fi

# ---- side by side --------------------------------------------------------

scene_time() { # <clip>: seconds of its first frame that differs much
  local time
  time=$(ffmpeg -loglevel error -i "$1" -vf "select='gt(scene,0.06)',metadata=print:file=-" \
    -f null - 2> /dev/null | sed -n 's/.*pts_time:\([0-9.]*\).*/\1/p' | head -n 1)
  awk -v t="${time:-0}" 'BEGIN { printf "%.2f", (t > 0.35 ? t - 0.35 : 0) }'
}

side_by_side() { # <name> <taildeck clip> <flclash clip> [seconds]
  local name=$1 td=$2 fl=$3 length=${4:-6}
  [ -s "$out/$td.mp4" ] && [ -s "$out/$fl.mp4" ] || { note "no pair for $name"; return 0; }
  local td_start fl_start
  td_start=$(scene_time "$out/$td.mp4")
  fl_start=$(scene_time "$out/$fl.mp4")
  note "$name: Taildeck from ${td_start}s, FlClash from ${fl_start}s"
  ffmpeg -loglevel error -y -ss "$td_start" -t "$length" -i "$out/$td.mp4" \
    -ss "$fl_start" -t "$length" -i "$out/$fl.mp4" \
    -filter_complex "[0:v]scale=540:-2,setsar=1[l];[1:v]scale=540:-2,setsar=1,tpad=stop_mode=clone:stop_duration=$length[r];[l][r]hstack=inputs=2,drawtext=text=Taildeck:x=14:y=14:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5,drawtext=text=FlClash:x=554:y=14:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5" \
    -an "$out/$name.mp4" 2> /dev/null || true
  [ -s "$out/$name.mp4" ] && note "side by side $name: $out/$name.mp4" || note "side by side $name: none"
}

side_by_side header-push taildeck-push flclash-push 6
side_by_side header-scroll taildeck-scroll flclash-scroll 5
side_by_side header-back taildeck-back flclash-back 5

for pair in \
  "settings:taildeck-settings:flclash-tools" \
  "theme:taildeck-theme:flclash-theme" \
  "theme-scrolled:taildeck-theme-scrolled:flclash-theme-scrolled" \
  "back:taildeck-back:flclash-back" \
  "collapse:taildeck-settings-scrolled:flclash-tools-scrolled"; do
  name=${pair%%:*}
  rest=${pair#*:}
  td=${rest%%:*}
  fl=${rest#*:}
  if [ -s "$out/$td.png" ] && [ -s "$out/$fl.png" ]; then
    convert "$out/$td.png" -resize 540x "$out/td-$name.png" 2> /dev/null || true
    convert "$out/$fl.png" -resize 540x "$out/fl-$name.png" 2> /dev/null || true
    convert "$out/td-$name.png" "$out/fl-$name.png" +append \
      -gravity northwest -annotate +14+14 Taildeck -annotate +554+14 FlClash \
      "$out/header-$name.png" 2> /dev/null || true
    [ -s "$out/header-$name.png" ] && note "still pair: header-$name.png"
  fi
done

note "ok: Taildeck's subpage bar and first-level collapse recorded against FlClash"
