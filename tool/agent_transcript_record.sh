#!/usr/bin/env bash
# Records an agent transcript on the emulator: a release APK built with
# TAILDECK_DEMO=true opens `?chat=w1:p1&herdr=demo&transcript=demo`, so the
# page, its Markdown and its tool rows are the shipped code over a canned
# session from the in-memory herdr (no herdr node on the runner). Every clip and still is stamped
# "demo transcript". Checks fail the run; media problems are only noted.
# Usage: tool/agent_transcript_record.sh <apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/agent_transcript_record.sh <apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-agent-transcript}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
mkdir -p "$out"
: > "$out/logcat.txt"
summary="$out/summary.txt"
: > "$summary"
failures=0
note() { echo "$*" | tee -a "$summary"; }
check() { # <label> <command...>
  local label=$1
  shift
  if "$@"; then note "PASS $label"; else note "FAIL $label"; failures=$((failures + 1)); fi
}
label='Demo transcript - release build (TAILDECK_DEMO)'

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell settings put system screen_off_timeout 2147483647 > /dev/null 2>&1 || true
for _ in $(seq 1 30); do
  adb shell pm path android > /dev/null 2>&1 && break
  sleep 2
done
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || { note "FAIL install, see install.txt"; exit 1; }

ui() { gate_ui "$out" "$here" "$@"; }
tap() { # <needle>
  local point
  point=$(ui tap "$1") || return 1
  # shellcheck disable=SC2086
  adb shell input tap $point
}

stamp() { # <in> <out> : the demo label across the top of a still or clip
  ffmpeg -loglevel error -y -i "$1" -vf "drawbox=x=0:y=0:w=iw:h=ih*0.035:color=black@0.72:t=fill,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='$label':fontcolor=white:fontsize=w*0.03:x=(w-tw)/2:y=(h*0.035-th)/2" \
    "$2" > /dev/null 2>&1 || cp "$1" "$2"
}

shot() { # <name>
  adb exec-out screencap -p > "$out/raw-$1.png" 2> /dev/null || true
  if [ -s "$out/raw-$1.png" ]; then
    stamp "$out/raw-$1.png" "$out/$1.png"
    rm -f "$out/raw-$1.png"
    note "still $1"
  else
    note "still $1: none"
  fi
}

recorder=''
rec_start() { # <name>
  adb shell pkill -f screenrecord > /dev/null 2>&1 || true
  sleep 0.5
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit 170 --bit-rate 8000000 /sdcard/rec.mp4 > /dev/null 2>&1 &
  recorder=$!
  rec_name=$1
  sleep 0.5
}
rec_stop() {
  adb shell pkill -INT screenrecord > /dev/null 2>&1 || true
  wait "$recorder" 2> /dev/null || true
  sleep 1
  adb pull /sdcard/rec.mp4 "$out/raw-$rec_name.mp4" > /dev/null 2>&1 || true
  if [ -s "$out/raw-$rec_name.mp4" ]; then
    stamp "$out/raw-$rec_name.mp4" "$out/$rec_name.mp4"
    rm -f "$out/raw-$rec_name.mp4"
    note "clip $rec_name: $(stat -c%s "$out/$rec_name.mp4") bytes"
  else
    note "clip $rec_name: none"
  fi
}

launch() { # <query>
  local attempt shown
  for attempt in 1 2 3; do
    adb shell am force-stop "$app" > /dev/null 2>&1 || true
    adb logcat -d >> "$out/logcat.txt" 2> /dev/null || true
    adb logcat -c > /dev/null 2>&1 || true
    sleep 1
    adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?$1' '$app'" > /dev/null 2>&1 || true
    shown=$SECONDS
    if wait_home "$app" "$out" "$here" '' 45 chat && gate_survived_focus "$app" "$shown" "$summary"; then
      return 0
    fi
    note "launch attempt $attempt did not reach the chat"
  done
  return 1
}

base="preview=1&chat=w1:p1&herdr=demo&lang=en&splash=0"
swipe_up() { adb shell input swipe 540 1500 540 900 700; sleep 1.2; }
swipe_down() { adb shell input swipe 540 900 540 1500 700; sleep 1.2; }

# Scrolls back until [needle] is on screen; the chat opens at its end.
find_up() { # <needle> [tries]
  local i
  for i in $(seq 1 "${2:-8}"); do
    ui has "$1" > /dev/null 2>&1 && return 0
    swipe_down
  done
  ui has "$1" > /dev/null 2>&1
}

markdown_flow() {
  check "dark chat launched" launch "$base&transcript=demo&theme=dark&status=idle"
  sleep 2
  shot agent-markdown-dark-end
  rec_start agent-markdown-dark
  check "heading rendered" find_up 'Why the cold-start dial fails'
  shot agent-markdown-dark-top
  check "no raw ** in the tree" bash -c "! grep -q '\*\*' '$out/ui.xml'"
  check "no raw [link](…) in the tree" bash -c "! grep -q '](lib/src' '$out/ui.xml'"
  check "path link copies" tap 'agents_phase.dart'
  sleep 0.6
  check "path copied snack" ui has 'Path copied'
  shot agent-markdown-path-copied
  sleep 3
  swipe_up
  check "code block copy button" tap 'Copy code'
  sleep 0.6
  check "code copied snack" ui has 'Code copied'
  shot agent-markdown-dark-code
  local box
  if box=$(ui bounds 'WaitNetmap'); then
    # shellcheck disable=SC2086
    set -- $box
    adb shell input swipe $((($1 + $3) / 2 + 200)) $((($2 + $4) / 2)) $((($1 + $3) / 2 - 300)) $((($2 + $4) / 2)) 600
    sleep 1
    shot agent-markdown-code-scrolled
  fi
  sleep 3
  swipe_up
  shot agent-markdown-dark-table
  swipe_up
  shot agent-markdown-dark-links
  check "inert javascript: link" ui has 'raw html stays text'
  check "external link opens" tap 'MagicDNS'
  sleep 3
  shot agent-markdown-external
  adb shell dumpsys activity activities 2> /dev/null | grep -m1 -E 'topResumedActivity' | tr -d '\r' >> "$summary" || true
  adb shell input keyevent KEYCODE_BACK
  sleep 2
  gate_in_front "$app" || adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?$base&transcript=demo&theme=dark' '$app'" > /dev/null 2>&1 || true
  rec_stop

  check "light chat launched" launch "$base&transcript=demo&theme=light&status=idle"
  find_up 'Why the cold-start dial fails' > /dev/null || true
  shot agent-markdown-light-top
  swipe_up
  shot agent-markdown-light-code
}

for flow in ${AGENT_FLOWS:-markdown}; do
  "${flow}_flow"
done

adb logcat -d >> "$out/logcat.txt" 2> /dev/null || true
if grep -E "FATAL EXCEPTION|ANR in $app" "$out/logcat.txt" > "$out/crashes.txt"; then
  note "FAIL crash or ANR (crashes.txt)"
  failures=$((failures + 1))
else
  note "PASS no crash or ANR"
fi
note "failures: $failures"
[ "$failures" -eq 0 ]
