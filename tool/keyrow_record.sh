#!/usr/bin/env bash
# Records the terminal's extra key row on the emulator: the bar above the soft
# keyboard, sticky Ctrl with a typed letter, the page swipe, the haptics
# setting and the key row editor. Media problems are reported, never failed.
# Usage: tool/keyrow_record.sh <flutter-apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/keyrow_record.sh <flutter-apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-keyrow}
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

density=$(adb shell wm density 2> /dev/null | sed -n 's/.*Physical density: \([0-9]*\).*/\1/p' | tr -d '\r')
density=${density:-420}
dp() { awk -v value="$1" -v dpi="$density" 'BEGIN { printf "%d", value * dpi / 160 }'; }

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

scroll_to() { # <needle> [tries]
  local attempt point
  for attempt in $(seq 1 "${2:-6}"); do
    if point=$(ui tap "$1"); then
      echo "$point"
      return 0
    fi
    adb shell input swipe 540 1500 540 800 300 > /dev/null 2>&1 || true
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
esc= ctrl= haptics= row=

show_keyboard() { # tap the input line, not the key row
  local point x y ex ey
  point=$(ui tap 'Type a command') || point=""
  if [ -n "$point" ]; then
    read -r x y <<< "$point"
  else
    read -r ex ey <<< "$esc"
    x=$((ex + $(dp 60)))
    y=$((ey - $(dp 52)))
  fi
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 3
}

ctrl_c() { # arm Ctrl, then type a letter
  read -r x y <<< "$ctrl"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 1.2
  adb shell input text c > /dev/null 2>&1 || true
  sleep 2.5
}

drag() { # a finger drag with real move steps, which input swipe lacks
  local y=$1 step start
  start=$(dp 330)
  adb shell input motionevent DOWN "$start" "$y" > /dev/null 2>&1 || return 1
  for step in 300 270 240 210 180 150 120 90; do
    adb shell input motionevent MOVE "$(dp "$step")" "$y" > /dev/null 2>&1 || true
  done
  adb shell input motionevent UP "$(dp 70)" "$y" > /dev/null 2>&1 || true
}

swipe_pages() { # one page per swipe, twice
  read -r _ y <<< "$ctrl"
  drag "$y"
  sleep 1.6
  drag "$y"
  sleep 1.6
}

toggle_haptics() {
  read -r x y <<< "$haptics"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 3
}

edit_keys() {
  read -r x y <<< "$row"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 2.5
  if ! ui has 'Choose which keys' > /dev/null 2>&1; then
    note "keyrow-editor: the sheet did not open"
    return 0
  fi
  local chip
  chip=$(ui tap 'Vertical bar') || chip=""
  if [ -n "$chip" ]; then
    read -r cx cy <<< "$chip"
    adb shell input tap "$cx" "$cy" > /dev/null 2>&1 || true
  fi
  sleep 2
}

install_app "$apk" || exit 0

# ---- 1. the bar, and the soft keyboard under it -------------------------
launch "$demo_url"
if ui has 'Extra key row' > /dev/null 2>&1; then
  note "terminal page: key row present"
else
  note "terminal page: no key row, the deep link did not open the terminal"
fi
esc=$(ui tap Escape) || esc=""
# The emulator reports a hardware keyboard, which hides the IME by default.
adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true
record keybar-keyboard 7 show_keyboard
adb shell dumpsys input_method 2> /dev/null | grep -o 'mInputShown=[a-z]*' | head -1 | tee -a "$summary" || true
shot keybar-keyboard

# ---- 2. sticky Ctrl + a typed letter -----------------------------------
ctrl=$(ui tap Control) || ctrl=""
if [ -n "$ctrl" ]; then
  record ctrl-c 8 ctrl_c
  shot ctrl-c
  if ui has '^C' > /dev/null 2>&1; then
    note "ctrl-c: verified ('^C' echoed)"
  else
    note "ctrl-c: echo is canvas text, check ctrl-c.png"
  fi
else
  note "ctrl-c: no Control key found"
fi

# ---- 3. swipe to the next page ----------------------------------------
if [ -n "$ctrl" ]; then
  record keybar-pages 8 swipe_pages
  if ui has 'page 3 of 3' > /dev/null 2>&1; then
    note "keybar-pages: verified (two swipes reached page 3)"
  else
    read -r _ page_y <<< "$ctrl"
    adb shell input swipe "$(dp 330)" "$page_y" "$(dp 70)" "$page_y" 900 > /dev/null 2>&1 || true
    sleep 1.2
    adb shell input swipe "$(dp 330)" "$page_y" "$(dp 70)" "$page_y" 900 > /dev/null 2>&1 || true
    sleep 1.2
    ui has 'page 3 of 3' > /dev/null 2>&1 && note "keybar-pages: verified (input swipe reached page 3)"
  fi
  if ! ui has 'page 3 of 3' > /dev/null 2>&1; then
    note "keybar-pages: swipes missed, stepping with the page dots"
    for _ in 1 2; do
      point=$(ui tap 'Key row page') || point=""
      [ -n "$point" ] && adb shell input tap $point > /dev/null 2>&1
      sleep 1.2
    done
    ui has 'page 3 of 3' > /dev/null 2>&1 && note "keybar-pages: dots reached page 3"
  fi
  shot keybar-page3
else
  note "keybar-pages: no Control key found"
fi

# ---- 4. the haptics setting and the key row editor --------------------
launch "taildeck://preview/?preview=1&tab=3&lang=en"
shot settings-terminal
haptics=$(scroll_to 'Terminal key haptics') || haptics=""
if [ -n "$haptics" ]; then
  record haptics 6 toggle_haptics
  shot haptics-off
  if ui has ', off' > /dev/null 2>&1; then
    note "haptics: verified (row reads off)"
  else
    note "haptics: check haptics-off.png"
  fi
else
  note "haptics: no row found"
fi
row=$(ui tap 'Extra key row') || row=""
if [ -z "$row" ]; then
  for _ in 1 2 3; do
    adb shell input swipe 540 800 540 1500 400 > /dev/null 2>&1 || true
    sleep 1
    row=$(ui tap 'Extra key row') && break
  done
fi
if [ -n "$row" ]; then
  record keyrow-editor 9 edit_keys
  shot keyrow-editor
else
  note "keyrow-editor: no row found"
fi

note "ok: extra key row recorded"
