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

scroll_clear() { # <needle> [tries]: keep the target above the floating dock
  local needle=$1 tries=${2:-24} attempt point x y height
  height=$(adb shell wm size 2> /dev/null | sed -n 's/.*: [0-9]*x\([0-9]*\).*/\1/p' | tr -d '\r')
  height=${height:-2400}
  for attempt in $(seq 1 "$tries"); do
    if point=$(ui tap "$needle"); then
      read -r x y <<< "$point"
      if [ "$y" -lt $((height - $(dp 170))) ]; then
        echo "$point"
        return 0
      fi
    fi
    adb shell input swipe 540 1500 540 1150 200 > /dev/null 2>&1 || true
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

demo_url="taildeck://preview/?preview=1&ssh=demo&lang=en&keys=1"
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

# ---- root only for the pinch --------------------------------------------
root_on() { adb root > /dev/null 2>&1 || true; adb wait-for-device; }
root_off() { adb unroot > /dev/null 2>&1 || true; adb wait-for-device; }

mindev() { # <device-name> -> /dev/input/eventN
  adb shell getevent -pl 2> /dev/null | awk -v want="$1" '
    /^add device/ { dev = $4 }
    /name:/ { if (index($0, "\"" want "\"") > 0) { print dev; exit } }'
}

# Each virtio finger reports positions over 0..32767, not screen pixels. The
# emulator can be read as one device with two contact slots or as one device
# per finger; the run tries both and keeps the one that zooms.
pinch() { # <out|in> <slots|devices> [centre "x y"]
  local mode=${1:-out} scheme=${2:-slots} centre=${3:-}
  local cx cy w h dev1 dev2 i d script=""
  dev1=$(mindev virtio_input_multi_touch_1)
  dev2=$(mindev virtio_input_multi_touch_2)
  dev1=${dev1:-/dev/input/event2}
  dev2=${dev2:-/dev/input/event3}
  if [ -z "$centre" ]; then
    read -r cx cy <<< "$(cell 20 10)" || return 0
  else
    read -r cx cy <<< "$centre"
  fi
  read -r w h <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  w=${w:-1080}
  h=${h:-2400}
  local near=90 far=330
  if [ "$mode" = "in" ]; then near=330; far=90; fi
  scale() { awk -v v="$1" -v max="$2" -v span="$3" 'BEGIN { printf "%d", v * max / span }'; }
  local sx1 sx2 sy
  for i in $(seq 0 11); do
    d=$((near + (far - near) * i / 11))
    sx1=$(scale $((cx - d)) 32767 "$w")
    sx2=$(scale $((cx + d)) 32767 "$w")
    sy=$(scale "$cy" 32767 "$h")
    if [ "$scheme" = "slots" ]; then
      [ "$i" -eq 0 ] && script+="sendevent $dev1 1 330 1; "
      script+="sendevent $dev1 3 47 0; sendevent $dev1 3 57 1; sendevent $dev1 3 53 $sx1; sendevent $dev1 3 54 $sy; sendevent $dev1 3 48 5; sendevent $dev1 3 58 50; sendevent $dev1 0 0 0; "
      script+="sendevent $dev1 3 47 1; sendevent $dev1 3 57 2; sendevent $dev1 3 53 $sx2; sendevent $dev1 3 54 $sy; sendevent $dev1 3 48 5; sendevent $dev1 3 58 50; sendevent $dev1 0 0 0; sleep 0.04; "
    else
      script+="sendevent $dev1 3 47 0; sendevent $dev1 3 57 1; sendevent $dev1 3 53 $sx1; sendevent $dev1 3 54 $sy; sendevent $dev1 3 48 5; sendevent $dev1 0 0 0; "
      script+="sendevent $dev2 3 47 0; sendevent $dev2 3 57 2; sendevent $dev2 3 53 $sx2; sendevent $dev2 3 54 $sy; sendevent $dev2 3 48 5; sendevent $dev2 0 0 0; sleep 0.04; "
    fi
  done
  if [ "$scheme" = "slots" ]; then
    script+="sendevent $dev1 3 47 0; sendevent $dev1 3 57 -1; sendevent $dev1 3 47 1; sendevent $dev1 3 57 -1; sendevent $dev1 1 330 0; sendevent $dev1 0 0 0"
  else
    script+="sendevent $dev1 3 57 -1; sendevent $dev1 0 0 0; sendevent $dev2 3 57 -1; sendevent $dev2 0 0 0"
  fi
  note "pinch: $mode ($scheme) around $cx,$cy on $dev1 $dev2"
  if ! adb shell "$script" > "$out/pinch.txt" 2>&1; then
    note "pinch: sendevent failed, see pinch.txt"
  fi
}

pinch_only() { # <scheme>
  pinch out "${1:-slots}"
  sleep 0.6
  pinch in "${1:-slots}"
}

pinch_slots() { pinch_only slots; }

raw_tap() { # one contact through the touch device, no InputManager
  local dev cx cy w h sx sy
  dev=$(mindev virtio_input_multi_touch_1)
  dev=${dev:-/dev/input/event2}
  read -r cx cy <<< "$(cell 30 20)" || return 0
  read -r w h <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  sx=$(awk -v v="$cx" -v max=32767 -v span="${w:-1080}" 'BEGIN { printf "%d", v * max / span }')
  sy=$(awk -v v="$cy" -v max=32767 -v span="${h:-2400}" 'BEGIN { printf "%d", v * max / span }')
  adb shell "sendevent $dev 1 330 1; sendevent $dev 3 47 0; sendevent $dev 3 57 1; sendevent $dev 3 53 $sx; sendevent $dev 3 54 $sy; sendevent $dev 3 48 5; sendevent $dev 3 58 50; sendevent $dev 0 0 0; sleep 0.1; sendevent $dev 3 57 -1; sendevent $dev 1 330 0; sendevent $dev 0 0 0" > "$out/raw-tap.txt" 2>&1 || true
}

raw_probe() { # root, one contact, unroot: the copy selection is still up
  root_on
  raw_tap
  sleep 1
  root_off
  sleep 1
  if ui has 'Copy' > /dev/null 2>&1; then
    note "raw touch: an injected contact did not reach the app"
  else
    note "raw touch: an injected contact reached the app (selection cleared)"
  fi
}

pinch_step() {
  local before after
  before=$(grid_cells || true)
  root_on
  record pinch 12 pinch_slots || true
  root_off
  sleep 1
  after=$(grid_cells || true)
  if [ "$before" = "$after" ]; then
    root_on
    pinch_only devices
    root_off
    sleep 1
    after=$(grid_cells || true)
    note "pinch: second scheme (one device per finger)"
  fi
  note "pinch: grid $before -> ${after:-unknown}"
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
landscape() { rotate 1; }
title='Key row with a hardware keyboard'

settings_shot() {
  # The emulator reports a physical keyboard, so the row hides by default; the
  # preview's ?keys=1 keeps it for the recording. Settings still shows the
  # switch that a phone owner would use.
  launch "$settings_url" || return 0
  if scroll_clear "$title" > /dev/null; then
    shot settings-row
    note "settings: the key row switch and the font size are on screen"
  else
    note "settings: the key row switch did not come into view"
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

select_until() { # <toolbar label> [max rows up]
  local label=$1 tries=${2:-12} n m row attempt x y
  read -r n m <<< "$(last_rows)" || return 1
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    [ "$attempt" -gt "$tries" ] && break
    row=$((m - attempt))
    [ "$row" -lt 1 ] && break
    read -r x y <<< "$(cell 6 "$row")"
    double_tap "$x" "$y"
    sleep 1.2
    if ui has "$label" > /dev/null 2>&1; then
      note "selection: double tap at $x,$y (row $row of $m)"
      return 0
    fi
  done
  note "selection: nothing selectable in the last $tries rows of $m"
  return 1
}

select_word() {
  select_until 'Copy'
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
  select_until 'Open link' 14 || return 0
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
  local wizard
  if wizard=$(ui tap 'Use without an account'); then
    read -r wx wy <<< "$wizard"
    adb shell input tap "$wx" "$wy" > /dev/null 2>&1 || true
    sleep 5
  fi
  shot open-link
  local resumed
  resumed=$(adb shell dumpsys activity activities 2> /dev/null \
    | grep -m1 -o 'topResumedActivity=[^ ]* [^/]*/[^ ]*' || true)
  case "$resumed" in
    *chrome*|*Chrome*) note "open-link: verified (Chrome is in front: $resumed)" ;;
    *) note "open-link: check open-link.png ($resumed)" ;;
  esac
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 3
  if ! ui has 'Terminal output' > /dev/null 2>&1; then
    launch "$demo_url" || true
  fi
}

ime_state() {
  adb shell dumpsys input_method 2> /dev/null | grep -o 'mInputShown=[a-z]*' | head -1 || true
}

show_keyboard() {
  local point x y
  point=$(ui tap 'Command input') || point=$(ui tap 'Type a command') || point=""
  if [ -z "$point" ]; then
    note "keyboard: no input line"
    return 0
  fi
  adb shell dumpsys input_method > "$out/input-method.txt" 2> /dev/null || true
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 6
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
settings_shot

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

# 3. selection, copy and paste
record selection 10 select_word
shot selection
record copy 7 copy_selection
shot copy
record paste 8 paste_clipboard
shot paste

# 4. open the link a selection holds
record open-link 12 open_link

# 5. landscape, then back to portrait
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

# 6. soft keyboard show and hide
record keyboard 13 show_keyboard
record keyboard-hide 9 hide_keyboard

# 7. hardware keys
if ! ui has 'Terminal output' > /dev/null 2>&1; then
  launch "$demo_url" || true
fi
record hardware 10 hardware_keys
shot hardware

# 8. the font size from Settings, kept across a relaunch
record font-step 12 font_step
shot font-step

# 9. pinch zoom: the emulator's touch devices take one contact each, so this
# is reported either way and runs last, after the other evidence is taken.
before=$(grid_cells || true)
pinch_step
shot pinch-out
note "pinch: grid $before -> $(grid_cells || echo unknown)"

note "ok: terminal gestures recorded"
