#!/usr/bin/env bash
# In-app web view video gate: a saved service on the test peer opens in the web
# view and plays four clips (tool/motion/peer/video.go). H.264 from a relative
# source and from an absolute tailnet URL (how AList/OpenList link raw files)
# and an HLS playlist must play past 1.5 s with no error event; H.265 is
# recorded, not failed. The verdicts come from the page's own reports in the peer's log.
# Needs CONTROL_URL, SEED_STATE (tool/seed_state.dart), the motionpeer peer and
# adb root (google_apis emulator).
# Usage: CONTROL_URL=http://10.0.2.2:8080 SEED_STATE=/tmp/seed/tailscaled.state \
#          PEER_LOG=/tmp/peer2.log tool/webvideo_android.sh <apk> [application-id] [out-dir]
set -uo pipefail

apk=${1:?usage: tool/webvideo_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-webvideo}
control_url=${CONTROL_URL:?CONTROL_URL is required}
seed=${SEED_STATE:-/tmp/seed/tailscaled.state}
peer_log=${PEER_LOG:-/tmp/peer2.log}
peer=${PEER:-motionpeer}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out/files"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }
evidence() {
  timeout 30 adb logcat -d > "$out/logcat.txt" 2>&1 || true
  grep -aE 'chromium|cr_|MediaCodec|MediaPlayer|ERR_|video-report|taildeck' "$out/logcat.txt" \
    | grep -avE 'uiautomator' > "$out/logcat-key.txt" || true
  sed -n "$((from + 1)),\$p" "$peer_log" > "$out/peer.log" 2>/dev/null || true
}
fail() {
  note "FAIL: $*"
  evidence
  timeout 60 adb uninstall "$app" > /dev/null 2>&1 || true
  exit 1
}

[ -s "$seed" ] || fail "no seeded node state at $seed"
[ -f "$peer_log" ] || fail "no peer log at $peer_log"
adb wait-for-device
[ -n "${DERP_PORT:-}" ] && adb reverse "tcp:$DERP_PORT" "tcp:$DERP_PORT" > /dev/null 2>&1
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true

adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
component=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$component" ] || fail "no launcher activity for $app"

# Signed in from a seeded node key, set to open services in the app, with one
# saved service on the peer: the path a user takes from the node page.
adb root > /dev/null 2>&1 || true
adb wait-for-device
[ "$(adb shell id -u 2> /dev/null | tr -d '\r')" = "0" ] || fail "adb root is required to seed the app's files"
data=/data/data/$app
adb shell "mkdir -p $data/files/tsnet" > /dev/null 2>&1 || fail "could not create $data/files"
adb push "$seed" "$data/files/tsnet/tailscaled.state" > "$out/push.txt" 2>&1 || fail "could not push the node key"
printf '{"hostname":"taildeck","controlURL":"%s","signedIn":true,"openInApp":true}' "$control_url" \
  > "$out/files/config.json"
printf '[{"id":"webvideo","node":"%s","name":"Video gate","url":"http://%s:3000/video"}]' "$peer" "$peer" \
  > "$out/files/services.json"
adb push "$out/files/config.json" "$data/files/config.json" >> "$out/push.txt" 2>&1 || fail "could not push the config"
adb push "$out/files/services.json" "$data/files/services.json" >> "$out/push.txt" 2>&1 || fail "could not push the services"
appuid=$(adb shell stat -c %u "$data" 2> /dev/null | tr -d '\r')
# The app's SELinux categories come from its uid; restorecon guesses others,
# so the files take the label of the app's own data dir.
appctx=$(adb shell stat -c %C "$data" 2> /dev/null | tr -d '\r')
[ -n "$appuid" ] && [ -n "$appctx" ] || fail "no owner or label for $data"
adb shell "chown -R $appuid:$appuid $data/files && chcon -R $appctx $data/files" >> "$out/push.txt" 2>&1 \
  || fail "could not hand $data/files to the app; see push.txt"
adb shell "ls -lZR $data/files" >> "$out/push.txt" 2>&1 || true

ui() { # <ui.py args...>
  local attempt
  for attempt in 1 2 3; do
    rm -f "$out/ui.xml"
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    python3 "$here/ui.py" "$out/ui.xml" "$@" 2> /dev/null && return 0
    sleep 0.5
  done
  return 1
}

from=$(wc -l < "$peer_log")
adb logcat -c > /dev/null 2>&1 || true
adb shell "am start -a android.intent.action.VIEW -d 'taildeck://preview/?node=$peer&lang=en&splash=0' -n $component" \
  > "$out/launch.txt" 2>&1 || fail "the launch did not start the app"
point=
for _ in $(seq 1 60); do
  point=$(ui tap "Video gate") && break
  sleep 1
done
[ -n "$point" ] || fail "the node page never listed the saved service; see ui.xml"
adb exec-out screencap -p > "$out/node.png" 2>/dev/null || true
gw=$(adb logcat -d 2>/dev/null | sed -n 's/.*taildeck: started, gateway \([0-9]*\).*/\1/p' | tail -1)
note "node page up, gateway port ${gw:-unknown}"

adb shell rm -f /sdcard/webvideo.mp4 > /dev/null 2>&1 || true
adb shell screenrecord --time-limit 30 --bit-rate 4000000 --size 720x1600 /sdcard/webvideo.mp4 > /dev/null 2>&1 &
recorder=$!
sleep 1
# shellcheck disable=SC2086
adb shell input tap $point > /dev/null 2>&1 || true

reports() { sed -n "$((from + 1)),\$p" "$peer_log" | grep -a 'video-report' || true; }
for _ in $(seq 1 60); do
  [ "$(reports | wc -l)" -ge 4 ] && break
  sleep 1
done
sleep 2
adb exec-out screencap -p > "$out/webview.png" 2>/dev/null || true
wait "$recorder" 2> /dev/null || true
adb pull /sdcard/webvideo.mp4 "$out/webvideo-raw.mp4" > /dev/null 2>&1 || true
[ -s "$out/webvideo-raw.mp4" ] && ffmpeg -loglevel error -y -i "$out/webvideo-raw.mp4" -an \
  -vf 'scale=360:-2' -c:v libx264 -pix_fmt yuv420p -crf 28 "$out/webvideo.mp4" || true

# The same request path the web view takes, from the runner through adb.
if [ -n "$gw" ]; then
  adb forward "tcp:$gw" "tcp:$gw" > /dev/null 2>&1 || true
  {
    echo "\$ curl -r 0-1023 -i -H 'Host: $peer-3000.localhost:$gw' http://127.0.0.1:$gw/media/h264.mp4"
    curl -sS -m 20 -r 0-1023 -o /dev/null -D - -H "Host: $peer-3000.localhost:$gw" "http://127.0.0.1:$gw/media/h264.mp4" 2>&1
    echo "\$ curl -x http://127.0.0.1:$gw -r 0-1023 -i http://$peer:3000/media/h264.mp4"
    curl -sS -m 20 -x "http://127.0.0.1:$gw" -r 0-1023 -o /dev/null -D - "http://$peer:3000/media/h264.mp4" 2>&1
  } | tr -d '\r' > "$out/curl.txt"
  cat "$out/curl.txt" >> "$summary"
fi

evidence
reports | sed 's/.*video-report /report: /' | tee -a "$summary"
status=0
for c in h264-rel h264-abs hls; do
  line=$(reports | grep -a "case=$c " | tail -1)
  case "$line" in
    *" ok=1 "*) note "ok $c" ;;
    "") note "FAIL $c: the page never reported"; status=1 ;;
    *) note "FAIL $c: ${line#*video-report }"; status=1 ;;
  esac
done
for c in hevc; do
  line=$(reports | grep -a "case=$c " | tail -1)
  note "info $c: ${line#*video-report }"
done

# The proxy override is process-wide: closing the page must drop it.
adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
cleared=
for _ in $(seq 1 15); do
  adb logcat -d 2>/dev/null | grep -aq 'taildeck: web view proxy cleared' && { cleared=1; break; }
  sleep 1
done
if [ -n "$cleared" ]; then
  note "ok proxy cleared after the page closed"
else
  note "FAIL the proxy override outlived the page"; status=1
fi
adb uninstall "$app" > /dev/null 2>&1 || true
exit "$status"
