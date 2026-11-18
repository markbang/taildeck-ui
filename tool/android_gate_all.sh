#!/usr/bin/env bash
# Every on-device gate of the android-smoke workflow against one emulator boot:
# the gates run in sequence, each with its own timeout and its own line in
# gate-results.txt, and a failing gate never stops the ones after it, so one
# run shows every breakage at once and the exit code is the failure count.
#
# Needs APK (the app under test) and PROFILE (the profile APK the cold-start
# loops use); NODEPAGE (a debug APK with the demo dataset) turns on the preview
# gates, NETREADY_APK (a debuggable APK without demo data) the netmap-window
# gate, and SEED_STATE plus CONTROL_URL and DERP_PORT feed the gates that sign
# a node in. The gates that need none of that are skipped.
# Usage: APK=build/profile.apk PROFILE=build/profile.apk tool/android_gate_all.sh
set -uo pipefail

app=${APP_ID:-top.bangwu.taildeck}
out=${GATE_OUT:-gates}
apk=${APK:?APK is required: the app under test}
profile=${PROFILE:-$apk}
demo=${NODEPAGE:-}
netready_apk=${NETREADY_APK:-$demo}
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-tskey-test}
seed_state=${SEED_STATE:-}
# GATES: "all" (the default) or a space-separated list of gate labels, so one
# gate can be re-run on its own while a breakage is being chased.
gates=${GATES:-all}
# RECORD=true (android-smoke's dispatch-only `record` input): every gate still
# runs and reports, but failures are warnings and the exit code is 0, for
# "before" and evidence runs that are expected to show a bug.
record=${RECORD:-false}
level=error
[ "$record" = true ] && level=warning
mkdir -p "$out"
results="$out/gate-results.txt"
: > "$results"

note() { echo "$*" | tee -a "$results"; }

# The emulator boots before this script runs; the launch stamp the workflow
# wrote before the runner started is what the AVD snapshot cache shortens (a
# quickboot resumes the guest, so its own uptime says nothing).
launched=$(cat /tmp/emulator-launch 2>/dev/null || true)
if [ -n "$launched" ]; then
  note "boot: device usable $(( $(date +%s) - launched ))s after the launch stamp"
fi
adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' | sed 's/^/boot: android /' | tee -a "$results"

failed=0
total=0
skipped=0

skip() { # <label> <reason>
  skipped=$((skipped + 1))
  note "skip $1: $2"
}

selected() { # <label>
  case " $gates " in
    *" all "*|*" $1 "*) return 0 ;;
  esac
  return 1
}

gate() { # <label> <timeout-seconds> <command...>
  local label=$1 limit=$2 start secs status
  shift 2
  selected "$label" || { skip "$label" "not in GATES"; return 0; }
  start=$(date +%s)
  total=$((total + 1))
  echo "::group::gate $label"
  echo "[$label] $* (timeout ${limit}s)"
  timeout --kill-after=30 "$limit" "$@"
  status=$?
  secs=$(( $(date +%s) - start ))
  echo "::endgroup::"
  if [ "$status" -eq 0 ]; then
    note "ok $label: ${secs}s"
    return 0
  fi
  failed=$((failed + 1))
  if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
    note "FAIL $label: timed out after ${secs}s (limit ${limit}s)"
    echo "::$level title=android gate $label::timed out after ${secs}s; see the $label summary in the artifact"
  else
    note "FAIL $label: exit $status after ${secs}s"
    echo "::$level title=android gate $label::exit $status after ${secs}s; see the $label summary in the artifact"
  fi
  return "$status"
}

# Fast gates first, the long cold-start loops last: a breakage early still
# leaves the loop evidence from the same run.
gate cold-start 600 bash tool/smoke_android.sh "$apk" "$app" smoke
gate splash 600 bash tool/splash_shots.sh "$apk" "$app" smoke-splash
gate agents 600 bash tool/agents_android.sh "$apk" "$app" smoke-agents
gate stills 600 bash tool/screenshots_android.sh "$apk" "$app" smoke-shots

if [ -n "$demo" ]; then
  gate tabs 900 bash tool/tabs_android.sh "$demo" "$app" smoke-tabs
  gate back 900 bash tool/back_android.sh "$demo" "$app" smoke-back
  gate ping 600 bash tool/ping_android.sh "$demo" "$app" smoke-ping
  gate node 600 bash tool/nodepage_android.sh "$demo" "$app" smoke-node
else
  skip tabs "no demo APK"
  skip back "no demo APK"
  skip ping "no demo APK"
  skip node "no demo APK"
fi

if [ -n "$control_url" ]; then
  gate termtap 1500 bash tool/termtap_record.sh "$profile" "$app" termtap
  gate remember 1200 env CONTROL_URL="$control_url" AUTH_KEY="$auth_key" \
    bash tool/remember_record.sh "$profile" "$app" remember
  gate routing 1800 env CONTROL_URL="$control_url" AUTH_KEY="$auth_key" \
    DERP_PORT="${DERP_PORT:-}" bash tool/routing_android.sh "$profile" "$app" routing
  if [ -n "$netready_apk" ] && [ -n "$seed_state" ]; then
    gate netready 2700 env CONTROL_URL="$control_url" SEED_STATE="$seed_state" \
      DERP_PORT="${DERP_PORT:-}" bash tool/netready_android.sh "$netready_apk" "$app" netready
  else
    skip netready "no demo APK or seeded node key"
  fi
else
  skip termtap "no test control plane"
  skip remember "no test control plane"
  skip routing "no test control plane"
  skip netready "no test control plane"
fi

note "ran $total gates: $((total - failed)) passed, $failed failed, $skipped skipped"
if [ "$record" = true ]; then
  note "record mode: $failed gate(s) failed, see summary"
  echo "::notice title=android-smoke record mode::$failed gate(s) failed, see summary"
  cat "$results"
  exit 0
fi
cat "$results"
[ "$failed" -eq 0 ]
