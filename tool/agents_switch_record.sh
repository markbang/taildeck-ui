#!/usr/bin/env bash
# Agents switch gate: replays the reported recording. A herdr dial fails while
# the user is on another tab, then the Agents tab is tapped. The page has to
# wake the target and paint the connecting skeleton; the failure left by the
# earlier dial may not paint for the page at all, and only the dial this visit
# started may turn into an error with Retry.
#
# The page logs one `taildeck agents: <phase>` line per phase change, so the
# order is read from logcat: a stale failure logs `failed` for the reopened
# page, the fix logs `connecting` first. Stills of the switch are kept as the
# visible record. uiautomator is only used once a card is at rest (the loading
# spinner never lets a dump reach the idle state).
#
# Needs CONTROL_URL, a node key seeded against that control plane
# (tool/seed_state.dart, SEED_STATE) and a peer named bangwu on it
# (tool/motion/peer -hostname bangwu). The saved target is a name that peer
# does not answer for, so the dial fails the way the report showed.
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

# A saved herdr target the peer does not answer for, so its dial fails on its
# own, with the sentence the report showed.
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
await_log() { # <tag> <phrase> <limit-s>
  local waited=0
  while [ "$waited" -lt "$3" ]; do
    logs | grep -qF -- "$2" && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# A still every moment of the switch, each with the epoch ms it came back: the
# paint a person would see, not a state sampled afterwards.
capture_window() { # <dir> <tap-ms> <window-ms>
  local dir=$1 tap=$2 window=$3 i=0 file
  mkdir -p "$dir"
  : > "$dir/times.txt"
  while :; do
    i=$((i + 1))
    file=$(printf '%s/frame-%03d.png' "$dir" "$i")
    echo "$(date +%s%3N)" >> "$dir/times.txt"
    adb exec-out screencap -p > "$file" 2> /dev/null || { rm -f "$file"; i=$((i - 1)); sed -i '$d' "$dir/times.txt"; }
    [ $(( $(date +%s%3N) - tap )) -ge "$window" ] && break
    [ "$i" -ge 24 ] && break
  done
}

# The dock is a floating capsule under the page: its label boxes are read from
# a settled dump, the profile's fractions are the fallback.
geometry() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  [ -n "${W:-}" ] || fail "no screen size"
  DOCK_NODES="$((W * 186 / 1000)) $((SH * 917 / 1000))"
  DOCK_AGENTS="$((W * 605 / 1000)) $((SH * 917 / 1000))"
}
tap_dock() { # <x> <y>
  adb shell input tap "$1" "$2" > /dev/null 2>&1 || fail "the dock tap did not land"
}
read_dock() { # <agents-out>
  local agents
  agents=$(python3 "$here/ui.py" "$out/ui.xml" tap Agents 2> /dev/null)
  [ -n "$agents" ] || return 1
  echo "$agents" > "$1"
  note "dock: Agents at [$agents]"
}

# A page at rest is static, so its dump does reach the idle state.
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
rest_text() {
  python3 "$here/ui.py" "$out/ui.xml" texts "$((SH * 5 / 10))" 2> /dev/null | head -3 | tr '\n' ' '
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

geometry
target ghost 22

# The Nodes tab first, so the launch dial fails where the page cannot see it.
adb shell am force-stop "$app" > /dev/null 2>&1 || true
sleep 2
adb logcat -c > /dev/null 2>&1 || true
adb shell "am start -a android.intent.action.VIEW -d 'taildeck://preview/?tab=0&lang=en&splash=0' -n $component" \
  > "$out/launch.txt" 2>&1 || fail "the launch did not start the app"
if wait_home "$app" "$out" "$here" Services 60; then
  note "shell up, dock readable"
else
  note "wait_home could not read the dock; the tap and the phase log still decide"
fi
# The launch dial has to fail on its own, unseen by the page.
sleep 8

# Dock point: the settled page's own box, else the profile's fraction.
agents_point="$DOCK_AGENTS"
rm -f "$out/ui.xml"
if timeout 60 adb shell uiautomator dump /sdcard/ui.xml > "$out/dump.txt" 2>&1 &&
  grep -q 'dumped to' "$out/dump.txt" &&
  timeout 30 adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1; then
  read_dock "$out/dock-agents.txt" && agents_point=$(cat "$out/dock-agents.txt")
fi
echo "$agents_point" > "$out/dock-agents.txt"

adb logcat -c > /dev/null 2>&1 || true
sleep 0.2
# The first screencap of a session pays adb's start; pay it before the tap.
adb exec-out screencap -p > /dev/null 2>&1 || true
started=$(date +%s%3N)
echo "$started" > "$out/tap.txt"
tap_dock $agents_point
capture_window "$out/frames" "$started" 4200

await_log tap 'taildeck agents: ' 12 \
  || fail "tapping the Agents tab started no page; the tap did not land"
first=$(phases | awk '{print $1}')
note "first phase the opened page logged: ${first:-none}"

sleep 1
shot early
sleep 6
shot rest
assert_phases tap "connecting failed"

case "$(rest_has "Can't find node ghost")" in
  ok) note "the recorded unknown-host sentence shows with the card: $(rest_text)" ;;
  missing) fail "the unknown host did not reach the card" ;;
  *) note "no dump at rest; the still carries the card" ;;
esac

# Nothing dials again by itself after that failure.
sleep 5
assert_phases tap "connecting failed"
note "no second dial after the failure"

montage "$out"/frames/frame-0[0-2]*.png -tile 6x -geometry +2+2 \
  -background '#101214' "$out/frames.png" 2> /dev/null || true
note "ok: no stale failure painted; the wake's own failure shows with Retry"
adb uninstall "$app" > /dev/null 2>&1 || true
