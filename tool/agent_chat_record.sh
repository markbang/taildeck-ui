#!/usr/bin/env bash
# Records the agent chat page on the emulator against the in-memory herdr
# (`?chat=w1:p1&herdr=demo`, a TAILDECK_DEMO build): the body scrolling under
# the header, the task strip and the composer; the keyboard going up and down;
# overscroll at both ends; a light still. The page logs its layer rects
# (`taildeck chat layers:`), which the summary keeps next to each step.
# Usage: tool/agent_chat_record.sh <apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/agent_chat_record.sh <apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-agent-chat}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
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
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
# The emulator reports a physical keyboard, which hides the IME by default.
adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true
for _ in $(seq 1 30); do
  adb shell pm path android > /dev/null 2>&1 && break
  sleep 2
done

read -r width height <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
width=${width:-1080}
height=${height:-2400}
density=$(adb shell wm density 2> /dev/null | sed -n 's/.*Physical density: \([0-9]*\).*/\1/p' | tr -d '\r')
density=${density:-420}
dp() { awk -v value="$1" -v dpi="$density" 'BEGIN { printf "%d", value * dpi / 160 }'; }
mid=$((width / 2))

shot() { # <name>
  adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"
  [ -s "$out/$1.png" ] && note "$1: $(stat -c%s "$out/$1.png") bytes"
}

layers() { # <label>: the page's last layer line
  local line
  line=$(adb logcat -d 2> /dev/null | grep 'taildeck chat layers:' | tail -1 | sed 's/.*taildeck chat layers: //' || true)
  note "$1 layers: ${line:-none logged}"
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
    rm -f "$out/$name-raw.mp4"
    [ -s "$out/$name.mp4" ] && note "$name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "$name: no recording"
  fi
}

launch() { # <query>
  local attempt shown
  for attempt in 1 2; do
    adb shell am force-stop "$app" > /dev/null 2>&1 || true
    adb logcat -c > /dev/null 2>&1 || true
    sleep 1
    adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?$1' $app" > /dev/null 2>&1 || true
    shown=$SECONDS
    for _ in $(seq 1 40); do
      adb logcat -d 2> /dev/null | grep -q 'taildeck route: chat' && break
      sleep 1
    done
    if gate_survived_focus "$app" "$shown" "$summary"; then
      sleep 3
      return 0
    fi
    note "launch attempt $attempt hit the cold-start ANR"
  done
  return 1
}

ime_shown() {
  adb shell dumpsys input_method 2> /dev/null | grep -q 'mInputShown=true'
}

# The composer's field sits right above the system bars.
input_point() { echo "$((width * 2 / 5)) $((height - $(dp 96)))"; }

swipe() { adb shell input swipe "$@" > /dev/null 2>&1 || true; }

scroll_story() {
  local top low
  top=$(dp 200)
  low=$((height - $(dp 260)))
  for _ in 1 2 3; do swipe "$mid" "$top" "$mid" "$low" 900; sleep 0.6; done
  for _ in 1 2 3; do swipe "$mid" "$low" "$mid" "$top" 900; sleep 0.6; done
}

keyboard_story() {
  local x y
  read -r x y <<< "$(input_point)"
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || true
  sleep 2.5
  adb shell input text 'hello' > /dev/null 2>&1 || true
  sleep 1
  swipe "$mid" "$(dp 160)" "$mid" "$(dp 420)" 700
  sleep 0.8
  swipe "$mid" "$(dp 420)" "$mid" "$(dp 120)" 300
  sleep 1.2
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 2
}

overscroll_story() {
  local top low
  top=$(dp 160)
  low=$((height - $(dp 240)))
  # At the end of the list: pull further up, twice.
  swipe "$mid" "$low" "$mid" "$top" 120; sleep 1.2
  swipe "$mid" "$low" "$mid" "$top" 120; sleep 1.2
  # To the start, then pull down past it.
  for _ in 1 2 3 4 5; do swipe "$mid" "$top" "$mid" "$low" 80; sleep 0.4; done
  sleep 1
  swipe "$mid" "$top" "$mid" "$low" 400; sleep 1.2
  swipe "$mid" "$top" "$mid" "$low" 120; sleep 1.2
}

adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || { note "install failed"; exit 1; }

dark="preview=1&chat=w1:p1&herdr=demo&splash=0&lang=zh&theme=dark"
launch "$dark" || { note "the chat page never came up"; shot fail; exit 1; }
shot agent-sticky-dark-rest
layers rest
swipe "$mid" "$(dp 220)" "$mid" "$((height / 2))" 900
sleep 1.5
shot agent-sticky-dark-mid
record agent-sticky-scroll 9 scroll_story

launch "$dark"
record agent-sticky-keyboard 11 keyboard_story
read -r kx ky <<< "$(input_point)"
adb shell input tap "$kx" "$ky" > /dev/null 2>&1 || true
sleep 3
if ime_shown; then note "keyboard: shown"; else note "keyboard: NOT shown"; fi
shot agent-sticky-dark-keyboard
layers keyboard
adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
sleep 2
layers keyboard-down

launch "$dark"
record agent-sticky-overscroll 10 overscroll_story
shot agent-sticky-dark-overscroll-end

launch "preview=1&chat=w1:p1&herdr=demo&splash=0&lang=zh&theme=light"
swipe "$mid" "$(dp 220)" "$mid" "$((height / 2))" 900
sleep 1.5
shot agent-sticky-light

adb logcat -d 2> /dev/null | grep -E 'taildeck|FATAL|AndroidRuntime' > "$out/logcat.txt" || true
if grep -q 'FATAL EXCEPTION' "$out/logcat.txt"; then note "crash: see logcat.txt"; exit 1; fi
note "done"
