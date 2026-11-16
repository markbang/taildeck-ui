#!/usr/bin/env bash
# Agents switch gate: replays the reported recording. A herdr dial fails while
# the user is on another tab, then the Agents tab is tapped. The page must wake
# the target and paint the connecting skeleton; the failure left by the earlier
# dial may never paint, not even one frame, and only the dial this visit
# started may turn into an error with Retry.
# Needs CONTROL_URL, a node key seeded against that control plane
# (tool/seed_state.dart, SEED_STATE) and a peer named bangwu on it
# (tool/motion/peer -hostname bangwu -hang-port 3001). The slow variant dials
# that hang port: it accepts and never answers, so the app's own four-second
# dial timeout is the window the skeleton is sampled in.
# Usage: CONTROL_URL=http://10.0.2.2:8080 SEED_STATE=/tmp/seed/tailscaled.state \
#          tool/agents_switch_record.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/agents_switch_record.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-agents-switch}
control_url=${CONTROL_URL:-}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
mkdir -p "$out/files"
summary="$out/summary.txt"
: > "$summary"

fail() {
  echo "FAIL: $*" | tee -a "$summary"
  timeout 30 adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  timeout 30 adb pull /sdcard/ui.xml "$out/ui-fail.xml" > /dev/null 2>&1 || true
  timeout 60 adb uninstall "$app" > /dev/null 2>&1 || true
  exit 1
}
note() { echo "$*" | tee -a "$summary"; }

[ -n "$control_url" ] || { echo "CONTROL_URL is required"; exit 2; }
seed=${SEED_STATE:-/tmp/seed/tailscaled.state}
hostname=${SEED_HOSTNAME:-taildeck}
[ -s "$seed" ] || { echo "no seeded node state at $seed"; exit 2; }

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell settings put system screen_off_timeout 2147483647 > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true

adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
component=$(adb shell cmd package resolve-activity --brief "$app" 2> /dev/null | tail -n 1 | tr -d '\r' || true)
[ -n "$component" ] || fail "no launcher activity for $app"

adb root > /dev/null 2>&1 || true
adb wait-for-device
[ "$(adb shell id -u 2> /dev/null | tr -d '\r')" = "0" ] \
  || fail "adb root is required to seed the app's files (needs a google_apis emulator)"
data=/data/data/$app
adb shell "mkdir -p $data/files/tsnet" > /dev/null 2>&1 || fail "could not create $data/files"
adb push "$seed" "$data/files/tsnet/tailscaled.state" > "$out/push.txt" 2>&1 \
  || fail "could not push the node key"

# A saved herdr target that cannot come up, so the launch dial fails on its own.
target() { # <node> <port>
  printf '{"hostname":"%s","controlURL":"%s","signedIn":true,"herdrNode":"%s","herdrUser":"root","herdrPort":%s,"herdrAuth":"tailscale"}' \
    "$hostname" "$control_url" "$1" "$2" > "$out/files/config.json"
  adb push "$out/files/config.json" "$data/files/config.json" >> "$out/push.txt" 2>&1 \
    || fail "could not push the config"
  local uid
  uid=$(adb shell stat -c %u "$data" 2> /dev/null | tr -d '\r')
  adb shell "chown -R $uid:$uid $data/files" > /dev/null 2>&1 || true
}

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }
dump_page() {
  rm -f "$out/ui.xml"
  timeout 60 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || return 1
  timeout 30 adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || return 1
  [ -s "$out/ui.xml" ]
}
page_has() { python3 "$here/ui.py" "$out/ui.xml" has "$1" 2> /dev/null; }
tap_point() { python3 "$here/ui.py" "$out/ui.xml" tap "$1" 2> /dev/null; }
phases() { timeout 60 adb logcat -d 2> /dev/null | grep -aoE 'taildeck agents: [a-z]+' | awk '{print $3}' | tr '\n' ' ' | sed 's/ *$//'; }

launch() { # <tag> <tab>
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 2
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -a android.intent.action.VIEW -d 'taildeck://preview/?tab=$2&lang=en&splash=0' -n $component" \
    > "$out/$1-launch.txt" 2>&1 || fail "$1: the launch did not start the app"
  wait_home "$app" "$out" "$here" Services 60 || fail "$1: the shell never showed its dock"
}

# Wait for the saved target's own dial to fail while another tab is up, so the
# page meets a failure it never watched begin.
await_failure() { # <tag> <limit-ms>
  local tag=$1 limit=${2:-20000} t0
  t0=$(date +%s%3N)
  while [ $(( $(date +%s%3N) - t0 )) -lt "$limit" ]; do
    dump_page || { sleep 1; continue; }
    if page_has "Retry"; then
      note "$tag: the launch dial failed after $(( $(date +%s%3N) - t0 ))ms"
      return 0
    fi
    sleep 1
  done
  fail "$tag: the launch dial never failed; the stale failure this gate needs never existed"
}

# One switch: tap the point, sample the page, record the first seconds of it.
switch_and_record() { # <tag> <point> <clip>
  local tag=$1 point=$2 clip=${3:-}
  local x=${point% *} y=${point#* } rec=0
  if [ -n "$clip" ]; then
    adb shell "rm -f /sdcard/$tag.mp4" > /dev/null 2>&1 || true
    adb shell screenrecord --time-limit 9 --bit-rate 6000000 --size 540x1200 \
      "/sdcard/$tag.mp4" > /dev/null 2>&1 &
    rec=$!
    sleep 0.8
  fi
  adb logcat -c > /dev/null 2>&1 || true
  sleep 0.2
  local t0
  t0=$(date +%s%3N)
  adb shell input tap "$x" "$y" > /dev/null 2>&1 || fail "$tag: the tap did not land"
  # Samples: progress must be on screen while the wake dials, the error only
  # once that dial has failed.
  local at wait_for name
  for at in 600 1400 2400 3400 4600 7000; do
    wait_for=$(( at - ( $(date +%s%3N) - t0 ) ))
    [ "$wait_for" -gt 0 ] && sleep "$(awk "BEGIN{printf %.3f, $wait_for/1000}")"
    name=$(printf '%s-%dms' "$tag" "$at")
    dump_page || { note "$name: no dump"; continue; }
    {
      printf '%s:' "$name"
      page_has "Connecting to herdr" && printf ' connecting'
      page_has "Connecting to the tailnet" && printf ' tailnet'
      page_has "Retry" && printf ' retry'
      page_has "Can't find node" && printf ' no-host'
      page_has "did not answer" && printf ' timeout'
      printf '\n'
    } >> "$summary"
    cp "$out/ui.xml" "$out/$name.xml" 2> /dev/null || true
  done
  shot "$tag-rest"
  if [ -n "$clip" ]; then
    wait "$rec" 2> /dev/null || true
    sleep 1
    adb pull "/sdcard/$tag.mp4" "$out/$tag.mp4" > /dev/null 2>&1 || true
    [ -s "$out/$tag.mp4" ] || fail "$tag: no clip"
  fi
}

# The page's own line per phase change is the precise order evidence: a stale
# failure logs `failed` before the switch ever started a dial.
assert_phases() { # <tag> <expected>
  local actual
  actual=$(phases)
  note "$1: phases after the tap: [${actual:-none}]"
  [ "${actual:-none}" = "$2" ] \
    || fail "$1: phases after the tap were [${actual:-none}], want [$2]"
}

# --- slow variant: a four-second dial, so the skeleton is sampled ----------

target bangwu "${HANG_PORT:-3001}"
launch slow 2
await_failure slow 30000
sleep 1
shot slow-stale-error
dump_page || fail "slow: no dump of the stale error"
page_has "Retry" || fail "slow: the error card left the screen before the switch"
tap_point Nodes > "$out/slow-nodes.txt" || fail "slow: no Nodes destination in the dock"
read -r nx ny < "$out/slow-nodes.txt"
adb shell input tap "$nx" "$ny" > /dev/null 2>&1 || fail "slow: the Nodes tap did not land"
sleep 1.5
dump_page || fail "slow: no dump after leaving the Agents tab"
page_has "Connecting to herdr" && fail "slow: the Agents page stayed on screen after leaving it"
agents_point=$(tap_point Agents) || fail "slow: no Agents destination in the dock"
switch_and_record slow "$agents_point" clip
assert_phases slow "connecting failed"

grep -q 'slow-600ms:.*connecting' "$summary" \
  || fail "slow: no connecting skeleton 600ms after the tap (see summary.txt)"
for at in 1400 2400 3400; do
  grep -q "slow-${at}ms:.*connecting" "$summary" \
    || fail "slow: the skeleton left the screen by ${at}ms"
  grep -q "slow-${at}ms:.*retry" "$summary" \
    && fail "slow: the stale error card was on screen at ${at}ms after the tap"
done
grep -q 'slow-7000ms:.*retry' "$summary" \
  || fail "slow: the failure of this visit never showed; the page kept its skeleton"
grep -q 'slow-7000ms:.*connecting' "$summary" \
  && fail "slow: the skeleton was still up at 7s; the wake dial never finished"

# Frames: the error card may not paint inside the second after the tap.
ffmpeg -loglevel error -y -i "$out/clip.mp4" -vf "fps=12,scale=48:48,format=gray" \
  -f rawvideo "$out/clip.raw" 2> /dev/null || fail "slow: could not decode the clip"
ffmpeg -loglevel error -y -i "$out/slow-stale-error.png" -vf "scale=48:48,format=gray" \
  -f rawvideo "$out/error.raw" 2> /dev/null || fail "slow: could not encode the error still"
mkdir -p "$out/frames"
ffmpeg -loglevel error -y -i "$out/clip.mp4" -vf "fps=12,scale=270:-2" \
  "$out/frames/frame-%03d.png" 2> /dev/null || true
# The wake's own dial needs its four seconds, so nothing may paint the card in
# the first three: a stale one appears the moment the tab opens.
python3 "$here/agents_switch_check.py" --frames "$out/clip.raw" --error "$out/error.raw" \
  --tap 0.8 --lead 36 >> "$summary" 2>&1 \
  || fail "slow: the error card painted before the connecting skeleton (see summary.txt)"
montage "$out"/frames/frame-*.png -tile 8x -geometry +3+3 -background '#101214' \
  "$out/frames.png" 2> /dev/null || true

# Nothing dials again by itself after that failure.
sleep 6
assert_phases slow "connecting failed"

# --- recorded variant: the unknown host the report showed -------------------

target ghost 22
launch fast 0
sleep 8
agents_point=$(tap_point Agents) || fail "fast: no Agents destination in the dock"
switch_and_record fast "$agents_point"
assert_phases fast "connecting failed"
grep -q "fast-7000ms:.*no-host" "$summary" \
  || fail "fast: the unknown host never reached the error card"
grep -q "fast-7000ms:.*retry" "$summary" \
  || fail "fast: the failure of this visit offers no Retry"

note "ok: no stale failure painted; the wake's own failure shows with Retry"
adb uninstall "$app" > /dev/null 2>&1 || true
