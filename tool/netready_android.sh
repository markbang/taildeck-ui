#!/usr/bin/env bash
# Tailnet-ready gate: the control plane holds the first netmap for ~2 s, so
# every cold start has a window where the node has no tailnet address and no
# peer table. The gate fails when a page draws that window as content (the OS
# hostname, "No nodes yet", "Can't find node" for a peer that is online) or
# drops its loading state before the app logs that the netmap is in.
# Needs CONTROL_URL, a node key seeded against that control plane
# (tool/seed_state.dart, SEED_STATE) and a peer named bangwu on it
# (tool/motion/peer -hostname bangwu), and adb root (google_apis emulator): the
# node key is pushed into the app's files and its netmap cache dropped with it.
# Usage: CONTROL_URL=http://10.0.2.2:8080 SEED_STATE=/tmp/seed/tailscaled.state \
#          tool/netready_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/netready_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-netready}
control_url=${CONTROL_URL:-}
runs=${RUNS:-20}
# The runner's side of the control plane: POST arms one held-netmap window, so
# every cold start meets the same 2 s delay.
hold_url=${HOLD_URL:-http://127.0.0.1:8080/__hold}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"

# Every adb call in a loop gets a bound: a stuck adb once held this job open
# until its timeout instead of failing the run.
fail() {
  echo "FAIL: $*" | tee -a "$summary"
  timeout 30 adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  # The node's own log says why it never reached Running.
  timeout 30 adb shell "cat /data/data/$app/files/tsnet/tailscaled.log*.txt" \
    > "$out/tsnet-fail.txt" 2> /dev/null || true
  timeout 30 adb pull /sdcard/ui.xml "$out/ui-fail.xml" > /dev/null 2>&1 || true
  timeout 60 adb uninstall "$app" > /dev/null 2>&1 || true
  exit 1
}
note() { echo "$*" | tee -a "$summary"; }

[ -n "$control_url" ] \
  || { echo "CONTROL_URL is required: the config has to point the node at the test control plane"; exit 2; }

adb wait-for-device
if [ -n "${DERP_PORT:-}" ]; then
  adb reverse "tcp:$DERP_PORT" "tcp:$DERP_PORT" > /dev/null 2>&1 || true
fi
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell settings put system screen_off_timeout 2147483647 > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true

# --- start signed in: a seeded node key and a config on disk -----------------

adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"

component=${LAUNCH_ACTIVITY:-$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r' || true)}
[ -n "$component" ] || fail "no launcher activity for $app"

# The login page costs taps that miss on a loaded emulator (and a missed auth
# key silently opens the browser flow), so the gate starts from a node key
# seeded against this control plane (tool/seed_state.dart).
seed=${SEED_STATE:-/tmp/seed/tailscaled.state}
hostname=${SEED_HOSTNAME:-taildeck}
[ -s "$seed" ] || fail "no seeded node state at $seed (run tool/seed_state.dart first)"
mkdir -p "$out/files"

# Root, not run-as: pushing a 2.5 kB state file through run-as means base64 over
# the pty, and the debug emulator image allows adb root.
adb root > /dev/null 2>&1 || true
adb wait-for-device
[ "$(adb shell id -u 2> /dev/null | tr -d '\r')" = "0" ] \
  || fail "adb root is required to seed the app's files (needs a google_apis emulator)"
data=/data/data/$app
adb shell "mkdir -p $data/files/tsnet" > /dev/null 2>&1 || fail "could not create $data/files"
note "app installed, activity $component"
adb push "$seed" "$data/files/tsnet/tailscaled.state" > "$out/push.txt" 2>&1 \
  || fail "could not push the node key; see push.txt"
printf '{"hostname":"%s","controlURL":"%s","signedIn":true,"herdrNode":"bangwu","herdrUser":"root","herdrPort":22,"herdrAuth":"tailscale"}' \
  "$hostname" "$control_url" > "$out/files/config.json"
adb push "$out/files/config.json" "$data/files/config.json" >> "$out/push.txt" 2>&1 \
  || fail "could not push the config; see push.txt"
appuid=$(adb shell stat -c %u "$data" 2> /dev/null | tr -d '\r')
adb shell "chown -R $appuid:$appuid $data/files" > /dev/null 2>&1 || fail "could not chown $data/files"
# adbd labels a pushed file from packages.list, which can still name the old
# uid right after a reinstall; the app then cannot open its own config (an MLS
# category denial) and starts on the login page. The data dir's label is right.
ctx=$(adb shell stat -c %C "$data" 2> /dev/null | tr -d '\r')
[ -n "$ctx" ] || fail "could not read the SELinux label of $data"
adb shell "chcon -R $ctx $data/files" > /dev/null 2>&1 || fail "could not relabel $data/files as $ctx"
got_ctx=$(adb shell stat -c %C "$data/files/config.json" 2> /dev/null | tr -d '\r')
[ "$got_ctx" = "$ctx" ] || fail "config.json is labelled ${got_ctx:-nothing}, want $ctx"
size=$(adb shell stat -c %s "$data/files/tsnet/tailscaled.state" 2> /dev/null | tr -d '\r')
[ "$size" = "$(stat -c%s "$seed")" ] \
  || fail "the node key landed at ${size:-nothing} bytes, want $(stat -c%s "$seed")"
want_sha=$(sha256sum "$seed" | cut -d' ' -f1)
got_sha=$(adb shell sha256sum "$data/files/tsnet/tailscaled.state" 2> /dev/null | tr -d '\r' | cut -d' ' -f1)
[ "$got_sha" = "$want_sha" ] \
  || fail "the node key is not intact on the device ($got_sha, want $want_sha)"
note "node key pushed: $size bytes, sha ${want_sha:0:12}, herdr target bangwu"


dump_page() {
  rm -f "$out/ui.xml"
  timeout 60 adb shell uiautomator dump /sdcard/ui.xml 2> /dev/null | grep -q 'dumped to' || return 1
  timeout 30 adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || return 1
  [ -s "$out/ui.xml" ]
}

page_has() { # <needle>
  python3 "$here/ui.py" "$out/ui.xml" has "$1" 2> /dev/null
}

# These strings are wrong on either page at any time: bangwu is online, and a
# node that is not found was looked up before its netmap. Retry is different:
# a real herdr failure may offer it, so it is only forbidden while loading.
forbidden_common=("Can't find node" "Connect herdr" "localhost" "No nodes yet")

# The app's own lines, filtered on the host: the log is cleared per run, so one
# read per run is enough (a device-side -s/-t filter returns nothing here).
flutter_log() { timeout 60 adb logcat -d 2> /dev/null | grep -a 'I flutter :'; }

cold_start() { # <tag> <query>
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  # Without this the node answers from its on-disk netmap in ~70 ms and the
  # window this gate exists for never opens.
  adb shell rm -rf "$data/files/tsnet/profile-data" > /dev/null 2>&1 || true
  curl -fsS -X POST "$hold_url?host=$hostname" > /dev/null 2>&1 \
    || fail "no held-netmap control plane at $hold_url (start tool/motion/control -hold-map)"
  adb logcat -c > /dev/null 2>&1 || true
  # No -W: the page is what this gate samples, not the first frame.
  adb shell "am start -a android.intent.action.VIEW -d 'taildeck://preview/?$2' -n $component" \
    > "$out/$1-launch.txt" 2>&1 || return 1
  grep -q "^Starting: Intent" "$out/$1-launch.txt"
}

# A plain start, no window armed: proves the seeded session signs in and lists
# the peer before the gate starts judging the window.
preflight() {
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  adb shell rm -rf "$data/files/tsnet/profile-data" > /dev/null 2>&1 || true
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -a android.intent.action.VIEW -d 'taildeck://preview/?tab=0&lang=en&splash=0' -n $component" \
    > "$out/preflight-launch.txt" 2>&1 || return 1
  local t0 waited
  t0=$(date +%s%3N)
  while [ $(( $(date +%s%3N) - t0 )) -lt 40000 ]; do
    dump_page && page_has "Services" && page_has "bangwu" && {
      preflight_ms=$(( $(date +%s%3N) - t0 ))
      return 0
    }
    sleep 1
  done
  return 1
}

# Samples the page until it shows content, and counts the runs that saw the
# loading state: a run whose samples all landed after the netmap proves nothing,
# so the total has to stay above zero.
loading_runs=0
runs_done=0
sample_until_ready() { # <tag> <phase>
  local tag=$1 phase=$2 t0 loading=0 ready=0 needle
  t0=$(date +%s%3N)
  while :; do
    ready=0
    flutter_log | grep -q 'taildeck netstate: ready at' && ready=1
    # The page is read before the log: a sample that still shows the loading
    # card while the log says ready is the transition, not a bug.
    if dump_page; then
      [ -s "$out/$tag.png" ] || adb exec-out screencap -p > "$out/$tag.png" 2>/dev/null || true
      if [ "$ready" -eq 0 ]; then
        for needle in "${forbidden_common[@]}"; do
          page_has "$needle" && fail "$tag: the $phase page shows \"$needle\" before the netmap is in"
        done
      fi
      if page_has "Connecting to the tailnet"; then
        loading=1
        if [ "$phase" = agents ] && page_has "Retry"; then
          fail "$tag: the Agents page offers Retry while the tailnet is still loading"
        fi
      fi
    fi
    [ "$ready" -eq 1 ] && break
    # A debug cold start on a loaded emulator can take 10 s to reach the node.
    [ $(( $(date +%s%3N) - t0 )) -gt 40000 ] \
      && fail "$tag: the $phase page never left its loading state; see ui.xml"
    sleep 0.3
  done
  # One more read after the log says ready: the page has to be content now.
  content_ms=$(( $(date +%s%3N) - t0 ))
  sleep 1
  [ -s "$out/$tag.png" ] || adb exec-out screencap -p > "$out/$tag.png" 2>/dev/null || true
  loading_runs=$((loading_runs + loading))
  runs_done=$((runs_done + 1))
}

# Returns 1 when the run met no delayed netmap: the arming raced another map
# request, so the run proves nothing and is repeated instead of judged.
netmap_seen_ms=''
check_netstate() { # <tag> <phase>
  local tag=$1 phase=$2 netmap_ms
  flutter_log > "$out/$tag-logcat.txt" || true
  # The netmap line comes before readiness; the ready line repeats its time.
  netmap_ms=$(sed -n -e 's/.*netstate: ready at [^(]*(Running: [^,]*, netmap: \([0-9]*\)ms.*/\1/p' \
    -e 's/.*netstate: netmap at \([0-9]*\)ms.*/\1/p' "$out/$tag-logcat.txt" | tail -1)
  [ -n "$netmap_ms" ] || { note "$tag: no netstate line, retrying"; return 1; }
  netmap_seen_ms=$netmap_ms
  [ "$netmap_ms" -ge 1000 ] || { note "$tag: netmap at ${netmap_ms}ms, retrying"; return 1; }
  grep -q 'taildeck netstate: waiting at' "$out/$tag-logcat.txt" \
    || { note "$tag: no netmap-less status, retrying"; return 1; }
  # After ready the page has to be content, not the loading state. The verdict
  # is the first dump that carries the page at all: while the emulator's
  # renderer stalls (an 8 s SwapBuffers once), uiautomator gets a FlutterView
  # with no semantics nodes, which is no page rather than a page without bangwu.
  sleep 0.5
  local t0 waited
  t0=$(date +%s%3N)
  until dump_page && page_has "Services"; do
    [ $(( $(date +%s%3N) - t0 )) -gt 20000 ] \
      && fail "$tag: no page tree in 20 s after the netmap (renderer stalled?); see ui.xml"
    sleep 0.5
  done
  waited=$(( $(date +%s%3N) - t0 ))
  [ "$waited" -lt 3000 ] || note "$tag: page tree back after ${waited}ms"
  local needle
  for needle in "${forbidden_common[@]}"; do
    page_has "$needle" && fail "$tag: the $phase page shows \"$needle\" after the netmap is in"
  done
  case "$phase" in
    node)
      page_has "bangwu" || fail "$tag: the node page never listed the online peer after the netmap"
      page_has "No nodes yet" && fail "$tag: the node page drew an empty tailnet while bangwu is online"
      ;;
    agents)
      page_has "Can't find node" && fail "$tag: the Agents page could not resolve an online peer"
      ;;
  esac
  note "$tag: netmap at ${netmap_ms}ms, ready line present, no forbidden string"
}

preflight || fail "the seeded session never reached the node page; see preflight-launch.txt"
note "preflight: node page with bangwu after ${preflight_ms}ms, no held netmap"

for phase in node agents; do
  tab=0
  [ "$phase" = agents ] && tab=2
  for n in $(seq 1 "$runs"); do
    tag=$(printf '%s-%02d' "$phase" "$n")
    for attempt in 1 2 3; do
      cold_start "$tag" "tab=$tab&lang=en&splash=0" || fail "$tag: the launch did not start the app"
      sample_until_ready "$tag" "$phase"
      # A run whose held netmap never applied is setup noise, not a verdict.
      check_netstate "$tag" "$phase" && break
      [ "$attempt" -eq 3 ] && fail "$tag: no delayed netmap in three starts"
    done
    # The app's own clock is what says the skeleton was short; the wall clock
    # includes a slow emulator's launch.
    case "$tag" in *-01)
      note "$tag: netmap at ${netmap_seen_ms}ms, skeleton left after wall ${content_ms}ms"
      [ "$netmap_seen_ms" -le 12000 ] \
        || fail "$tag: the netmap took ${netmap_seen_ms}ms, the skeleton waited for it" ;;
    esac
  done
done

[ "$loading_runs" -gt 0 ] \
  || fail "no run sampled the loading state; the window was over before the first dump"

# Evidence: one still per run, and a contact sheet per page.
for phase in node agents; do
  montage "$out"/$phase-*.png -tile 5x4 -geometry +4+4 -background '#101214' \
    "$out/$phase-runs.png" 2>/dev/null || true
done
note "ok: $runs cold starts per page; $loading_runs of $runs_done sampled the loading window"
adb uninstall "$app" > /dev/null 2>&1 || true
