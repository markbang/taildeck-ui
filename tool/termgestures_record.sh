#!/usr/bin/env bash
# Records the terminal's gesture and keyboard layer on the emulator: swipe
# arrows, a held arrow key, pinch zoom, selection with copy and open-link,
# paste, the soft keyboard resize, landscape and hardware keys. Media
# problems are reported, never failed.
# Usage: tool/termgestures_record.sh <flutter-apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/termgestures_record.sh <flutter-apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-termgestures}
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
# The emulator reports a physical keyboard, which hides the IME by default.
adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true

density=$(adb shell wm density 2> /dev/null | sed -n 's/.*Physical density: \([0-9]*\).*/\1/p' | tr -d '\r')
density=${density:-420}
dp() { awk -v value="$1" -v dpi="$density" 'BEGIN { printf "%d", value * dpi / 160 }'; }

dump() {
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
}

ui() { # <tap|has|text|bounds> <needle>
  local attempt
  for attempt in 1 2 3; do
    dump
    if python3 tool/ui.py "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

scroll_to() { # <needle> [tries]
  local attempt point
  for attempt in $(seq 1 "${2:-8}"); do
    if point=$(ui tap "$1"); then
      echo "$point"
      return 0
    fi
    adb shell input swipe 540 1700 540 900 300 > /dev/null 2>&1 || true
    sleep 1
  done
  return 1
}

shot() { # <name>
  adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"
  [ -s "$out/$1.png" ] && note "$1: $(stat -c%s "$out/$1.png") bytes"
}

record() { # <name> <seconds> <shell function>
  local name=$1 seconds=$2 action=$3
  adb shell pkill -f screenrecord > /dev/null 2>&1 || true
  sleep 0.7
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$((seconds + 2))" --bit-rate 8000000 \
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

install_app() {
  adb uninstall "$app" > /dev/null 2>&1 || true
  adb install -g "$1" > "$out/install.txt" 2>&1 || { note "install failed, see install.txt"; return 1; }
}

demo_url="taildeck://preview/?preview=1&ssh=demo&lang=en"
settings_url="taildeck://preview/?preview=1&tab=3&lang=en"

# ---- grid geometry from the a11y tree -----------------------------------
# The grid is one semantics node; its header carries "libghostty-vt · N×M".
grid_cells() { # prints "N M"
  local text
  text=$(ui text 'libghostty-vt') || return 1
  echo "$text" | sed -n 's/.*[·] *\([0-9][0-9]*\)×\([0-9][0-9]*\).*/\1 \2/p'
}

grid_box() { # prints "x1 y1 x2 y2"
  ui bounds 'Terminal output'
}

cell() { # <col> <row> -> "x y" in screen pixels
  local col=$1 row=$2 gx1 gy1 gx2 gy2 n m
  read -r gx1 gy1 gx2 gy2 <<< "$(grid_box)" || return 1
  read -r n m <<< "$(grid_cells)" || return 1
  awk -v c="$col" -v r="$row" -v x1="$gx1" -v y1="$gy1" -v x2="$gx2" -v y2="$gy2" \
    -v n="$n" -v m="$m" \
    'BEGIN { printf "%d %d", x1 + (c + 0.5) * (x2 - x1) / n, y1 + (r + 0.5) * (y2 - y1) / m }'
}

last_rows() { # prints "N M" and the row index of the demo URL line (M-3)
  local n m
  read -r n m <<< "$(grid_cells)" || return 1
  echo "$n $m"
}

double_tap() { adb shell "input tap $1 $2; input tap $1 $2" > /dev/null 2>&1 || true; }
long_press() { adb shell input swipe "$1" "$2" "$1" "$2" "${3:-1200}" > /dev/null 2>&1 || true; }
swipe_on_grid() { adb shell input swipe "$1" "$2" "$3" "$4" "${5:-400}" > /dev/null 2>&1 || true; }

# ---- one finger per device, two for a pinch ------------------------------
mt_devices() { # prints "device kind" for every multi-touch device
  adb shell getevent -pl 2> /dev/null | awk '
    /^add device/ { if (dev != "") print dev, mt ? (slot ? "slot" : "plain") : "none"; dev = $4; mt = 0; slot = 0 }
    /ABS_MT_POSITION_X/ { mt = 1 }
    /ABS_MT_SLOT/ { slot = 1 }
    END { if (dev != "") print dev, mt ? (slot ? "slot" : "plain") : "none" }' \
    | awk '$2 != "none"'
}

pinch() { # <out|in> [centre "x y"]
  local mode=${1:-out} centre=${2:-} cx cy w h
  local devices first second kind
  mapfile -t devices < <(mt_devices)
  if [ "${#devices[@]}" -eq 0 ]; then
    note "pinch: no multi-touch device, not injected"
    return 0
  fi
  if [ -z "$centre" ]; then
    read -r cx cy <<< "$(cell 20 10)" || return 0
  else
    read -r cx cy <<< "$centre"
  fi
  local near=40 far=300 step i d script=""
  if [ "$mode" = "in" ]; then near=300; far=40; fi
  if [ "${#devices[@]}" -ge 2 ]; then
    first=${devices[0]%% *}
    second=${devices[1]%% *}
    note "pinch: two devices $first $second"
    for i in $(seq 0 11); do
      d=$((near + (far - near) * i / 11))
      script+="sendevent $first 3 57 1; sendevent $first 3 53 $((cx - d)); sendevent $first 3 54 $cy; sendevent $first 0 0 0; "
      script+="sendevent $second 3 57 2; sendevent $second 3 53 $((cx + d)); sendevent $second 3 54 $cy; sendevent $second 0 0 0; sleep 0.04; "
    done
    script+="sendevent $first 3 57 -1; sendevent $first 0 0 0; sendevent $second 3 57 -1; sendevent $second 0 0 0"
  else
    first=${devices[0]%% *}
    kind=${devices[0]##* }
    note "pinch: device $first ($kind)"
    for i in $(seq 0 11); do
      d=$((near + (far - near) * i / 11))
      script+="sendevent $first 3 47 0; sendevent $first 3 57 1; sendevent $first 3 53 $((cx - d)); sendevent $first 3 54 $cy; "
      if [ "$kind" = "slot" ]; then
        script+="sendevent $first 3 47 1; sendevent $first 3 57 2; sendevent $first 3 53 $((cx + d)); sendevent $first 3 54 $cy; "
      fi
      script+="sendevent $first 0 0 0; sleep 0.04; "
    done
    script+="sendevent $first 3 57 -1; sendevent $first 0 0 0"
  fi
  if ! adb shell "$script" > "$out/pinch.txt" 2>&1; then
    note "pinch: sendevent failed, see pinch.txt"
  fi
}

# ---- hardware keys -------------------------------------------------------
keyboard_device() {
  adb shell getevent -pl 2> /dev/null | awk '
    /^add device/ { dev = $4 }
    /KEY_LEFTCTRL/ { print dev; exit }'
}

ctrl_c() {
  if adb shell input keycombination 113 31 > /dev/null 2>&1; then
    note "ctrl-c: input keycombination"
    return 0
  fi
  local device
  device=$(keyboard_device) || true
  if [ -z "${device:-}" ]; then
    note "ctrl-c: no keyboard device, not injected"
    return 0
  fi
  adb shell "sendevent $device 1 29 1; sendevent $device 0 0 0; sendevent $device 1 46 1; sendevent $device 0 0 0; sendevent $device 1 46 0; sendevent $device 0 0 0; sendevent $device 1 29 0; sendevent $device 0 0 0" \
    > /dev/null 2>&1 || note "ctrl-c: sendevent failed"
  note "ctrl-c: sendevent on $device"
}

# ---- actions -------------------------------------------------------------
pinch_out() { pinch out; }
landscape() { rotate 1; }
title='Key row with a hardware keyboard'

enable_key_row() {
  # The emulator has a physical keyboard, so the row hides by default. The
  # row's own label is a semantics action, not a pointer target: tap the
  # switch at its right edge.
  launch "$settings_url" || return 0
  local x1 y1 x2 y2 x y
  if ! scroll_to "$title" > /dev/null; then
    note "key row with a hardware keyboard: row not found"
    return 0
  fi
  read -r x1 y1 x2 y2 <<< "$(ui bounds "$title")" || return 0
  x=$((x2 - $(dp 22)))
  y=$(((y1 + y2) / 2))
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 2
  if ui has ', on' > /dev/null 2>&1; then
    note "key row with a hardware keyboard: on"
  else
    note "key row with a hardware keyboard: tapped at $x,$y, state unreadable"
  fi
}

prepare_ime() {
  adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true
  local imes
  imes=$(adb shell ime list -s 2> /dev/null | tr -d '\r')
  if [ -z "$imes" ]; then
    adb shell ime enable com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME > /dev/null 2>&1 || true
    adb shell ime set com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME > /dev/null 2>&1 || true
    imes=$(adb shell ime list -s 2> /dev/null | tr -d '\r')
  fi
  note "ime: ${imes:-none}"
  note "show_ime_with_hard_keyboard: $(adb shell settings get secure show_ime_with_hard_keyboard | tr -d '\r')"
}

swipe_step() {
  read -r x1 y1 <<< "$(cell 20 8)"
  read -r x2 y2 <<< "$(cell 40 8)"
  swipe_on_grid "$x1" "$y1" "$x2" "$y1" 300
  sleep 1
  read -r x3 y3 <<< "$(cell 20 10)"
  read -r x4 y4 <<< "$(cell 20 14)"
  swipe_on_grid "$x3" "$y3" "$x3" "$y4" 300
  sleep 1.5
}

hold_arrow() {
  local point
  point=$(ui tap 'Left arrow') || point=""
  if [ -z "$point" ]; then
    note "hold-arrow: no Left arrow key"
    return 0
  fi
  read -r x y <<< "$point"
  long_press "$x" "$y" 1400
  sleep 1.5
}

select_word() {
  local n m row
  read -r n m <<< "$(last_rows)" || return 0
  row=$((m - 2))
  read -r x y <<< "$(cell 6 "$row")"
  double_tap "$x" "$y"
  sleep 1.5
  note "selection: double tap at $x,$y (row $row of $m)"
}

copy_selection() {
  local point
  point=$(ui tap 'Copy') || point=""
  if [ -z "$point" ]; then
    note "copy: no Copy action, the toolbar is missing"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 0.8
  shot copy-flash
  if ui has 'Copied' > /dev/null 2>&1; then
    note "copy: verified (toolbar reads Copied)"
  else
    note "copy: check copy-flash.png"
  fi
}

paste_clipboard() {
  local point
  point=$(ui tap 'Paste') || point=$(ui tap 'paste') || point=""
  if [ -z "$point" ]; then
    note "paste: no Paste action"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 1.5
}

open_link() {
  select_word
  sleep 0.5
  local point
  point=$(ui tap 'Open link') || point=""
  if [ -z "$point" ]; then
    note "open-link: no Open link action on the URL"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 6
  shot open-link
  if ui has 'tailscale' > /dev/null 2>&1; then
    note "open-link: verified (a browser page shows the link)"
  else
    note "open-link: check open-link.png"
  fi
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 2
}

ime_state() {
  adb shell dumpsys input_method 2> /dev/null | grep -o 'mInputShown=[a-z]*' | head -1 || true
}

show_keyboard() {
  local point x y
  point=$(ui tap 'Type a command') || point=""
  if [ -z "$point" ]; then
    note "keyboard: no input line"
    return 0
  fi
  adb shell dumpsys input_method > "$out/input-method.txt" 2> /dev/null || true
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 3
  shot keyboard-shown
  note "keyboard: $(ime_state) after tapping $x,$y"
  note "keyboard: grid $(grid_cells || echo unknown)"
}

hide_keyboard() {
  # Back closes the IME; without one it would leave the terminal page.
  if [ "$(ime_state)" != "mInputShown=true" ]; then
    note "keyboard-hide: no IME to close"
    return 0
  fi
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 2.5
  shot keyboard-hidden
  note "keyboard-hide: grid $(grid_cells || echo unknown)"
}

rotate() { # <0|1>
  adb shell settings put system accelerometer_rotation 0 > /dev/null 2>&1 || true
  adb shell settings put system user_rotation "$1" > /dev/null 2>&1 || true
  sleep 3
}

hardware_keys() {
  adb shell input keyevent KEYCODE_TAB > /dev/null 2>&1 || true
  sleep 0.4
  adb shell input keyevent KEYCODE_ESCAPE > /dev/null 2>&1 || true
  sleep 0.4
  adb shell input keyevent KEYCODE_DPAD_LEFT KEYCODE_DPAD_UP > /dev/null 2>&1 || true
  sleep 0.4
  ctrl_c
  sleep 1.5
}

# ---- run -----------------------------------------------------------------
install_app "$apk" || exit 0
adb shell getevent -pl > "$out/getevent.txt" 2>&1 || true
prepare_ime
enable_key_row

launch "$demo_url" || exit 0
if ui has 'Extra key row' > /dev/null 2>&1; then
  note "terminal page: key row present"
else
  note "terminal page: no key row"
fi
shot grid-initial
grid_cells | sed 's/^/grid before: /' | tee -a "$summary" || true

# 1. swipe arrows, both axes
record swipe-arrows 8 swipe_step
shot swipe-arrows

# 2. a held arrow key repeats
record hold-arrow 8 hold_arrow
shot hold-arrow

# 3. pinch zoom, then the persisted size
before=$(grid_cells || true)
record pinch 10 pinch_out
shot pinch-out
after=$(grid_cells || true)
note "pinch: grid $before -> $after"
launch "$settings_url" || true
font=$(ui text 'pinch the grid' || true)
note "pinch: settings reads ${font:-nothing}"
launch "$demo_url" || true
note "pinch: grid after relaunch $(grid_cells || echo unknown)"

# 4. selection, copy and paste
record selection 10 select_word
shot selection
record copy 7 copy_selection
shot copy
record paste 8 paste_clipboard
shot paste

# 5. open the link a selection holds
record open-link 12 open_link

# 6. landscape, then back to portrait
record landscape 9 landscape
shot landscape
note "landscape: grid $(grid_cells || echo unknown)"
rotate 0
sleep 2
if ! ui has 'Terminal output' > /dev/null 2>&1; then
  note "landscape: terminal page lost, relaunching"
  launch "$demo_url" || true
fi
note "portrait: grid $(grid_cells || echo unknown)"

# 7. soft keyboard show and hide
record keyboard 11 show_keyboard
record keyboard-hide 9 hide_keyboard

# 8. hardware keys
if ! ui has 'Terminal output' > /dev/null 2>&1; then
  launch "$demo_url" || true
fi
record hardware 10 hardware_keys
shot hardware

note "ok: terminal gestures recorded"
