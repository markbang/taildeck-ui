#!/usr/bin/env bash
# Agents switch gate: replays the reported recording. A herdr dial fails while
# the user is on another tab, then the Agents tab is tapped. The page must wake
# the target and paint the connecting skeleton; the failure left by the earlier
# dial may never paint, not even one frame, and only the dial this visit
# started may turn into an error.
#
# The page logs one `taildeck agents: <phase>` line per phase change, and the
# shell logs its route, so the order evidence is read from logcat: a stale
# failure logs `failed` for the reopened page, the fix logs `connecting` first.
# The clip's frames are then compared with the settled error card. uiautomator
# is not used: the tailnet spinner never lets a dump reach the idle state.
#
# Needs CONTROL_URL, a node key seeded against that control plane
# (tool/seed_state.dart, SEED_STATE) and a peer named bangwu on it
# (tool/motion/peer -hostname bangwu -hang-port 3001). The slow variant dials
# that hang port: it accepts and never answers, so the app's own four-second
# dial timeout is the window the skeleton is held in.
# Usage: CONTROL_URL=http://10.0.2.2:8080 SEED_STATE=/tmp/seed/tailscaled.state \
#          tool/agents_switch_record.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/agents_switch_record.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-agents-switch}
control_url=${CONTROL_URL:-}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out/files"
summary="$out/summary.txt"
: > "$summary"

fail() {
  echo "FAIL: $*" | tee -a "$summary"
  echo "phases: [$(phases 2> /dev/null)]" | tee -a "$summary"
  timeout 30 adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  shot fail-screen
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

# A freshly booted emulator takes a moment before its package service answers;
# an install that meets it too early dies with a broken pipe.
for _ in $(seq 1 30); do
  adb shell pm path android > /dev/null 2>&1 && break
  sleep 2
done
adb uninstall "$app" > /dev/null 2>&1 || true
installed=0
for attempt in 1 2 3; do
  if adb install -g "$apk" > "$out/install.txt" 2>&1; then installed=1; break; fi
  cat "$out/install.txt" >> "$summary"
  adb wait-for-device > /dev/null 2>&1 || true
  sleep 10
done
[ "$installed" = 1 ] || fail "adb install failed, see install.txt"
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

# A saved herdr target that cannot come up, so its dial fails on its own.
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
logs() { timeout 60 adb logcat -d 2> /dev/null | grep -a 'I flutter :'; }
phases() { logs | grep -aoE 'taildeck agents: [a-z]+' | awk '{print $3}' | tr '\n' ' ' | sed 's/ *$//'; }
# Waits for a phrase in the app's own log; the route and phase lines arrive
# within seconds of the launch.
await_log() { # <tag> <phrase> <limit-s>
  local waited=0
  while [ "$waited" -lt "$3" ]; do
    logs | grep -qF -- "$2" && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# The dock is a floating capsule under the page. Its label boxes are read from
# a settled dump; the fractions are only the fallback for a run whose dump
# never came back.
geometry() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  [ -n "${W:-}" ] || fail "no screen size"
  DOCK_NODES="$((W / 8)) $((SH * 917 / 1000))"
  DOCK_AGENTS="$((W * 5 / 8)) $((SH * 917 / 1000))"
}
tap_dock() { # <x> <y>
  adb shell input tap "$1" "$2" > /dev/null 2>&1 || fail "the dock tap did not land"
}

# Where the dock's two destinations are, from the dump taken at rest.
read_dock() { # <nodes-out> <agents-out>
  local nodes agents
  nodes=$(python3 "$here/ui.py" "$out/ui.xml" tap Nodes 2> /dev/null)
  agents=$(python3 "$here/ui.py" "$out/ui.xml" tap Agents 2> /dev/null)
  [ -n "$nodes" ] && [ -n "$agents" ] || return 1
  echo "$nodes" > "$1"
  echo "$agents" > "$2"
  note "dock: Nodes at [$nodes], Agents at [$agents]"
}

# A page at rest is static, so a dump of the settled card does reach the idle
# state. The spinners during loading do not, which is why this is only used
# once a failure is on screen.
rest_has() { # <needle> -> ok | missing | nodump
  local attempt
  for attempt in 1 2 3 4 5; do
    rm -f "$out/ui.xml"
    timeout 60 adb shell uiautomator dump /sdcard/ui.xml > "$out/dump.txt" 2>&1 || true
    if grep -q 'dumped to' "$out/dump.txt" &&
      timeout 30 adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 &&
      [ -s "$out/ui.xml" ]; then
      python3 "$here/ui.py" "$out/ui.xml" has "$1" 2> /dev/null && echo ok || echo missing
      return 0
    fi
    sleep 1
  done
  echo nodump
}

launch() { # <tag> <tab>
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 2
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -a android.intent.action.VIEW -d 'taildeck://preview/?tab=$2&lang=en&splash=0' -n $component" \
    > "$out/$1-launch.txt" 2>&1 || fail "$1: the launch did not start the app"
  await_log "$1" 'taildeck route: shell' 60 || fail "$1: the shell never showed"
  sleep 2
  note "$1: shell up"
}

# One switch: tap the tab, note the phase the page logs first, record the first
# seconds of it and keep a still of the rest.
switch_to_agents() { # <tag> <point> <clip?>
  local tag=$1 point=$2 clip=${3:-} rec=0
  if [ -n "$clip" ]; then
    # /data/local/tmp, not /sdcard: the gate runs as root (adb root) and the
    # sdcard's FUSE mount does not always take a root write.
    adb shell "rm -f /data/local/tmp/$tag.mp4" > /dev/null 2>&1 || true
    adb shell screenrecord --time-limit 9 --bit-rate 6000000 --size 540x1200 \
      "/data/local/tmp/$tag.mp4" > "$out/$tag-recorder.txt" 2>&1 &
    rec=$!
    sleep 0.8
  fi
  adb logcat -c > /dev/null 2>&1 || true
  sleep 0.2
  tap_dock $point
  # The page only logs a phase when its tab opens or its state changes. A
  # loaded emulator can take seconds to deliver the tap.
  await_log "$tag" 'taildeck agents: ' 12 \
    || fail "$tag: tapping the Agents tab started no page; the tap did not land"
  sleep 1
  shot "$tag-early"
  sleep 6
  shot "$tag-rest"
  if [ -n "$clip" ]; then
    wait "$rec" 2> /dev/null || true
    sleep 1
    adb shell "ls -l /data/local/tmp/$tag.mp4" >> "$out/$tag-recorder.txt" 2>&1 || true
    adb pull "/data/local/tmp/$tag.mp4" "$out/$tag.mp4" >> "$out/$tag-recorder.txt" 2>&1 || true
    [ -s "$out/$tag.mp4" ] || {
      note "$tag: recorder said: $(head -3 "$out/$tag-recorder.txt" | tr '\n' ' ')"
      fail "$tag: no clip"
    }
  fi
}

# The page's own line per phase change is the precise order evidence: a stale
# failure logs `failed` before the visit ever started a dial.
assert_phases() { # <tag> <expected>
  local actual
  actual=$(phases)
  note "$1: phases after the tap: [${actual:-none}]"
  [ "${actual:-none}" = "$2" ] \
    || fail "$1: phases after the tap were [${actual:-none}], want [$2]"
}

# --- slow variant: a four-second dial, so the skeleton is on screen --------

geometry
target bangwu "${HANG_PORT:-3001}"
launch slow 2
# The page woke the target at launch and its dial has to fail on its own.
await_log slow 'taildeck agents: failed' 40 \
  || fail "slow: the launch dial never failed; the stale failure this gate needs never existed"
note "slow: the launch dial failed with the page up"
sleep 1
shot slow-stale-error
case "$(rest_has 'did not answer')" in
  ok) note "slow: the card on screen is the dial's own failure" ;;
  missing) fail "slow: the page at rest does not carry that failure" ;;
  *) note "slow: no dump at rest; the still carries the card" ;;
esac
read_dock "$out/dock-nodes.txt" "$out/dock-agents.txt" || true
[ -s "$out/dock-nodes.txt" ] || echo "$DOCK_NODES" > "$out/dock-nodes.txt"
[ -s "$out/dock-agents.txt" ] || echo "$DOCK_AGENTS" > "$out/dock-agents.txt"
read -r nx ny < "$out/dock-nodes.txt"
read -r ax ay < "$out/dock-agents.txt"
tap_dock "$nx" "$ny"
sleep 2
# Leaving the page starts the next visit clean.
adb logcat -c > /dev/null 2>&1 || true
switch_to_agents slow "$ax $ay" clip
assert_phases slow "connecting failed"
[ -s "$out/slow-early.png" ] || fail "slow: no still of the first second"
case "$(rest_has 'did not answer')" in
  ok) note "slow: after the switch the visit's own timeout shows with the card" ;;
  missing) fail "slow: the failure this visit's dial made never reached the card" ;;
  *) note "slow: no dump after the switch; the clip carries it" ;;
esac

# Frames: the error card may not paint in the three seconds after the tap that
# the wake's four-second dial owns.
ffmpeg -loglevel error -y -i "$out/slow.mp4" -vf "fps=12,scale=48:48,format=gray" \
  -f rawvideo "$out/clip.raw" 2> /dev/null || fail "slow: could not decode the clip"
ffmpeg -loglevel error -y -i "$out/slow-stale-error.png" -vf "scale=48:48,format=gray" \
  -f rawvideo "$out/error.raw" 2> /dev/null || fail "slow: could not encode the error still"
mkdir -p "$out/frames"
ffmpeg -loglevel error -y -i "$out/slow.mp4" -vf "fps=12,scale=270:-2" \
  "$out/frames/frame-%03d.png" 2> /dev/null || true
python3 "$here/agents_switch_check.py" --frames "$out/clip.raw" --error "$out/error.raw" \
  --tap 0.8 --lead 36 >> "$summary" 2>&1 \
  || fail "slow: the error card painted before the connecting skeleton (see summary.txt)"
montage "$out"/frames/frame-*.png -tile 8x -geometry +3+3 -background '#101214' \
  "$out/frames.png" 2> /dev/null || true

# Nothing dials again by itself after that failure.
sleep 5
assert_phases slow "connecting failed"
note "slow: no second dial after the failure"

# --- recorded variant: the unknown host the report showed ------------------

target ghost 22
launch fast 0
sleep 8
switch_to_agents fast "$ax $ay"
assert_phases fast "connecting failed"
sleep 1
case "$(rest_has "Can't find node ghost")" in
  ok) note "fast: the recorded unknown-host sentence shows with the card" ;;
  missing) fail "fast: the unknown host did not reach the card" ;;
  *) note "fast: no dump at rest; the still carries the card" ;;
esac

note "ok: no stale failure painted; the wake's own failure shows with Retry"
adb uninstall "$app" > /dev/null 2>&1 || true
