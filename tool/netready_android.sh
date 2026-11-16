#!/usr/bin/env bash
# Tailnet-ready gate: the control plane holds the first netmap for ~2 s, so
# every cold start has a window where the node has no tailnet address and no
# peer table. The gate fails when a page draws that window as content (the OS
# hostname, "No nodes yet", "Can't find node" for a peer that is online) or
# drops its loading state before the app logs that the netmap is in.
# Needs CONTROL_URL, AUTH_KEY and a peer named bangwu on that control plane
# (tool/motion/peer -hostname bangwu), plus a debuggable APK: the netmap cache
# is dropped through run-as before each start.
# Usage: CONTROL_URL=http://10.0.2.2:8080 AUTH_KEY=tskey-test \
#          tool/netready_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/netready_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-netready}
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-}
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

fail() {
  echo "FAIL: $*" | tee -a "$summary"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui-fail.xml" > /dev/null 2>&1 || true
  adb uninstall "$app" > /dev/null 2>&1 || true
  exit 1
}
note() { echo "$*" | tee -a "$summary"; }

[ -n "$control_url" ] && [ -n "$auth_key" ] \
  || { echo "CONTROL_URL and AUTH_KEY are required: a test control plane is what signs the node in"; exit 2; }

adb wait-for-device
if [ -n "${DERP_PORT:-}" ]; then
  adb reverse "tcp:$DERP_PORT" "tcp:$DERP_PORT" > /dev/null 2>&1 || true
fi
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell settings put system screen_off_timeout 2147483647 > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true

ui() {
  local attempt
  for attempt in 1 2 3; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if python3 "$here/ui.py" "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

wait_for() { # <marker> <seconds>
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    ui has "$1" && return 0
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

screen_size() {
  adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r'
}

# One dump per check: a page is read once and scanned for every string it may
# not show, so the window costs one dump, not one per string.
dump_page() {
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
  [ -s "$out/ui.xml" ]
}

page_has() { # <needle>
  python3 "$here/ui.py" "$out/ui.xml" has "$1" 2> /dev/null
}

# --- sign in once, then give the saved session a herdr target on the peer -----

adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"

component=${LAUNCH_ACTIVITY:-$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r' || true)}
[ -n "$component" ] || fail "no launcher activity for $app"

adb shell am force-stop "$app" > /dev/null 2>&1 || true
adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?login=1&lang=en&splash=0' -n $component" \
  > "$out/login-launch.txt" 2>&1 || true
wait_for "Continue in browser" 60 || fail "the login page never opened; see ui.xml"

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
wait_home "$app" "$out" "$here" Services 120 || fail "sign-in did not reach the shell; see ui.xml"
note "signed in against $control_url"

adb shell am force-stop "$app" > /dev/null 2>&1 || true
config=$(adb shell run-as "$app" cat files/config.json 2> /dev/null | tr -d '\r' || true)
[ -n "$config" ] || fail "no saved config after sign-in (is the APK debuggable?)"
patched=$(printf '%s' "$config" | python3 -c '
import json, sys
cfg = json.load(sys.stdin)
cfg.update({"herdrNode": "bangwu", "herdrUser": "root", "herdrPort": 22, "herdrAuth": "tailscale"})
print(json.dumps(cfg, separators=(",", ":")))
')
# base64 keeps the pty from rewriting the JSON on its way in.
encoded=$(printf '%s' "$patched" | base64 -w0)
adb shell "run-as $app sh -c 'echo $encoded | base64 -d > files/config.json'" > /dev/null 2>&1 || true
adb shell run-as "$app" cat files/config.json 2> /dev/null | tr -d '\r' | grep -q '"herdrNode":"bangwu"' \
  || fail "the saved herdr target was not written; see ui.xml"
adb shell run-as "$app" test -f files/tsnet/tailscaled.state \
  || fail "run-as cannot read the app's state dir; this gate needs a debuggable APK"
note "saved herdr target: bangwu"

# --- 20 cold starts per page, sampling the window ----------------------------

# Until the app logs that the netmap is in, these strings mean a page drew the
# netmap-less status as the node. bangwu is online, so they are wrong after it
# is in as well, except Retry, which a real herdr failure may offer.
forbidden_common=("Can't find node" "Connect herdr")
forbidden_node=("localhost" "No nodes yet")
forbidden_agents=("localhost" "No nodes yet" "Retry")

cold_start() { # <tag> <query>
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  # Without this the node answers from its on-disk netmap in ~70 ms and the
  # window this gate exists for never opens.
  adb shell run-as "$app" rm -rf files/tsnet/profile-data > /dev/null 2>&1 || true
  curl -fsS -X POST "$hold_url" > /dev/null 2>&1 \
    || fail "no held-netmap control plane at $hold_url (start tool/motion/control -hold-map)"
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?$2' -n $component" \
    > "$out/$1-launch.txt" 2>&1 || return 1
  grep -q "Activity: $app/" "$out/$1-launch.txt"
}

# Samples the page until the ready line is in logcat, and counts the runs that
# saw the loading state: a run whose dumps all landed after the netmap proves
# nothing, so the total has to stay above zero.
loading_runs=0
runs_done=0
sample_until_ready() { # <tag> <phase>
  local tag=$1 phase=$2 t0 loading=0 forbidden=()
  t0=$(date +%s%3N)
  case "$phase" in
    node) forbidden=("${forbidden_common[@]}" "${forbidden_node[@]}") ;;
    agents) forbidden=("${forbidden_common[@]}" "${forbidden_agents[@]}") ;;
  esac
  while :; do
    local ready=0 needle
    if dump_page; then
      page_has "Connecting to the tailnet" && loading=1
      [ -s "$out/$tag.png" ] || adb exec-out screencap -p > "$out/$tag.png" 2>/dev/null || true
    fi
    # The ready line can land between the dump and this read: a sample taken
    # after it is content, so it gets no pre-ready check.
    if adb logcat -d 2>/dev/null | grep -q 'taildeck netstate: Running at'; then
      ready=1
    else
      for needle in "${forbidden[@]}"; do
        page_has "$needle" && fail "$tag: the $phase page shows \"$needle\" while the netmap is not in"
      done
    fi
    [ "$ready" -eq 1 ] && break
    if [ $(( $(date +%s%3N) - t0 )) -gt 15000 ]; then
      [ -s "$out/$tag.png" ] || adb exec-out screencap -p > "$out/$tag.png" 2>/dev/null || true
      fail "$tag: no \"netstate: Running\" line within 15 s; the page may be stuck in loading"
    fi
    sleep 0.2
  done
  runs_done=$((runs_done + 1))
  loading_runs=$((loading_runs + loading))
}

check_netstate() { # <tag> <phase>
  local tag=$1 phase=$2 netmap_ms
  adb logcat -d 2>/dev/null > "$out/$tag-logcat.txt" || true
  grep -q 'taildeck netstate: no netmap at' "$out/$tag-logcat.txt" \
    || fail "$tag: the cold start never reported a netmap-less status; the window was not exercised"
  netmap_ms=$(sed -n 's/.*netstate: Running at [^,]*, netmap at \([0-9]*\)ms.*/\1/p' "$out/$tag-logcat.txt" | tail -1)
  [ -n "$netmap_ms" ] || fail "$tag: no ready netstate line; see $tag-logcat.txt"
  [ "$netmap_ms" -ge 1000 ] \
    || fail "$tag: the netmap was in after ${netmap_ms}ms; the delayed-netmap window was not in effect"
  # After ready the page has to be content, not the loading state.
  sleep 1
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
