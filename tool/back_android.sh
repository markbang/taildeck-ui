#!/usr/bin/env bash
# System back test on a running emulator: back must close a sheet, pop the page
# under it, return to the first tab, and only leave after a second press. Each
# launch is a real app start driven by the taildeck://preview link.
# Usage: tool/back_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/back_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-back}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
mkdir -p "$out"
rm -f "$out/timing.txt"

# A frozen app is the interesting failure: keep the ANR trace with the log.
dump_anr() {
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  # A failure after the launch can still be an ANR; it gets a verdict too.
  if [ "${launch_anr:-0}" = 0 ] && grep -q "ANR in .*$app" "$out/logcat-fail.txt"; then
    python3 "$here/compositor_stall.py" "$app" < "$out/logcat-fail.txt" \
      | sed 's/^/at the failure: /' >> "$out/summary.txt" || true
  fi
  cat "$out/timing.txt" >> "$out/summary.txt" 2>/dev/null || true
  adb root > /dev/null 2>&1 || true
  sleep 2
  # Only the newest trace: the AVD snapshot carries an old launcher ANR.
  # shellcheck disable=SC2016 # expands on the device
  adb shell 'cat "$(ls -t /data/anr/anr_* | head -n 1)"' > "$out/anr.txt" 2>&1 || true
  adb shell dumpsys activity top > "$out/activity-top.txt" 2>&1 || true
}

fail() {
  stop_watch
  echo "FAIL: $*" | tee -a "$out/summary.txt"
  dump_anr
  exit 1
}

pass() { echo "ok: $*" | tee -a "$out/summary.txt"; }
step() { echo "== $*" | tee -a "$out/summary.txt"; }

adb wait-for-device
# Root reads the app's main thread in /proc and the ANR traces.
adb root > /dev/null 2>&1 || true
adb wait-for-device
if ! adb shell pm path "$app" > /dev/null 2>&1; then
  adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
fi
# After the install: the gates before this one uninstall their own build, and
# resolve-activity answers "No activity found" in prose when nothing is there.
activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null \
  | grep -oE '[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+' | tail -n 1 | tr -d '\r')
case "$activity" in
  */*) ;;
  *) fail "no launcher activity for $app (got '$activity')" ;;
esac

shot() { adb exec-out screencap -p > "$out/$1.png" || true; }

# The app's main thread once a second through the focus window: uptime, its
# stat (state, CPU ticks), wait channel and syscall, until the ANR or the end.
# compositor_stall.py reads it when the ANR report has no CPU list from before.
watch_main() { # <pid> <samples file>
  local pid=$1 file=$2 _i
  : > "$file"
  for _i in $(seq 1 $(("${GATE_FOCUS_WINDOW:-9}" + 3))); do
    {
      echo "--- sample"
      adb shell "cat /proc/uptime /proc/$pid/task/$pid/stat; cat /proc/$pid/task/$pid/wchan; echo; cat /proc/$pid/task/$pid/syscall" 2> /dev/null | tr -d '\r'
    } >> "$file"
    if adb logcat -d 2> /dev/null | grep -q "ANR in .*$app"; then
      echo "--- anr" >> "$file"
      return 0
    fi
    sleep 1
  done
}

watcher=
stop_watch() {
  [ -n "$watcher" ] || return 0
  kill "$watcher" 2> /dev/null || true
  wait "$watcher" 2> /dev/null || true
  watcher=
}

# Waits for the first drawn frame, then a moment for the page after it.
wait_first_frame() {
  local pid
  for _ in $(seq 1 60); do
    if adb logcat -d 2>/dev/null | grep -q "Displayed $app/"; then
      shown_at=$SECONDS
      pid=$(adb shell pidof "$app" 2> /dev/null | tr -d '\r' || true)
      if [ -n "$pid" ]; then
        watch_main "${pid%% *}" "$out/main-samples.txt" &
        watcher=$!
      fi
      sleep 4
      return 0
    fi
    sleep 1
  done
  return 1
}

# One quoted command: an unquoted '&' in the query would split it on the device.
start() { # $1: preview query
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  # The previous Go node finishes its shutdown on this emulator's few cores.
  sleep 3
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?$1' -n $activity" \
    > "$out/launch.txt" 2>&1 || return 1
  grep -q "Activity: $app/" "$out/launch.txt" || return 1
  shown_at=$SECONDS
  if ! wait_first_frame; then
    anr_after_wait && return 1
    fail "no frame from $app within 60s"
  fi
  # No dock marker: the launches with a sheet cover it, and wait_sheet is what
  # proves that sheet opened. A launch with ssh=demo opens the terminal, whose
  # route is its own.
  if ! wait_home "$app" "$out" "$here" '' 30 'shell|terminal'; then
    anr_after_wait && return 1
    fail "the shell did not settle for $1; see launch.txt"
  fi
  if ! gate_survived_focus "$app" "$shown_at" "$out/summary.txt"; then
    anr_verdict
    return 1
  fi
  stop_watch
  timing "$1"
}

# A wait that failed inside the focus window may have met the ANR's kill:
# the window is waited out, and an ANR found takes the same verdict.
anr_after_wait() {
  local line
  while [ $((SECONDS - shown_at)) -lt "${GATE_FOCUS_WINDOW:-9}" ]; do sleep 1; done
  line=$(adb logcat -d 2>/dev/null | grep -m1 "ANR in .*$app" || true)
  [ -n "$line" ] || return 1
  echo "$line" | cut -c1-200 >> "$out/summary.txt"
  anr_verdict
}

# Every ANR of a launch, whichever wait met it: the report and its CPU list
# land before the kill, then tool/compositor_stall.py judges the log.
anr_verdict() {
  local n
  launch_anr=1
  anrs=$((anrs + 1))
  n=$anrs
  if [ -n "$watcher" ]; then
    wait "$watcher" 2> /dev/null || true
    watcher=
  fi
  mv "$out/main-samples.txt" "$out/main-samples-$n.txt" 2> /dev/null || : > "$out/main-samples-$n.txt"
  for _ in $(seq 1 20); do
    adb shell pidof "$app" > /dev/null 2>&1 || break
    sleep 1
  done
  adb logcat -d > "$out/logcat-anr-$n.txt" 2>&1 || true
  # shellcheck disable=SC2016 # expands on the device
  adb shell 'cat "$(ls -t /data/anr/anr_* | head -n 1)"' > "$out/anr-trace-$n.txt" 2>&1 || true
  if python3 "$here/compositor_stall.py" "$app" "$out/main-samples-$n.txt" "$out/anr-trace-$n.txt" \
    < "$out/logcat-anr-$n.txt" | tee -a "$out/summary.txt"; then
    launch_stall=1
  fi
}

# The launch's cost as Android and the app each saw it.
timing() { # $1: preview query
  local log
  log=$(adb logcat -d 2>/dev/null)
  echo "  $1: $(grep -m1 -oE 'Displayed [^ ]+ for user 0: \+[0-9a-z]+' <<< "$log" | sed 's/.*: //'), \
$(grep -m1 -oE 'taildeck first frame: .*' <<< "$log" | sed 's/taildeck //'), \
$(grep -m1 -oE 'taildeck frames: .*' <<< "$log" | sed 's/taildeck //')" >> "$out/timing.txt"
}

# One retry for any failed cold start. An ANR on the retry fails the gate unless
# both were the emulator's compositor (tool/compositor_stall.py: another process
# froze too and the app is absent from the ANR's CPU top), which a phone does
# not have: that earns a third start, twice per run at most. A third stall
# still fails, as the emulator's.
anrs=0
stall_retries=0
launch() { # $1: preview query
  local attempt stalls=0
  for attempt in 1 2 3; do
    launch_anr=0
    launch_stall=0
    start "$1" && return 0
    stalls=$((stalls + launch_stall))
    if [ "$attempt" -eq 1 ]; then
      echo "retrying $1" | tee -a "$out/summary.txt"
      continue
    fi
    [ "$launch_anr" = 1 ] || fail "am start or first frame failed for $1, see launch.txt"
    if [ "$attempt" -eq 2 ] && [ "$stalls" -eq 2 ] && [ "$stall_retries" -lt 2 ]; then
      stall_retries=$((stall_retries + 1))
      echo "retrying $1 a third time: both ANRs were compositor stalls" | tee -a "$out/summary.txt"
      continue
    fi
    [ "$stalls" -lt 3 ] || fail "$1: emulator compositor stall on 3 cold starts in a row"
    fail "$1: the app stopped answering input on $attempt cold starts in a row"
  done
}

back() { # $1: seconds to settle (default 1.2)
  adb shell input keyevent 4 > /dev/null 2>&1 || fail "could not send back"
  sleep "${1:-1.2}"
}

steps() { adb logcat -d 2>/dev/null | grep -oE 'taildeck back: (keyboard|page|tab|askExit|exit)' | sed 's/taildeck back: //' || true; }
count() { steps | grep -cx "$1" || true; }

# The preview sheet announces itself before it opens, which is the only signal
# the test can read: Flutter has no view ids for uiautomator.
wait_sheet() { # $1: sheet kind
  for _ in $(seq 1 60); do
    if adb logcat -d 2>/dev/null | grep -q "taildeck preview: sheet=$1"; then
      sleep 3
      return 0
    fi
    sleep 1
  done
  fail "sheet=$1 never opened; logcat: $(adb logcat -d 2>/dev/null | grep 'taildeck preview' | tail -n 3 | tr '\n' ' ')"
}

# The app answers back with a log line after the sheet's animation. A single
# grep reads the log too early on a loaded emulator, so the answer is waited
# for; the state it names is still asserted exactly once afterwards.
wait_log() { # <pattern> <seconds>
  local _i
  for _i in $(seq 1 "$2"); do
    adb logcat -d 2>/dev/null | grep -q "$1" && return 0
    sleep 1
  done
  return 1
}

expect_count() { # $1: step, $2: exactly this many
  local seen
  seen=$(count "$1")
  [ "$seen" -eq "$2" ] || fail "'$1' happened $seen times, expected $2; steps: $(steps | tr '\n' ' ')"
}

alive() { # $1: what we just did
  pid=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
  [ -n "$pid" ] || fail "$1: $app is gone"
  adb shell dumpsys activity activities 2>/dev/null | grep -q "topResumedActivity.*$app" \
    || fail "$1: $app is not the resumed activity"
}

# Presses back until the shell answers with [step]; prints how many presses it
# took, and fails the other steps were taken instead.
press_until() { # $1: step, $2: most presses to try
  local wanted=$1
  local presses=0
  while [ "$presses" -lt "$2" ]; do
    presses=$((presses + 1))
    back
    if [ "$(count "$wanted")" -gt 0 ]; then
      echo "$presses"
      return 0
    fi
  done
  fail "back never reached '$wanted' in $2 presses; steps: $(steps | tr '\n' ' ')"
}

only_steps() { # $*: the steps that may appear
  local seen
  seen=$(steps | sort -u)
  for item in $seen; do
    case " $* " in
      *" $item "*) ;;
      *) fail "unexpected back step '$item'; steps: ${seen:-none}" ;;
    esac
  done
}

# 1. A sheet answers back on its own route; the page under it answers next.
for sheet in ssh service agent key dialog; do
  step "sheet=$sheet"
  launch "preview=1&node=devbox&sheet=$sheet"
  wait_sheet "$sheet"
  shot "sheet-$sheet-open"
  back
  wait_log 'taildeck preview: sheet closed' 10 \
    || fail "sheet=$sheet: back did not close the sheet in 10 s; logcat: $(adb logcat -d 2>/dev/null | grep -E 'taildeck (preview|back)' | tail -n 3 | tr '\n' ' ')"
  expect_count page 0
  alive "sheet=$sheet closed"
  shot "sheet-$sheet-closed"
  back
  expect_count page 1
  alive "page under sheet=$sheet"
  shot "sheet-$sheet-page-closed"
  pass "sheet=$sheet: back closed the sheet, then the page under it"
done

# 2. The terminal page leaves without ending the app.
step terminal
launch "preview=1&ssh=demo"
shot terminal-open
press_until page 3 > /dev/null
alive "terminal left"
shot terminal-closed
pass terminal

# 3. A secondary tab returns to Nodes.
step tab
launch "preview=1&tab=2"
shot tab-agents
press_until tab 2 > /dev/null
alive "tab fallback"
shot tab-nodes
pass "tab returned to the first tab"

# 4. The first tab's list asks once, then leaves on a second press.
step exit
launch "preview=1"
shot exit-root
back
[ "$(count askExit)" -eq 1 ] || fail "first press on the nodes list did not ask for a second; steps: $(steps | tr '\n' ' ')"
alive "exit hint"
shot exit-hint
sleep 3
back
[ "$(count askExit)" -eq 2 ] || fail "a press after the window did not ask again; steps: $(steps | tr '\n' ' ')"
back 0.3
[ "$(count exit)" -eq 1 ] || fail "second press inside the window did not leave; steps: $(steps | tr '\n' ' ')"
for _ in $(seq 1 10); do
  adb shell dumpsys activity activities 2>/dev/null | grep -q "topResumedActivity.*$app" || break
  sleep 1
done
if adb shell dumpsys activity activities 2>/dev/null | grep -q "topResumedActivity.*$app"; then
  fail "the app is still the resumed activity after the second press"
fi
only_steps askExit exit
shot exit-left
pass "exit asked once, then left"

adb logcat -d > "$out/logcat.txt" 2>&1 || true
cat "$out/timing.txt" >> "$out/summary.txt" 2>/dev/null || true
echo "all back cases passed" | tee -a "$out/summary.txt"
