#!/usr/bin/env bash
# Startup routing gate: sign in on a test control plane once, then cold start
# the app 20 times and fail when the login page shows up on any launch. Every
# run keeps a clip of its first 3 s and a frame signature compared against a
# login reference. Needs CONTROL_URL and AUTH_KEY (tool/motion/control).
# Usage: CONTROL_URL=http://10.0.2.2:8080 AUTH_KEY=tskey-test \
#          tool/routing_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/routing_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-routing}
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-}
runs=${RUNS:-20}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"

fail() {
  echo "FAIL: $*" | tee -a "$summary"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb uninstall "$app" > /dev/null 2>&1 || true
  exit 1
}
note() { echo "$*" | tee -a "$summary"; }

[ -n "$control_url" ] && [ -n "$auth_key" ] \
  || { echo "CONTROL_URL and AUTH_KEY are required: a test control plane is what signs the node in"; exit 2; }

adb wait-for-device
# testcontrol's relay listens on the runner's loopback; the emulator reaches it
# as 10.0.2.2, so hand the same port through adb.
if [ -n "${DERP_PORT:-}" ]; then
  adb reverse "tcp:$DERP_PORT" "tcp:$DERP_PORT" > /dev/null 2>&1 || true
fi
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell settings put system screen_off_timeout 2147483647 > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true

activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

ui() {
  for _ in 1 2 3; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if python3 tool/ui.py "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
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

tap_text() {
  local point
  point=$(ui tap "$1") || return 1
  # shellcheck disable=SC2086
  adb shell input tap $point > /dev/null 2>&1 || true
  sleep 0.8
}

fill_field() { # <index> <value>
  local point
  point=$(ui edit "$1") || return 1
  # shellcheck disable=SC2086
  adb shell input tap $point > /dev/null 2>&1 || true
  sleep 0.5
  adb shell input text "$(printf '%s' "$2" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
  sleep 0.4
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 0.6
}

launch_url() { # <url>
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 1
  adb shell "am start -W -a android.intent.action.VIEW -d '$1' -n $activity" > "$out/launch.txt" 2>&1 || true
  sleep 3
}

screen_size() {
  adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r'
}

# A fresh install has no record: this is the login page as it looks, the frame
# every cold start is measured against.
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
launch_url "taildeck://preview/?login=1&lang=en&splash=0"
wait_for "Continue in browser" 60 || fail "the login page never opened; see ui.xml"
adb exec-out screencap -p > "$out/login.png" || fail "login reference screenshot failed"
note "login reference: $out/login.png"

# Sign in once through the fields the login page shows.
tap_text "Control server" || fail "no Control server toggle"
fill_field 0 "$control_url" || fail "no control server field"
tap_text "Use an auth key" || fail "no auth key toggle"
fill_field 0 "$auth_key" || fail "no auth key field"
read -r w h <<< "$(screen_size)"
tap_text "Connect" || {
  adb shell input swipe "$((w / 2))" "$((h * 3 / 4))" "$((w / 2))" "$((h / 2))" 300 > /dev/null 2>&1
  sleep 1
  tap_text "Connect" || fail "no Connect button"
}
wait_for "Services" 120 || fail "sign-in did not reach the shell; see ui.xml"
sleep 6
adb exec-out screencap -p > "$out/home.png" || fail "home reference screenshot failed"
note "home reference: $out/home.png"
signed=$(adb shell run-as "$app" cat files/config.json 2> /dev/null \
  | sed -n 's/.*"signedIn":\(true\|false\).*/\1/p' || true)
note "saved config signedIn=${signed:-unknown}"

ffmpeg -loglevel error -y -i "$out/login.png" -vf 'scale=48:48,format=gray' -f rawvideo "$out/login.raw"
ffmpeg -loglevel error -y -i "$out/home.png" -vf 'scale=48:48,format=gray' -f rawvideo "$out/home.raw"

cold_start() { # <tag>
  local tag=$1
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 2
  adb logcat -c > /dev/null 2>&1 || true
  adb shell rm -f /sdcard/cold.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit 6 --bit-rate 8000000 /sdcard/cold.mp4 > /dev/null 2>&1 &
  local recorder=$!
  sleep 1.2
  adb shell am start -W -n "$activity" > "$out/$tag-launch.txt" 2>&1 || true
  sleep 5
  wait "$recorder" 2> /dev/null || true
  adb pull /sdcard/cold.mp4 "$out/$tag.mp4" > /dev/null 2>&1 || true
  [ -s "$out/$tag.mp4" ] || return 1
  # The recording starts 1.2 s before the launch; keep the app's first 4 s.
  ffmpeg -loglevel error -y -ss 1.0 -t 3.0 -i "$out/$tag.mp4" \
    -an -vf 'scale=360:-2' -c:v libx264 -pix_fmt yuv420p -crf 28 "$out/$tag-3s.mp4" || true
  ffmpeg -loglevel error -y -ss 1.0 -t 4.0 -i "$out/$tag.mp4" \
    -vf 'fps=8,scale=48:48,format=gray' -f rawvideo "$out/$tag.raw" || return 1
}

for n in $(seq 1 "$runs"); do
  tag=$(printf 'run-%02d' "$n")
  cold_start "$tag" || fail "run $n: the cold start was not recorded"
  pid=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
  [ -n "$pid" ] || fail "run $n: $app is not running"

  python3 tool/frame_check.py --login "$out/login.raw" --home "$out/home.raw" \
    --frames "$out/$tag.raw" > "$out/$tag-check.txt" 2>&1 || {
    ffmpeg -loglevel error -y -ss 1.6 -i "$out/$tag.mp4" -frames:v 1 "$out/$tag-fail.png" || true
    cat "$out/$tag-check.txt" >> "$summary"
    fail "run $n: the login page was on screen during a cold start ($tag-fail.png)"
  }

  routes=$(adb logcat -d 2>/dev/null | grep -o 'taildeck route: [a-z]*' | awk '{print $3}' | tr '\n' ' ')
  case " $routes " in
    *" login "*) cat "$out/$tag-check.txt" >> "$summary"
      fail "run $n: the app routed to the login page ($routes)" ;;
  esac
  case " $routes " in
    *" shell "*) ;;
    *) fail "run $n: the home shell never opened ($routes)" ;;
  esac
  note "$tag: $(cat "$out/$tag-check.txt") routes=${routes:-none}"
  ffmpeg -loglevel error -y -ss 2.2 -i "$out/$tag.mp4" -frames:v 1 "$out/$tag-thumb.png" || true
done

# Evidence: one clip of a cold start and a contact sheet of every run.
if [ -s "$out/run-01-3s.mp4" ]; then
  ffmpeg -loglevel error -y -i "$out/run-01-3s.mp4" \
    -vf 'fps=8,scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse' \
    "$out/cold-start.gif" || true
fi
montage "$out"/run-*-thumb.png -tile 5x4 -geometry +4+4 -background '#101214' \
  "$out/cold-start-runs.png" 2>/dev/null || true

note "ok: $runs cold starts with the home shell and no login frame"
adb uninstall "$app" > /dev/null 2>&1 || true
