#!/usr/bin/env bash
# The remembered device connection on the Android emulator against the test
# tailnet's SSH peers (tool/motion/peer): the first tap goes through the
# actions and the sheet; after a force-stop the same tap dials straight in;
# Edit connection switches the auth and the next tap uses it; a second device
# keeps its own. Stills and clips are named remember-connection-*.
# Usage: tool/remember_record.sh <flutter-apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/remember_record.sh <flutter-apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-remember}
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-tskey-test}
peer=${PEER:-bangwu}
peer_b=${PEER_B:-motionpeer}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
failures=0
note() { echo "$*" | tee -a "$summary"; }
fail() { note "GATE FAIL: $*"; failures=$((failures + 1)); }

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell input keyevent 82 > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true

W= SH=
screen_size() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  W=${W:-1080}; SH=${SH:-2400}
}

dump() {
  rm -f "$out/ui.xml"
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
}

ui() { # <tap|has|text|bounds|edit> <needle>
  local attempt
  for attempt in 1 2 3; do
    dump
    if python3 tool/ui.py "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

tap_xy() { # 'x y'
  # shellcheck disable=SC2086
  adb shell input tap $1 > /dev/null 2>&1 || true
  sleep 0.8
}

long_press_xy() { # 'x y'
  local x=${1% *} y=${1#* }
  adb shell input swipe "$x" "$y" "$x" "$y" 900 > /dev/null 2>&1 || true
  sleep 1.2
}

tap_label() { # <text>
  local point
  point=$(ui tap "$1") || return 1
  tap_xy "$point"
}

hide_ime() {
  adb shell dumpsys input_method 2> /dev/null | grep -q 'mInputShown=true' || return 0
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 0.8
}

type_text() {
  adb shell input text "$(printf '%s' "$1" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
  sleep 0.4
}

fill_edit() { # <index> <value>
  local point
  point=$(ui edit "$1") || { note "no text field $1"; return 1; }
  tap_xy "$point"
  type_text "$2"
  hide_ime
}

wait_for() { # <marker> <seconds>
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    ui has "$1" > /dev/null 2>&1 && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

shot() { adb exec-out screencap -p > "$out/remember-connection-$1.png" 2> /dev/null || true; }

record() { # <name> <seconds> <shell function...>
  local name=remember-connection-$1 seconds=$2
  shift 2
  adb shell pkill -f screenrecord > /dev/null 2>&1 || true
  sleep 0.6
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$((seconds + 2))" --bit-rate 6000000 /sdcard/rec.mp4 > /dev/null 2>&1 &
  local recorder=$!
  sleep 0.5
  "$@" || true
  wait "$recorder" 2> /dev/null || true
  sleep 0.5
  adb pull /sdcard/rec.mp4 "$out/$name-raw.mp4" > /dev/null 2>&1 || true
  if [ -s "$out/$name-raw.mp4" ]; then
    ffmpeg -loglevel error -y -ss 0.2 -i "$out/$name-raw.mp4" -t "$seconds" \
      -an -vf 'scale=360:-2' "$out/$name.mp4" || true
    rm -f "$out/$name-raw.mp4"
    [ -s "$out/$name.mp4" ] && note "$name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "$name: no recording"
  fi
}

launch() {
  local attempt resumed
  for attempt in 1 2 3; do
    adb shell am force-stop "$app" > /dev/null 2>&1 || true
    sleep 1
    adb shell monkey -p "$app" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
    sleep 5
    resumed=$(adb shell dumpsys activity activities 2> /dev/null \
      | grep -m1 -E 'mResumedActivity|topResumedActivity' || true)
    case "$resumed" in
      *"$app"*) return 0 ;;
    esac
    note "launch attempt $attempt: ${resumed:-no resumed activity}"
    sleep 3
  done
  return 1
}

sign_in() {
  [ -n "$control_url" ] || { note "no control server"; return 1; }
  local waited=0 point
  while [ "$waited" -lt 45 ]; do
    ui has "Nodes" > /dev/null 2>&1 && return 0
    ui has "Control server" > /dev/null 2>&1 && break
    sleep 1
    waited=$((waited + 1))
  done
  point=$(ui tap "Control server") || { note "sign-in: no control-server row"; return 1; }
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$control_url" || return 1
  point=$(ui tap "Use an auth key") || return 1
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$auth_key" || return 1
  point=$(ui tap "Connect") || return 1
  tap_xy "$point"
  wait_for "Nodes" 45 || { note "sign-in: still on the login screen"; return 1; }
  note "sign-in: node up, control $control_url"
}

# A device row: its spoken label starts with "<name>, ".
row() { ui tap "$1, "; }

wait_row() { # <name>
  local waited=0
  while [ "$waited" -lt 60 ]; do
    row "$1" > /dev/null 2>&1 && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

to_list() {
  local attempt
  for attempt in 1 2 3 4 5; do
    row "$peer" > /dev/null 2>&1 && return 0
    adb shell input keyevent 4 > /dev/null 2>&1 || true
    sleep 1
  done
  return 1
}

pick_auth() { # <option>
  tap_label "Authentication" || { note "no Authentication row"; return 1; }
  sleep 1
  tap_label "$1" || { note "no auth option '$1'"; return 1; }
  sleep 1
}

relaunch() {
  launch || return 1
  wait_row "$peer" || { note "after relaunch: no $peer row"; return 1; }
  sleep 2
}

# ---- 1. first connection: actions, sheet, Connect ------------------------
first_connect() {
  tap_xy "$(row "$peer")"
  sleep 1.5
  tap_label "SSH" || { note "no SSH action"; return 1; }
  sleep 1.5
  shot 02-sheet-first
  tap_label "Connect" || { note "no Connect"; return 1; }
  wait_for "Terminal output" 30
}

# ---- 2. after a force-stop the tap goes straight in -----------------------
tap_straight_in() {
  tap_xy "$(row "$peer")"
  sleep 0.6
  ui has "Authentication" > /dev/null 2>&1 && note "straight-in: the sheet showed"
  wait_for "Terminal output" 30
}

# ---- 3. long press, Edit connection, Key ---------------------------------
edit_to_key() {
  long_press_xy "$(row "$peer")"
  tap_label "Edit connection" || { note "no Edit connection"; return 1; }
  sleep 1.5
  shot 05-edit-sheet
  pick_auth "Key" || return 1
  tap_label "Connect" || return 1
  wait_for "Terminal output" 30
}

screen_size
note "screen: ${W}x${SH}"
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || { note "install failed"; exit 1; }
launch || { fail "the app did not come up"; exit 1; }
sign_in || { fail "sign-in"; exit 1; }
wait_row "$peer" || { fail "no $peer row"; exit 1; }
sleep 2
shot 01-list-first

if record 01-first-connect 14 first_connect && ui has "Terminal output" > /dev/null 2>&1; then
  note "first connect: terminal up through the sheet"
  shot 03-first-terminal
else
  fail "first connect did not reach the terminal"
fi

relaunch || fail "relaunch"
shot 04-list-remembered
if ui has "SSH · " > /dev/null 2>&1; then
  note "row label: $(ui text "SSH · " || true)"
else
  fail "the row shows no remembered method"
fi
record 02-straight-in 10 tap_straight_in
if ui has "Terminal output" > /dev/null 2>&1 && ! ui has "Authentication" > /dev/null 2>&1; then
  note "straight-in: terminal up with no menu or sheet"
  shot 04b-straight-in
else
  fail "the second tap did not go straight in"
fi

to_list || true
sleep 1
record 03-edit-key 16 edit_to_key
ui has "Terminal output" > /dev/null 2>&1 || fail "edit to Key did not connect"
relaunch || fail "relaunch"
if ui has "· Key" > /dev/null 2>&1; then
  note "after edit: $(ui text "· Key" || true)"
else
  fail "the row does not show Key after the edit"
fi
shot 06-list-key
tap_xy "$(row "$peer")"
wait_for "Terminal output" 30 && ! ui has "Authentication" > /dev/null 2>&1 \
  && note "key auth: next tap went straight in" || fail "key auth was not used on the next tap"

# ---- 4. a second device keeps its own -----------------------------------
to_list || true
sleep 1
if wait_row "$peer_b"; then
  tap_xy "$(row "$peer_b")"
  sleep 1.5
  ui has "Scan common ports" > /dev/null 2>&1 \
    && note "$peer_b: first tap opened the actions" || fail "$peer_b: no actions on first tap"
  tap_label "SSH" || true
  sleep 1.5
  pick_auth "Password" || true
  fill_edit 2 "anything" || true
  tap_label "Connect" || true
  wait_for "Terminal output" 30 && note "$peer_b: password login up" || fail "$peer_b: password login"
  relaunch || true
  shot 07-two-devices
  note "rows: $(ui text "SSH · " || true) | $(ui text "· Password" || true)"
  ui has "· Key" > /dev/null 2>&1 && ui has "· Password" > /dev/null 2>&1 \
    || fail "the two devices do not show their own methods"
  tap_xy "$(row "$peer_b")"
  sleep 2
  shot 08-password-sheet
  ui has "Authentication" > /dev/null 2>&1 \
    && note "$peer_b: saved password login opens the sheet" || fail "$peer_b: no sheet for the password"
else
  fail "no $peer_b row"
fi

if [ "$failures" -gt 0 ]; then
  note "remember: $failures failure(s)"
  exit 1
fi
note "remember: first connect, straight-in tap, edit to Key, two devices"
