#!/usr/bin/env bash
# Records what Send writes on the emulator: the app's Send button, the soft
# keyboard's Enter and its own send key, and the long-press that turns Enter
# off. The demo session echoes every byte with caret notation, so a CR shows
# up on the grid as ^M. Media problems are reported, never failed.
# Usage: tool/termsend_record.sh <flutter-apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/termsend_record.sh <flutter-apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-termsend}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true
sleep 20
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
# The emulator reports a physical keyboard, which hides the IME by default.
adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true

wake() { # the emulator still locks itself on a long run
  adb shell input keyevent KEYCODE_WAKEUP > /dev/null 2>&1 || true
  adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
  adb shell svc power stayon true > /dev/null 2>&1 || true
  adb shell settings put system screen_off_timeout 2147483647 > /dev/null 2>&1 || true
}

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

FIND_PY="$(mktemp)"
cat > "$FIND_PY" <<'FIND_EOF'
import re, sys, xml.etree.ElementTree as ET

path, needle, package = sys.argv[1:4]
box_re = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
best = None
for node in ET.parse(path).getroot().iter("node"):
    if package not in (node.get("package") or ""):
        continue
    labels = [v.lower() for v in (node.get("text"), node.get("content-desc")) if v]
    if not any(needle.lower() in label for label in labels):
        continue
    box = box_re.match(node.get("bounds") or "")
    if not box:
        continue
    x1, y1, x2, y2 = map(int, box.groups())
    if x2 <= x1 or y2 <= y1:
        continue
    if best is None or y1 < best[0]:
        best = (y1, (x1 + x2) // 2, (y1 + y2) // 2)
if best is None:
    sys.exit(1)
print(best[1], best[2])
FIND_EOF

# The keyboard advertises its own "Send" key while the app does too: a tap
# point is only useful with the window that owns it.
point_in() { # <needle> <package fragment>
  dump
  python3 "$FIND_PY" "$out/ui.xml" "$1" "$2"
}

shot() { # <name>
  adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"
  [ -s "$out/$1.png" ] && note "$1: $(stat -c%s "$out/$1.png") bytes"
}

record() { # <name> <seconds> <shell function>
  local name=$1 seconds=$2 action=$3
  wake
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

focus_input() { # tap the input line
  local point x y
  point=$(ui tap 'Command input') || point=$(ui tap 'Type a command') || point=$(ui tap 'Terminal input') || point=""
  if [ -z "$point" ]; then
    note "focus: no input line"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 1
}

type_line() { # <text>; `input text` wants %s for a space
  local escaped
  escaped=${1// /%s}
  adb shell input text "$escaped" > /dev/null 2>&1 || true
  sleep 0.8
}

tap_send() {
  local point x y
  point=$(point_in 'Send' "$app") || point=""
  if [ -z "$point" ]; then
    note "send: no Send button in the app's tree"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 1.2
}

hold_send() {
  local point x y
  point=$(point_in 'Send' "$app") || point=""
  if [ -z "$point" ]; then
    note "hold-send: no Send button in the app's tree"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input swipe "$x" "$y" "$x" "$y" 1400 > /dev/null 2>&1 || true
  sleep 1.4
}

ime_enter() {
  adb shell input keyevent KEYCODE_ENTER > /dev/null 2>&1 || true
  sleep 1.2
}

screen_size() { # prints "W H"
  local size
  size=$(adb shell wm size 2> /dev/null | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')
  echo "${size:-1080 2400}"
}

ime_shown() {
  adb shell dumpsys input_method 2> /dev/null | grep -q 'mInputShown=true'
}

# Gboard keeps its keys out of the a11y tree, so its send arrow is found by
# colour: the accent blue sits in the bottom strip of the screen.
find_send_key() {
  adb exec-out screencap -p > "$out/ime-screen.png" 2> /dev/null || return 1
  [ -s "$out/ime-screen.png" ] || return 1
  ffmpeg -loglevel error -y -i "$out/ime-screen.png" -f rawvideo -pix_fmt rgb24 \
    "$out/ime-screen.rgb" 2> /dev/null || return 1
  python3 - "$out/ime-screen.rgb" <<'COLOUR_EOF'
import sys

raw = open(sys.argv[1], "rb").read()
width, height = 1080, len(raw) // (1080 * 3)
top = int(height * 0.72)
xs, ys = [], []
for y in range(top, height, 2):
    row = y * width * 3
    for x in range(0, width, 2):
        i = row + x * 3
        r, g, b = raw[i], raw[i + 1], raw[i + 2]
        if b > 200 and 120 < g < 210 and r < 130:
            xs.append(x)
            ys.append(y)
if not xs:
    sys.exit(1)
print(sum(xs) // len(xs), sum(ys) // len(ys))
COLOUR_EOF
}

tap_ime_action() { # the soft keyboard's own send key
  local point x y
  if ! ime_shown; then
    note "ime-action: no soft keyboard up"
    return 0
  fi
  point=$(find_send_key) || point=""
  if [ -z "$point" ]; then
    note "ime-action: no blue send key on screen"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  note "ime-action: tapped the keyboard's send key at $x,$y"
  sleep 0.4
  shot ime-action-grid
  sleep 1.2
  if ui has 'echo action' > /dev/null 2>&1; then
    note "ime-action: the line did not leave the input bar"
  else
    note "ime-action: the line left the input bar"
  fi
}

# ---- the steps -----------------------------------------------------------
start_fresh() { # each clip opens the demo page itself
  wake
  launch "$demo_url" || return 0
  focus_input
  if ! ui has 'Terminal output' > /dev/null 2>&1; then
    note "step: the terminal page is not on screen"
  fi
}

send_step() {
  start_fresh
  type_line 'echo send'
  tap_send
}

ime_step() {
  start_fresh
  type_line 'echo enter'
  ime_enter
}

ime_action_step() {
  start_fresh
  type_line 'echo action'
  tap_ime_action
}

hold_step() {
  start_fresh
  hold_send
  if ui has 'Send inserts the text without Enter' > /dev/null 2>&1; then
    note "hold-send: insert-only reported"
  else
    note "hold-send: no insert-only notice"
  fi
  shot insert-only-on
  focus_input
  type_line 'echo ins'
  tap_send
  shot insert-only-typed
  # Enter back on: the empty line then sends its CR alone.
  hold_send
  if ui has 'Send presses Enter' > /dev/null 2>&1; then
    note "hold-send again: Enter back on"
  else
    note "hold-send again: no notice"
  fi
  sleep 1.5
  tap_send
  shot insert-only-cr
}

keyrow_step() { # page 2 holds the row's own insert-only key
  start_fresh
  local x1 y1 x2 y2 mid point x y
  read -r x1 y1 x2 y2 <<< "$(ui bounds 'Extra key row')" || return 0
  mid=$(((y1 + y2) / 2))
  adb shell input swipe "$((x2 - 30))" "$mid" "$((x1 + 20))" "$mid" 220 > /dev/null 2>&1 || true
  sleep 1.4
  shot keyrow-page2
  point=$(point_in 'Insert without Enter' "$app") || point=""
  if [ -z "$point" ]; then
    note "keyrow: no Ins key on page 2"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 1.2
  shot keyrow-ins
  if ui has 'Send inserts the text without Enter' > /dev/null 2>&1; then
    note "keyrow: the Ins key turned Enter off"
  else
    note "keyrow: no insert-only notice from the Ins key"
  fi
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 1.2
  if ui has 'Send presses Enter' > /dev/null 2>&1; then
    note "keyrow: a second tap turned Enter back on"
  else
    note "keyrow: no notice on the second tap"
  fi
}

# ---- run ----------------------------------------------------------------
install_app "$apk" || exit 0
launch "$demo_url" || exit 0
if ui has 'Terminal output' > /dev/null 2>&1; then
  note "terminal page: open"
else
  note "terminal page: missing"
fi
shot start

note "ime: $(adb shell ime list -s 2> /dev/null | tr -d '\r' | paste -sd, -)"
note "keyboard: $(adb shell dumpsys input_method 2> /dev/null | grep -o 'mInputShown=[a-z]*' | head -1 || true)"

record send 10 send_step
shot send
record ime 10 ime_step
shot ime
record ime-action 12 ime_action_step
shot ime-action
record insert-only 16 hold_step
shot insert-only
record keyrow 14 keyrow_step
shot keyrow
