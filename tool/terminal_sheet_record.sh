#!/usr/bin/env bash
# Records the terminal sheet before and after the 2026-11-16 redesign, on the
# Android emulator against a real SSH shell from the runner's test tailnet:
# the old header, input line and quick-command row from v0.2.18, then the new
# grabber, title bar, floating capsule, tap-does-nothing, keyboard button,
# Compose with Chinese text, toolbar controls, and the light theme. Also builds
# a still against the described reference layout. Recording problems are
# reported, never failed; the tap gate lives in tool/termtap_record.sh.
# Usage: tool/terminal_sheet_record.sh <new.apk> [app-id] [out-dir] [old.apk]
set -euo pipefail

apk=${1:?usage: tool/terminal_sheet_record.sh <new.apk> [app-id] [out-dir] [old.apk]}
app=${2:-top.bangwu.taildeck}
out=${3:-sheet}
old=${4:-}
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-tskey-test}
peer=${PEER:-motionpeer}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
adb shell settings put global stay_on_while_plugged_in 3 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true
sleep 15
adb shell input keyevent 82 > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true

dump() {
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
}

ui() { # <tap|has|text|bounds|edit> <needle>
  local attempt
  for attempt in 1 2 3; do
    dump
    if python3 tool/ui.py "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

tap_xy() {
  # shellcheck disable=SC2086
  adb shell input tap $1 > /dev/null 2>&1 || true
  sleep 0.8
}

tap_label() {
  local point
  point=$(ui tap "$1") || return 1
  tap_xy "$point"
}

ime_state() {
  adb shell dumpsys input_method 2> /dev/null | grep -o 'mInputShown=[a-z]*' | head -1 || true
}

hide_ime() {
  [ "$(ime_state)" = "mInputShown=true" ] || return 0
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 1.5
}

type_text() {
  adb shell input text "$(printf '%s' "$1" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
  sleep 0.4
}

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }

record() { # <name> <seconds> <function>
  local name=$1 seconds=$2 action=$3
  adb shell pkill -f screenrecord > /dev/null 2>&1 || true
  sleep 0.6
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

grid_box() { ui bounds 'Terminal output'; }

tap_grid() { # <fx> <fy>, both 0..1
  local fx=$1 fy=$2 box x1 y1 x2 y2 x y
  box=$(grid_box) || { note "no grid bounds"; return 1; }
  read -r x1 y1 x2 y2 <<< "$box"
  x=$(awk -v f="$fx" -v a="$x1" -v b="$x2" 'BEGIN { printf "%d", a + f * (b - a) }')
  y=$(awk -v f="$fy" -v a="$y1" -v b="$y2" 'BEGIN { printf "%d", a + f * (b - a) }')
  tap_xy "$x $y"
}

scroll_down() {
  local w h
  read -r w h <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  adb shell input swipe "$(( ${w:-1080} / 2 ))" "$(( ${h:-2400} * 3 / 4 ))" \
    "$(( ${w:-1080} / 2 ))" "$(( ${h:-2400} / 2 ))" 300 > /dev/null 2>&1 || true
  sleep 0.8
}

find_or_scroll() {
  local point tries=${2:-4}
  point=$(ui tap "$1") && { echo "$point"; return 0; }
  while [ "$tries" -gt 0 ]; do
    scroll_down
    point=$(ui tap "$1") && { echo "$point"; return 0; }
    tries=$((tries - 1))
  done
  return 1
}

fill_edit() { # <index> <value>
  local point
  point=$(ui edit "$1") || { note "no text field $1"; return 1; }
  tap_xy "$point"
  type_text "$2"
  hide_ime
}

wait_for() { # <marker> <seconds>
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    ui has "$1" > /dev/null 2>&1 && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

launch() { # [url]
  local url=${1:-} attempt resumed
  for attempt in 1 2 3; do
    adb shell am force-stop "$app" > /dev/null 2>&1 || true
    sleep 1
    if [ -n "$url" ]; then
      adb shell "am start -W -a android.intent.action.VIEW -d '$url' '$app'" > /dev/null 2>&1 || true
    else
      adb shell monkey -p "$app" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
    fi
    sleep 5
    resumed=$(adb shell dumpsys activity activities 2> /dev/null \
      | grep -m1 -E 'mResumedActivity|topResumedActivity' || true)
    case "$resumed" in
      *"$app"*) return 0 ;;
    esac
    note "launch attempt $attempt: ${resumed:-no resumed activity}"
    sleep 3
  done
  note "launch failed"
  return 1
}

sign_in() {
  [ -n "$control_url" ] || { note "no control server: cannot reach a shell"; return 1; }
  if ui has "Nodes" > /dev/null 2>&1; then
    note "sign-in: already signed in"
    return 0
  fi
  local point
  point=$(find_or_scroll "Control server") || { note "sign-in: no control-server row"; return 1; }
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$control_url" || return 1
  point=$(find_or_scroll "Use an auth key") || return 1
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$auth_key" || return 1
  point=$(find_or_scroll "Connect") || return 1
  tap_xy "$point"
  wait_for "Nodes" 45 || { note "sign-in: still on the login screen"; return 1; }
  note "sign-in: node up, control $control_url"
}

open_session() {
  local node=$1 point
  point=$(find_or_scroll "$node") || { note "$node: not in the node list"; return 1; }
  tap_xy "$point"
  sleep 1.5
  point=$(find_or_scroll "SSH") || { note "$node: no SSH action"; return 1; }
  tap_xy "$point"
  sleep 1.5
  point=$(find_or_scroll "Connect") || { note "$node: no Connect button"; return 1; }
  tap_xy "$point"
  wait_for "Terminal output" 30 || { note "$node: the terminal did not open"; return 1; }
  note "$node: SSH session up"
}

# ---- the old sheet (v0.2.18) ---------------------------------------------
old_open() { open_session "$peer"; }
old_tap() {
  hide_ime
  tap_grid 0.4 0.35
  sleep 3
  shot sheet-before-keyboard
}

# ---- the new sheet --------------------------------------------------------
new_open() { open_session "$peer"; }

new_tap() {
  hide_ime
  tap_grid 0.4 0.35
  sleep 3
  [ "$(ime_state)" = "mInputShown=true" ] && note "tap: the IME came up"
  shot sheet-tap
}

new_keyboard() {
  hide_ime
  tap_label 'Show keyboard' || { note "keyboard: no Show keyboard button"; return 1; }
  sleep 3
  shot sheet-keyboard
  [ "$(ime_state)" = "mInputShown=true" ] || note "keyboard: the button did not show the IME"
  tap_label 'Hide keyboard' || { note "keyboard: no Hide keyboard button"; return 1; }
  sleep 2
  [ "$(ime_state)" = "mInputShown=true" ] && note "keyboard: the button did not hide the IME"
}

new_toolbar() {
  tap_label 'Arrow keys and more' || { note "toolbar: no d-pad"; return 1; }
  sleep 1.2
  shot sheet-arrows
  tap_label 'Control' || note "toolbar: no Control key"
  sleep 0.6
  tap_label 'Left arrow' || note "toolbar: no Left arrow"
  sleep 0.8
  tap_label 'Arrow keys and more' || true
  sleep 0.8
  tap_label 'Snippets' || note "toolbar: no Snippets button"
  sleep 1.5
  shot sheet-snippets
  tap_label 'Close' || true
  sleep 1
  tap_label 'Insert from clipboard' || note "toolbar: no Paste button"
  sleep 1
}

compose_flow() {
  tap_label 'Compose' || { note "compose: no Compose button"; return 1; }
  sleep 2
  shot sheet-compose
  tap_label 'Send' || { note "compose: no Send button"; return 1; }
  sleep 3
  shot sheet-compose-sent
}

light_flow() {
  hide_ime
  tap_grid 0.5 0.4
  sleep 1.5
  shot sheet-light
}

# ---- run -----------------------------------------------------------------
if [ -n "$old" ] && [ -s "$old" ]; then
  adb install -r -d -g "$old" > "$out/install-old.txt" 2>&1 \
    || note "old APK install failed, see install-old.txt"
  if launch; then
    sign_in || true
    record sheet-before-open 25 old_open
    record sheet-before-tap 14 old_tap
    shot sheet-before
  fi
fi

# The published APK is release-signed, this one is profile/debug-signed: the
# old build has to go before the new one can be installed.
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -r -g "$apk" > "$out/install.txt" 2>&1 || { note "install failed, see install.txt"; exit 0; }
launch || { note "cannot launch the app"; exit 0; }
sign_in || true
record sheet-open 25 new_open
shot sheet-dark
record sheet-tap 10 new_tap
record sheet-keyboard 14 new_keyboard
record sheet-toolbar 16 new_toolbar

compose_url="taildeck://preview/?compose=echo%20%E4%BD%A0%E5%A5%BD%EF%BC%8C%E7%BB%88%E7%AB%AF"
launch "$compose_url" || note "compose launch failed"
sign_in || true
open_session "$peer" || true
record sheet-compose 18 compose_flow

launch "taildeck://preview/?theme=light" || note "light launch failed"
sign_in || true
open_session "$peer" || true
record sheet-light 10 light_flow

# ---- stills against the described layout ---------------------------------
if [ -s "$out/sheet-dark.png" ]; then
  ref="$out/reference-described.png"
  convert -size 360x780 'xc:#0b0d11' \
    -fill '#1a1e26' -stroke '#3a4150' -strokewidth 1 \
    -draw 'roundrectangle 40,14 320,26 6,6' \
    -draw 'line 20,54 340,54' \
    -draw 'circle 40,44 46,44' \
    -draw 'roundrectangle 52,36 72,52 4,4' \
    -draw 'line 20,70 340,70' \
    -draw 'roundrectangle 16,742 344,772 15,15' \
    -fill '#8b93a1' -stroke none -pointsize 11 \
    -font DejaVu-Sans \
    -draw "text 150,44 'user: node'" \
    -draw "text 282,46 'SSH'" \
    -draw "text 24,96 'terminal grid, mono + CJK'" \
    -draw "text 26,756 'Ctrl  Esc  Tab  dpad  snippets  paste  Compose  keyboard'" \
    "$ref" 2> /dev/null || true
  if [ -s "$ref" ]; then
    montage "$out/sheet-dark.png" "$ref" -tile 2x1 -geometry 360x780+10+0 \
      -background '#07080a' "$out/sheet-structure.png" 2> /dev/null || true
    note "sheet-structure.png: new sheet | described reference layout"
  fi
  if [ -s "$out/sheet-before.png" ]; then
    montage "$out/sheet-before.png" "$out/sheet-dark.png" -tile 2x1 \
      -geometry 360x780+10+0 -background '#07080a' \
      "$out/sheet-before-after.png" 2> /dev/null || true
    note "sheet-before-after.png: v0.2.18 | this build"
  fi
fi

note "sheet: recordings and stills are in $out/"
