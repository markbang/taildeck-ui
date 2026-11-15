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

tap_ime_action() { # the soft keyboard's own send/done key
  local point x y
  point=$(point_in 'Send' inputmethod) || point=$(point_in 'Enter' inputmethod) || point=""
  if [ -z "$point" ]; then
    note "ime-action: the keyboard has no Send key in its tree"
    return 0
  fi
  read -r x y <<< "$point"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  note "ime-action: tapped the keyboard's key at $x,$y"
  sleep 1.2
}

# ---- the steps -----------------------------------------------------------
send_step() {
  focus_input
  type_line 'echo send'
  tap_send
}

ime_step() {
  focus_input
  type_line 'echo enter'
  ime_enter
}

ime_action_step() {
  focus_input
  type_line 'echo action'
  tap_ime_action
}

hold_step() {
  focus_input
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
  # With the line empty, a second Send presses Enter alone.
  tap_send
  hold_send
  if ui has 'Send presses Enter' > /dev/null 2>&1; then
    note "hold-send again: Enter back on"
  else
    note "hold-send again: no notice"
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
