#!/usr/bin/env bash
# Records the terminal's snippets, sessions, reconnect and appearance on the
# Android emulator, against a real shell: the runner's test tailnet carries two
# peer nodes with an SSH server (tool/motion/peer), so every session here is a
# genuine dial. Manual only; a missing clip is reported, never failed.
# Usage: tool/termsessions_record.sh <flutter-apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/termsessions_record.sh <flutter-apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-termsessions}
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-tskey-test}
peer=${PEER:-motionpeer}
peer_b=${PEER_B:-motionpeer2}
drop_a=${DROP_A:-3999}
drop_b=${DROP_B:-3998}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true
sleep 15
adb shell input keyevent 82 > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
# The emulator reports a physical keyboard, which hides the IME and the key row.
adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true

W= SH=
screen_size() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  W=${W:-1080}; SH=${SH:-2400}
}

dump() {
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

tap_label() { # <text>: reach a screen, never evidence
  local point
  point=$(ui tap "$1") || return 1
  tap_xy "$point"
}

scroll_down() {
  screen_size
  adb shell input swipe "$((W / 2))" "$((SH * 3 / 4))" "$((W / 2))" "$((SH / 2))" 300 > /dev/null 2>&1 || true
  sleep 0.8
}

find_or_scroll() { # <text> [tries]
  local point tries=${2:-4}
  point=$(ui tap "$1") && { echo "$point"; return 0; }
  while [ "$tries" -gt 0 ]; do
    scroll_down
    point=$(ui tap "$1") && { echo "$point"; return 0; }
    tries=$((tries - 1))
  done
  return 1
}

# The floating dock sits over the bottom of a long page, so a row that came
# into view there cannot be tapped; keep scrolling until it is above the dock.
scroll_clear() { # <text> [tries]
  local needle=$1 tries=${2:-24} point x y
  for _ in $(seq 1 "$tries"); do
    if point=$(ui tap "$needle"); then
      y=${point#* }
      if [ "$y" -lt $((SH - 170)) ]; then
        echo "$point"
        return 0
      fi
    fi
    adb shell input swipe "$((W / 2))" "$((SH * 5 / 8))" "$((W / 2))" "$((SH / 2))" 200 > /dev/null 2>&1 || true
    sleep 0.8
  done
  return 1
}

# A popup option: a plain tap on a visible label, never a scroll (a drag
# closes the popup) and never under the dock.
tap_option() { # <text>
  local attempt point
  for attempt in 1 2 3; do
    point=$(ui tap "$1") && { tap_xy "$point"; sleep 1; return 0; }
    sleep 0.6
  done
  note "no option '$1'"
  return 1
}

# Back to the tab shell from wherever a step left off.
to_tabs() {
  local attempt
  for attempt in 1 2 3 4 5; do
    ui has "Nodes" > /dev/null 2>&1 && return 0
    adb shell input keyevent 4 > /dev/null 2>&1 || true
    sleep 1
  done
  return 1
}

type_text() {
  adb shell input text "$(printf '%s' "$1" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
  sleep 0.4
}

hide_keyboard() {
  adb shell dumpsys input_method 2> /dev/null | grep -q 'mInputShown=true' || return 0
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 0.8
}

fill_edit() { # <index> <value>
  local point
  point=$(ui edit "$1") || { note "no text field $1"; return 1; }
  tap_xy "$point"
  type_text "$2"
  hide_keyboard
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

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || true; }

record() { # <name> <seconds> <shell function...>
  local name=$1 seconds=$2
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
    [ -s "$out/$name.mp4" ] && note "$name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "$name: no recording"
  fi
}

check() { # <clip> <marker>
  if ui has "$2" > /dev/null 2>&1; then
    note "$1: verified ('$2')"
  else
    note "$1: marker '$2' missing"
  fi
}

launch() { # [url]
  local url=${1:-} attempt resumed
  for attempt in 1 2 3; do
    adb shell am force-stop "$app" > /dev/null 2>&1 || true
    sleep 1
    if [ -n "$url" ]; then
      adb shell "am start -W -a android.intent.action.VIEW -d '$url' '$app'" > /dev/null 2>&1 || true
    else
      adb shell monkey -p "$app" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
    fi
    sleep 5
    resumed=$(adb shell dumpsys activity activities 2> /dev/null \
      | grep -m1 -E 'mResumedActivity|topResumedActivity' || true)
    case "$resumed" in
      *"$app"*) return 0 ;;
    esac
    note "launch attempt $attempt: ${resumed:-no resumed activity}"
    sleep 3
  done
  note "launch failed"
  return 1
}

sign_in() {
  [ -n "$control_url" ] || { note "no control server: the app stays on the login screen"; return 1; }
  if ui has "Nodes" > /dev/null 2>&1; then
    note "sign-in: already signed in"
    return 0
  fi
  local point
  point=$(find_or_scroll "Control server") || { note "sign-in: no control-server row"; return 1; }
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$control_url" || return 1
  point=$(find_or_scroll "Use an auth key") || return 1
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$auth_key" || return 1
  point=$(find_or_scroll "Connect") || return 1
  tap_xy "$point"
  wait_for "Nodes" 45 || { note "sign-in: still on the login screen"; return 1; }
  note "sign-in: node up, control $control_url"
}

open_session() { # <node label>
  local node=$1 point
  point=$(find_or_scroll "$node") || { note "$node: not in the node list"; return 1; }
  tap_xy "$point"
  sleep 1.5
  point=$(find_or_scroll "SSH") || { note "$node: no SSH action"; return 1; }
  tap_xy "$point"
  sleep 1.5
  point=$(find_or_scroll "Connect") || { note "$node: no Connect button"; return 1; }
  tap_xy "$point"
  wait_for "Terminal output" 30 || { note "$node: the terminal did not open"; return 1; }
  note "$node: SSH session up"
}

open_peer() { # <node label>: from a node page back to the list
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 1
  open_session "$1"
}

send_command() { # <text>
  local point
  point=$(ui tap "Command input") || point=$(ui edit 0) || { note "no input line"; return 1; }
  tap_xy "$point"
  type_text "$1"
  adb shell input keyevent 66 > /dev/null 2>&1 || true
  sleep 3
}

# ---- snippets ------------------------------------------------------------
snippet_sheet() { # <name> <command>: add one from the terminal's chip
  local point
  point=$(ui tap "Snippets") || { note "no Snippets chip"; return 1; }
  tap_xy "$point"
  sleep 1.2
  point=$(ui tap "New snippet") || { note "no New snippet row"; return 1; }
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$1"
  fill_edit 1 "$2"
  point=$(ui tap "Save") || { note "no Save"; return 1; }
  tap_xy "$point"
  sleep 1.5
}

close_sheet() {
  local point
  point=$(ui tap "Close") || return 0
  tap_xy "$point"
  sleep 1
}

snippets_step() {
  if ! snippet_sheet "Disk usage" "df -h /"; then
    shot term-snippets-missing
    return 0
  fi
  shot term-snippets-list
  note "snippets: saved one entry"
  record term-snippets 10 run_snippet
  check term-snippets "Disk usage"
  close_sheet
  shot term-snippet-sent
}

run_snippet() {
  local point
  point=$(ui tap "Disk usage") || return 1
  tap_xy "$point"
  sleep 2
}

# ---- sessions ------------------------------------------------------------
sessions_step() {
  to_tabs || true
  sleep 1
  if ! open_peer "$peer_b"; then
    shot term-sessions-missing
    return 0
  fi
  sleep 2
  shot term-sessions
  record term-sessions-switch 10 switch_back
  check term-sessions-switch "$peer"
}

switch_back() {
  local point
  point=$(ui tap "$peer") || point=$(ui tap "$peer_b") || return 1
  tap_xy "$point"
  sleep 2
}

# ---- reconnect -----------------------------------------------------------
reconnect_step() {
  # Drop both peers: the active session may be either one after the switch.
  if ! curl -fsS "http://127.0.0.1:$drop_a/drop" > /dev/null 2>&1; then
    note "reconnect: could not drop the first peer's sessions"
  fi
  if ! curl -fsS "http://127.0.0.1:$drop_b/drop" > /dev/null 2>&1; then
    note "reconnect: could not drop the second peer's sessions"
  fi
  sleep 3
  if ! ui has "Reconnect" > /dev/null 2>&1; then
    note "reconnect: the session did not drop"
    shot term-reconnect-missing
    return 0
  fi
  shot term-reconnect
  record term-reconnect 12 tap_reconnect
  check term-reconnect "Connected"
}

tap_reconnect() {
  local point
  point=$(ui tap "Reconnect") || return 1
  tap_xy "$point"
  sleep 8
}

# ---- appearance and safe areas ------------------------------------------
appearance_step() {
  local point
  to_tabs || true
  sleep 1.5
  point=$(ui tap "Settings") || { note "appearance: no Settings tab"; return 0; }
  tap_xy "$point"
  sleep 1.5
  # The terminal's own settings page opens from the list.
  point=$(find_or_scroll "Terminal") || { note "appearance: no Terminal row"; return 0; }
  tap_xy "$point"
  sleep 1.5
  point=$(scroll_clear "Color theme") || { note "appearance: no theme row"; return 0; }
  shot term-settings-appearance
  record term-theme 12 theme_step
  check term-theme "Paper light"
  record term-cursor-font 12 cursor_font_step
  scroll_clear "Cursor" > /dev/null 2>&1 || true
  check term-cursor-font "Bar"
  shot term-settings-applied
  # Back out of the settings page, then into the terminal on the same session.
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 1.2
  to_tabs || true
  sleep 1
  point=$(find_or_scroll "$peer") || return 0
  tap_xy "$point"
  sleep 1.5
  point=$(find_or_scroll "Resume") || return 0
  tap_xy "$point"
  sleep 3
  shot term-theme-session
  record term-safe-area 8 rotate_to 1
  shot term-safe-area-landscape
  rotate_to 0
}

theme_step() {
  local point
  point=$(scroll_clear "Color theme") || return 1
  tap_xy "$point"
  sleep 1.2
  tap_option "Paper light" || return 1
  sleep 1
}

cursor_font_step() {
  local point
  point=$(scroll_clear "Cursor") || return 1
  tap_xy "$point"
  sleep 1.2
  tap_option "Bar" || return 1
  sleep 1
  point=$(scroll_clear "Font family") || return 1
  tap_xy "$point"
  sleep 1.2
  tap_option "Sans (not monospace)" || tap_option "Sans" || return 1
  sleep 1.5
}

rotate_to() { # <0|1>
  adb shell settings put system accelerometer_rotation 0 > /dev/null 2>&1 || true
  adb shell settings put system user_rotation "$1" > /dev/null 2>&1 || true
  sleep 3
}

# ---- run -----------------------------------------------------------------
screen_size
note "screen: ${W}x${SH}"
adb uninstall "$app" > /dev/null 2>&1 || true
if ! adb install -g "$apk" > "$out/install.txt" 2>&1; then
  note "install failed, see install.txt"
  exit 1
fi
launch || { note "the app did not come up"; exit 0; }
shot term-start

if sign_in; then
  if open_session "$peer"; then
    sleep 3
    shot term-session
    send_command "uname -sr"
    shot term-shell
    send_command "htop"
    sleep 2
    shot term-htop
    adb shell input keyevent 129 > /dev/null 2>&1 || true # Esc leaves htop
    adb shell input text "q" > /dev/null 2>&1 || true
    sleep 2
    snippets_step
    sessions_step
    reconnect_step
    appearance_step
  fi
fi

adb shell settings put system user_rotation 0 > /dev/null 2>&1 || true
note "done"
