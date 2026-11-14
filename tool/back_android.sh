#!/usr/bin/env bash
# System back test on a running emulator: back must close a sheet, pop the page
# under it, return to the first tab, and only leave after a second press. Each
# launch is a real app start driven by the taildeck://preview link.
# Usage: tool/back_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/back_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-back}
mkdir -p "$out"

# A frozen app is the interesting failure: keep the ANR trace with the log.
dump_anr() {
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb root > /dev/null 2>&1 || true
  sleep 2
  adb shell 'cat /data/anr/*' > "$out/anr.txt" 2>&1 || true
  adb shell dumpsys activity top > "$out/activity-top.txt" 2>&1 || true
}

fail() {
  echo "FAIL: $*" | tee -a "$out/summary.txt"
  dump_anr
  exit 1
}

pass() { echo "ok: $*" | tee -a "$out/summary.txt"; }
step() { echo "== $*" | tee -a "$out/summary.txt"; }

adb wait-for-device
activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

if ! adb shell pm path "$app" > /dev/null 2>&1; then
  adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
fi

shot() { adb exec-out screencap -p > "$out/$1.png" || true; }

# Waits for the first drawn frame, then a moment for the page after it.
wait_first_frame() {
  for _ in $(seq 1 60); do
    if adb logcat -d 2>/dev/null | grep -q "Displayed $app/"; then
      sleep 4
      return 0
    fi
    sleep 1
  done
  fail "no frame from $app within 60s"
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
  wait_first_frame
}

launch() { # $1: preview query; one retry, an emulator can stall a cold start
  if ! start "$1"; then
    echo "retrying $1" | tee -a "$out/summary.txt"
    start "$1" || fail "am start or first frame failed for $1, see launch.txt"
  fi
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
  adb logcat -d 2>/dev/null | grep -q 'taildeck preview: sheet closed'     || fail "sheet=$sheet: back did not close the sheet"
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
echo "all back cases passed" | tee -a "$out/summary.txt"
