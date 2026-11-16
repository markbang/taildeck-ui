#!/usr/bin/env bash
# Tailnet-ready gate: the control plane holds the first netmap for ~2 s, so
# every cold start has a window where the node has no tailnet address and no
# peer table. The gate fails when a page draws that window as content (the OS
# hostname, "No nodes yet", "Can't find node" for a peer that is online) or
# drops its loading state before the app logs that the netmap is in.
# Needs CONTROL_URL, a node key seeded against that control plane
# (tool/seed_state.dart, SEED_STATE) and a peer named bangwu on it
# (tool/motion/peer -hostname bangwu), plus a debuggable APK: the netmap cache
# is dropped through run-as before each start.
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
  timeout 30 adb shell run-as "$app" sh -c 'cat files/tsnet/tailscaled.log*.txt' \
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

dump_page() {
  rm -f "$out/ui.xml"
  timeout 60 adb shell uiautomator dump /sdcard/ui.xml 2> /dev/null | grep -q 'dumped to' || return 1
  timeout 30 adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || return 1
  [ -s "$out/ui.xml" ]
}

page_has() { # <needle>
  python3 "$here/ui.py" "$out/ui.xml" has "$1" 2> /dev/null
}

# The app's own lines, filtered on the host: the log is cleared per run, so one
# read per run is enough (a device-side -s/-t filter returns nothing here).
flutter_log() { timeout 60 adb logcat -d 2> /dev/null | grep -a 'I flutter :'; }

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
    flutter_log | grep -q 'taildeck netstate: Running at' && ready=1
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
  sleep 1
  [ -s "$out/$tag.png" ] || adb exec-out screencap -p > "$out/$tag.png" 2>/dev/null || true
  runs_done=$((runs_done + 1))
  loading_runs=$((loading_runs + loading))
}

check_netstate() { # <tag> <phase>
  local tag=$1 phase=$2 netmap_ms
  flutter_log > "$out/$tag-logcat.txt" || true
  grep -q 'taildeck netstate: no netmap at' "$out/$tag-logcat.txt" \
    || fail "$tag: the cold start never reported a netmap-less status; the window was not exercised"
  # The netmap line comes before readiness; the ready line repeats its time.
  netmap_ms=$(sed -n -e 's/.*netstate: Running at [^,]*, netmap at \([0-9]*\)ms.*/\1/p' \
    -e 's/.*netstate: netmap at \([0-9]*\)ms.*/\1/p' "$out/$tag-logcat.txt" | tail -1)
  [ -n "$netmap_ms" ] || fail "$tag: no ready netstate line; see $tag-logcat.txt"
  [ "$netmap_ms" -ge 1000 ] \
    || fail "$tag: the netmap was in after ${netmap_ms}ms; the delayed-netmap window was not in effect"
  # After ready the page has to be content, not the loading state.
  sleep 0.5
  dump_page || true
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

for phase in node agents; do
  tab=0
  [ "$phase" = agents ] && tab=2
  for n in $(seq 1 "$runs"); do
    tag=$(printf '%s-%02d' "$phase" "$n")
    cold_start "$tag" "tab=$tab&lang=en&splash=0" || fail "$tag: the launch did not start the app"
    sample_until_ready "$tag" "$phase"
    check_netstate "$tag" "$phase"
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
