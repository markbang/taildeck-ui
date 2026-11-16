#!/usr/bin/env bash
# Records Taildeck and FlClash doing the same gestures on one emulator: the
# language select opening, the theme page sliding in, and back, with the drag
# back. Cuts side-by-side stills and clips and checks Taildeck's own steps.
# Usage: tool/settings_flclash_record.sh <taildeck-apk> <flclash-apk> [out-dir]
set -euo pipefail

apk=${1:?usage: tool/settings_flclash_record.sh <taildeck-apk> <flclash-apk> [out-dir]}
flclash_apk=${2:?no FlClash APK}
out=${3:-settings-flclash}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
slow=${SETTINGS_SLOW:-5}
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

tap_label() { # <text>
  local point
  point=$(ui tap "$1") || return 1
  # shellcheck disable=SC2086
  adb shell input tap $point > /dev/null 2>&1 || true
  sleep 0.8
}

value_point() { # <text>: the row's value at its end, where a select opens from
  local box x1 y1 x2 y2
  box=$(ui bounds "$1") || return 1
  read -r x1 y1 x2 y2 <<< "$box"
  echo "$((x2 - 40)) $(((y1 + y2) / 2))"
}

# Stills as fast as screencap allows, to catch a transition mid-flight. The
# first capture warms the path: a cold one can trail the whole animation.
mid_stills() { # <prefix>
  adb exec-out screencap -p > /dev/null 2>&1 || true
  local i
  for i in 1 2 3 4 5 6; do
    adb exec-out screencap -p > "$out/$1-$i.png" 2> /dev/null || true
  done
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

# Records a clip while a step runs: screenrecord stops when the step ends.
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
  # ?slow= stretches the menu unfold and the page push, so the clip can show
  # their frames; the emulator itself runs with real motion.
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&tab=3&lang=en&splash=0&slow=$stretch' -n $component" \
    > "$out/launch-taildeck.txt" 2>&1 || true
  sleep 3
  dismiss_system_dialogs
  # The dock's "Settings" label is the readiness signal; the dumps can fail on
  # a busy boot, so keep trying and keep what the screen showed.
  local attempt
  for attempt in $(seq 1 20); do
    if gate_in_front "$app" && ui has Settings > /dev/null 2>&1; then
      sleep 1
      return 0
    fi
    sleep 2
  done
  note "dump: $(adb shell uiautomator dump /sdcard/ui.xml 2>&1 | tail -n 1)"
  shot taildeck-launch-fail
  ui texts "$SH" > "$out/taildeck-launch-fail.txt" 2> /dev/null || true
  note "Taildeck: no dock after 40 s, carrying on"
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

# FlClash's page push is 300 ms; Taildeck's is spring-settled, so both clips
# run long enough to hold the transition and then the page at rest. The row's
# point is resolved before the clip starts, so the tap lands in its first
# second.
theme_point= drag_point=
theme_step() {
  # The tap runs beside the captures, so the stills start before it lands.
  # shellcheck disable=SC2086
  ( adb shell input tap $theme_point > /dev/null 2>&1 || true ) &
  mid_stills taildeck-push
  wait
  sleep $((slow + 1))
}

drag_step() {
  tap_point "$1" $((slow + 2))
  adb shell input swipe "$((W / 6))" "$((SH / 2))" "$((W * 3 / 4))" "$((SH / 2))" 600 > /dev/null 2>&1 || true
  sleep $((slow + 1))
}

geometry
launch_taildeck
shot taildeck-settings
wait_for Language 15 || {
  shot taildeck-settings-fail
  fail "the settings list does not show the language select"
}
note "Taildeck settings: list with the language row"

language_point=$(value_point Language) || fail "no bounds for the language row"
language_tap() {
  # shellcheck disable=SC2086
  ( adb shell input tap $language_point > /dev/null 2>&1 || true ) &
  mid_stills taildeck-language
  wait
  sleep $((slow + 1))
}
record taildeck-language 12 language_tap
shot taildeck-language-open
ui has English > /dev/null 2>&1 || fail "the language menu did not open"
ui has 中文 > /dev/null 2>&1 || note "the language menu lists no zh entry"
back_key
sleep 1

theme_point=$(ui tap Theme) || fail "no Theme row on the settings list"
record taildeck-push 12 theme_step
shot taildeck-theme
wait_for "Theme mode" 15 || fail "the theme page did not open"
note "Taildeck theme page: preview and mode choices"

back_key
sleep 2
shot taildeck-back

# The push at a sixth of its speed, so a still can land inside it.
launch_taildeck 20
slow_point=$(ui tap Theme 2> /dev/null) || slow_point=""
if [ -n "$slow_point" ]; then
  ( adb shell input tap $slow_point > /dev/null 2>&1 || true ) &
  mid_stills taildeck-push-slow
  wait
  sleep 2
fi
back_key
sleep 2

record taildeck-drag 14 drag_step "$theme_point"
shot taildeck-drag-end
ui has "Theme mode" > /dev/null 2>&1 && note "drag back left the theme page open" ||
  note "drag back returned to the list"

# A theme choice, to show the preview and the mode rows repaint.
light_point=$(ui tap Light 2> /dev/null) || light_point=""
if [ -n "$light_point" ]; then
  record taildeck-theme-light 8 tap_point "$light_point" $((slow + 1))
fi
shot taildeck-theme-light
back_key
sleep 1
alive=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
[ -n "$alive" ] || fail "Taildeck died during the recording"
exceptions=$(adb logcat -d 2> /dev/null | grep -hE -e 'EXCEPTION CAUGHT BY' -e 'Another exception was thrown' | head -n 3 || true)
[ -z "$exceptions" ] || fail "Taildeck logged a Flutter exception: $exceptions"
note "Taildeck: alive, no Flutter exception"

# ---- FlClash -------------------------------------------------------------

# FlClash opens on its disclaimer once per install; Agree then asks for the
# no-service statement typed back before Confirm enables. The emulator's
# English locale is the statement this types.
disclaimer_statement="The Software itself does not provide any proxy server, node, subscription, or network access service, and has no partnership, agency, or guarantee relationship with any provider of such services."

accept_flclash_disclaimer() {
  local point attempt
  point=$(ui tap Agree 2> /dev/null) || point=$(ui tap 同意 2> /dev/null) || return 0
  tap_point "$point" 2
  if ui has Confirm > /dev/null 2>&1; then
    if point=$(ui edit 0 2> /dev/null); then
      tap_point "$point" 1
      # Typed once: a second pass appends to the field and never matches.
      adb shell input text "$(printf '%s' "$disclaimer_statement" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
      sleep 3
    elif point=$(ui tap "I have read" 2> /dev/null); then
      # A remote-focused build asks for a check instead of the statement.
      tap_point "$point" 1
    fi
    point=$(ui tap Confirm 2> /dev/null) && tap_point "$point" 3
    ui has Confirm > /dev/null 2>&1 && note "disclaimer: Confirm still disabled"
  fi
  ui texts "$SH" > "$out/flclash-disclaimer.txt" 2> /dev/null || true
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
  # Its dock is the last of four slots whether or not its labels reach the
  # accessibility tree.
  if wait_for Tools 20 || wait_for 工具 5; then return 0; fi
  adb shell input tap "$((W * 7 / 8))" "$((SH - 160))" > /dev/null 2>&1 || true
  sleep 2
  shot flclash-dock
  ui texts "$SH" > "$out/flclash-dock.txt" 2> /dev/null || true
  ui has Language > /dev/null 2>&1 || ui has Theme > /dev/null 2>&1
}

open_tools() {
  if tap_label Tools || tap_label 工具; then
    sleep 2
    return 0
  fi
  adb shell input tap "$((W * 7 / 8))" "$((SH - 160))" > /dev/null 2>&1 || true
  sleep 2
  ui texts "$SH" > "$out/flclash-tools.txt" 2> /dev/null || true
  ui has Language > /dev/null 2>&1 || ui has Theme > /dev/null 2>&1
}

flclash_theme_step() {
  # Its push is 300 ms, shorter than a screencap; the clip's third frame holds
  # the middle of it.
  # shellcheck disable=SC2086
  ( adb shell input tap $1 > /dev/null 2>&1 || true ) &
  sleep 3
  wait
}
flclash_drag_step() {
  tap_point "$1" 3
  adb shell input swipe "$((W / 6))" "$((SH / 2))" "$((W * 3 / 4))" "$((SH / 2))" 600 > /dev/null 2>&1 || true
  sleep 3
}

adb install -g "$flclash_apk" > "$out/install-flclash.txt" 2>&1 || note "FlClash install failed, see install-flclash.txt"
if launch_flclash; then
  shot flclash-home
  if open_tools; then
    shot flclash-tools
    ui texts "$SH" > "$out/flclash-tools.txt" 2> /dev/null || true
    wait_for Language 15 && note "FlClash tools: language select found" ||
      note "FlClash tools: no language row in the dump"
    language_point=$(value_point Language 2> /dev/null) || language_point=""
    if [ -n "$language_point" ]; then
      record flclash-language 12 tap_point "$language_point"
    else
      record flclash-language 12 tap_label Language
    fi
    # Its unfold is short: the clip holds the middle of it.
    ffmpeg -loglevel error -y -i "$out/flclash-language.mp4" -vf "select='eq(n,1)'" \
      -frames:v 1 "$out/flclash-language-2.png" 2> /dev/null || true
    shot flclash-language-open
    back_key
    sleep 1
    flclash_theme_point=$(ui tap Theme 2> /dev/null) || flclash_theme_point=""
    if [ -n "$flclash_theme_point" ]; then
      record flclash-push 12 flclash_theme_step "$flclash_theme_point"
      ffmpeg -loglevel error -y -i "$out/flclash-push.mp4" -vf "select='eq(n,2)'" \
        -frames:v 1 "$out/flclash-push-3.png" 2> /dev/null || true
      shot flclash-theme
      wait_for "Theme mode" 15 && note "FlClash theme page: mode rows found" ||
        note "FlClash theme page: no 'Theme mode' in the dump"
      back_key
      sleep 2
      shot flclash-back
      record flclash-drag 14 flclash_drag_step "$flclash_theme_point"
      shot flclash-drag-end
    else
      note "FlClash: no Theme row on its tools page"
    fi
  else
    note "FlClash: no Tools tab"
  fi
  adb logcat -d 2> /dev/null | grep -i "follow.clash" | tail -20 >> "$summary" || true
else
  note "FlClash never showed its Tools tab; only Taildeck is recorded"
fi

# ---- side by side --------------------------------------------------------

# The encoder on a loaded emulator can hold the first frames back for a few
# seconds, so both clips start a moment before their first real change.
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
    -filter_complex '[0:v]scale=540:-2,setsar=1[l];[1:v]scale=540:-2,setsar=1[r];[l][r]hstack=inputs=2,drawtext=text=Taildeck:x=14:y=14:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5,drawtext=text=FlClash:x=554:y=14:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5' \
    -an "$out/$name.mp4" 2> /dev/null || true
  [ -s "$out/$name.mp4" ] && note "side by side $name: $out/$name.mp4" || note "side by side $name: none"
}

side_by_side settings-flclash-language taildeck-language flclash-language 5
side_by_side settings-flclash-theme taildeck-push flclash-push 5
side_by_side settings-flclash-drag taildeck-drag flclash-drag 6

# Still pairs for the pull request.
for pair in \
  "settings:taildeck-settings:flclash-tools" \
  "language:taildeck-language-open:flclash-language-open" \
  "theme:taildeck-theme:flclash-theme" \
  "push:taildeck-push-slow-3:flclash-push-3" \
  "popup:taildeck-language-3:flclash-language-2"; do
  name=${pair%%:*}
  rest=${pair#*:}
  td=${rest%%:*}
  fl=${rest#*:}
  if [ -s "$out/$td.png" ] && [ -s "$out/$fl.png" ]; then
    convert "$out/$td.png" -resize 540x "$out/td-$name.png" 2> /dev/null || true
    convert "$out/$fl.png" -resize 540x "$out/fl-$name.png" 2> /dev/null || true
    convert "$out/td-$name.png" "$out/fl-$name.png" +append \
      -gravity northwest -annotate +14+14 Taildeck -annotate +554+14 FlClash \
      "$out/settings-flclash-$name.png" 2> /dev/null || true
    [ -s "$out/settings-flclash-$name.png" ] && note "still pair: settings-flclash-$name.png"
  fi
done

ffmpeg -loglevel error -y -i "$out/taildeck-push.mp4" -vf "fps=10,scale=270:-2" \
  "$out/frames-%03d.png" 2> /dev/null || true

note "ok: Taildeck's select, push, back and drag back recorded against FlClash"
