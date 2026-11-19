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
# SHIP=true (the release's APK under test): the gates in RECORD_GATES run and
# save their evidence but never fail the job, while every other gate blocks.
# The settings stills hit a known qemu freeze on the CI emulator (see
# docs/TESTING.md, "Release gate"); test/theme_open_test.dart in ci guards
# what they guarded.
ship=${SHIP:-false}
record_gates=${RECORD_GATES:-stills}
[ "$ship" = true ] || record_gates=""
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
recorded=0
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

record_only() { # <label>
  case " $record_gates " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# The CI emulator can freeze guest-wide on a page's first frames and lose
# qemu a minute later, on any app version. A gate that fails with the
# emulator gone is run once more on a fresh boot; the loss stays in the
# results and as a warning, and only the retry's outcome counts.
emulator_alive() {
  pgrep -f qemu-system > /dev/null && timeout 15 adb shell true > /dev/null 2>&1
}

reboot_emulator() { # <label>
  local sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}} waited=0
  {
    free -m
    sudo dmesg -T 2> /dev/null | tail -30
  } > "$out/host-lost-$1.txt" 2>&1
  pkill -9 -f qemu-system 2> /dev/null || true
  adb kill-server > /dev/null 2>&1 || true
  sleep 3
  # shellcheck disable=SC2086 # the options are a word list
  nohup "$sdk/emulator/emulator" -port 5554 -avd "${AVD_NAME:-taildeck-api34}" \
    ${EMULATOR_OPTIONS:--no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none} \
    -no-snapshot-save > "$out/emulator-retry-$1.log" 2>&1 &
  timeout 300 adb wait-for-device || return 1
  until [ "$(adb shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ]; do
    [ "$waited" -ge 300 ] && return 1
    sleep 2
    waited=$((waited + 2))
  done
  for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb shell settings put global "$scale" 0 > /dev/null 2>&1 || true
  done
  adb shell input keyevent 82 > /dev/null 2>&1 || true
}

run_gate() { # <label> <timeout-seconds> <command...>
  local label=$1 limit=$2 status
  shift 2
  echo "::group::gate $label"
  echo "[$label] $* (timeout ${limit}s)"
  timeout --kill-after=30 "$limit" "$@"
  status=$?
  echo "::endgroup::"
  return "$status"
}

# Set by gate(): the last gate lost its emulator (and was retried).
gate_lost=false

gate() { # <label> <timeout-seconds> <command...>
  local label=$1 limit=$2 start secs status level=error
  shift 2
  selected "$label" || { skip "$label" "not in GATES"; return 0; }
  if [ "$record" = true ]; then
    level=warning
  elif record_only "$label"; then
    level=warning
    echo "::notice title=android gate $label is record-only::ship mode: $label runs and keeps its evidence, but never fails the release (docs/TESTING.md, Release gate)"
  fi
  start=$(date +%s)
  total=$((total + 1))
  gate_lost=false
  run_gate "$label" "$limit" "$@"
  status=$?
  if [ "$status" -ne 0 ] && ! emulator_alive; then
    gate_lost=true
    note "LOST $label: the emulator died under the gate after $(( $(date +%s) - start ))s; retrying once on a new boot"
    echo "::warning title=android gate $label::emulator lost (qemu died under the gate); retried once on a new boot"
    # The gate's out dir is its last argument; keep the lost attempt beside it.
    [ -d "${*: -1}" ] && rm -rf "${*: -1}-lost" && mv "${*: -1}" "${*: -1}-lost"
    if reboot_emulator "$label"; then
      start=$(date +%s)
      run_gate "$label" "$limit" "$@"
      status=$?
    else
      note "LOST $label: the new emulator did not boot"
    fi
  fi
  secs=$(( $(date +%s) - start ))
  if [ "$status" -eq 0 ]; then
    note "ok $label: ${secs}s"
    return 0
  fi
  if [ "$level" = warning ] && [ "$record" != true ]; then
    recorded=$((recorded + 1))
  else
    failed=$((failed + 1))
  fi
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
stills_status=$?
stills_lost=$gate_lost

# One machine-readable line for the release: "stills: ok 13/13", "stills: lost
# emulator 4/13", "stills: failed 9/13" or "stills: skipped".
stills_outcome() {
  local want got missing
  selected stills || { echo "stills: skipped"; return; }
  want=$(grep -cE '^[[:space:]]*(shot|record) [a-z]' tool/screenshots_android.sh)
  got=$(grep -cE '^[a-z-]+: [0-9]+ bytes$' smoke-shots/summary.txt 2> /dev/null)
  missing=$(grep -cE ': no (screenshot|recording)$' smoke-shots/summary.txt 2> /dev/null)
  if [ "$stills_status" -eq 0 ] && [ "${missing:-0}" -eq 0 ] && [ "${got:-0}" -ge "$want" ] &&
    grep -qx 'done' smoke-shots/summary.txt 2> /dev/null; then
    if [ "$stills_lost" = true ]; then
      echo "stills: ok $got/$want (retried after a lost emulator)"
    else
      echo "stills: ok $got/$want"
    fi
  elif [ "$stills_lost" = true ] || ! pgrep -f qemu-system > /dev/null || ! timeout 15 adb shell true > /dev/null 2>&1 ||
    grep -q 'stopped answering adb' smoke-shots/summary.txt 2> /dev/null; then
    echo "stills: lost emulator ${got:-0}/$want"
  else
    echo "stills: failed ${got:-0}/$want"
  fi
}
stills_outcome | tee "$out/ship-stills.txt" | tee -a "$results"

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
  if [ -n "$seed_state" ]; then
    gate webvideo 600 env CONTROL_URL="$control_url" SEED_STATE="$seed_state" \
      DERP_PORT="${DERP_PORT:-}" PEER_LOG="${PEER_LOG:-/tmp/peer2.log}" \
      bash tool/webvideo_android.sh "$profile" "$app" webvideo
  else
    skip webvideo "no seeded node key"
  fi
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
  skip webvideo "no test control plane"
  skip termtap "no test control plane"
  skip remember "no test control plane"
  skip routing "no test control plane"
  skip netready "no test control plane"
fi

# The emulator can die under a gate; keep the host's memory and kernel log.
pgrep -f qemu-system > /dev/null || note "emulator: the qemu process is gone"
{
  free -m
  ps -eo pid,rss,etime,args --sort=-rss | head -8 | cut -c1-160
  sudo dmesg -T 2> /dev/null | tail -30
} > "$out/host.txt" 2>&1

note "ran $total gates: $((total - failed - recorded)) passed, $failed failed, $recorded failed record-only, $skipped skipped"
if [ "$record" = true ]; then
  note "record mode: $failed gate(s) failed, see summary"
  echo "::notice title=android-smoke record mode::$failed gate(s) failed, see summary"
  cat "$results"
  exit 0
fi
cat "$results"
[ "$failed" -eq 0 ]
