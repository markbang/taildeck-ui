#!/usr/bin/env bash
# Records one gesture per motion effect on this build and on the Kotlin
# reference app, then stacks the two clips side by side under docs/motion/.
# A peer node (tool/motion_peer) joins the same test control plane as both
# apps, so the screens behind login have a node to open, ping, scan and pull.
# Media problems are reported in summary.txt and never fail the step.
# Usage: tool/motion_record.sh <flutter-apk> <kotlin-apk> [application-id] [out-dir]
set -euo pipefail

flutter_apk=${1:?usage: tool/motion_record.sh <flutter-apk> <kotlin-apk> [app-id] [out]}
kotlin_apk=${2:?usage: tool/motion_record.sh <flutter-apk> <kotlin-apk> [app-id] [out]}
app=${3:-top.bangwu.taildeck}
out=${4:-motion}
kotlin_url=${KOTLIN_APK_URL:-https://github.com/markbang/taildeck/releases/download/v0.1.0/taildeck-0.1.0-x86_64.apk}
# With a control server both apps sign in and the screens behind login become
# recordable: control_url is what the emulator reaches, e.g. http://10.0.2.2:8080
# for a control plane on the runner. peer is the hostname of tool/motion_peer,
# derp_port is the relay port its map advertises on 127.0.0.1, reversed into
# the emulator so a relay-only path still carries the node's traffic.
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-}
peer=${PEER:-motionpeer}
derp_port=${DERP_PORT:-}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }

adb wait-for-device
# A freshly booted emulator sometimes shows an ANR dialog over the app.
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
sleep 15
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
# testcontrol's relay listens on the runner's loopback; the emulator only sees
# 10.0.2.2, so hand it the same port through adb.
if [ -n "$derp_port" ]; then
  adb reverse "tcp:$derp_port" "tcp:$derp_port" > /dev/null 2>&1 \
    && note "relay port $derp_port reversed into the device" \
    || note "could not reverse relay port $derp_port"
fi

[ -s "$kotlin_apk" ] || curl -fsSL -o "$kotlin_apk" "$kotlin_url"

W= SH= TAB_NODES= TAB_SERVICES= TAB_AGENTS= TAB_SETTINGS=
screen_size() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  [ -n "${W:-}" ]
}

# uiautomator sometimes dumps while the window is mid-animation; retry.
ui() {
  local attempt
  for attempt in 1 2 3; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if python3 tool/ui.py "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

dump() { # keeps a dump per stage so a missing marker can be read back
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui-$1.xml" > /dev/null 2>&1 || true
}

tapxy() { # 'x y'
  # shellcheck disable=SC2086
  adb shell input swipe $1 $1 120 > /dev/null 2>&1 || true
  sleep 0.5
}

hold_long() { # 'x y' <ms>: the finger stays down for the whole clip
  # shellcheck disable=SC2086
  adb shell input swipe $1 $1 "${2:-3000}" > /dev/null 2>&1 || true
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

wait_for() { # <marker> <seconds>
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    ui has "$1" > /dev/null 2>&1 && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

launch() { # <apk> <app> [url]
  local id=$2 url=${3:-} attempt resumed
  for attempt in 1 2 3; do
    adb shell am force-stop "$id" > /dev/null 2>&1 || true
    sleep 1
    if [ -n "$url" ]; then
      adb shell am start -W -a android.intent.action.VIEW -d "$url" "$id" > /dev/null 2>&1 || true
    else
      adb shell monkey -p "$id" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
    fi
    sleep 5
    resumed=$(adb shell dumpsys activity activities 2> /dev/null \
      | grep -m1 -E 'mResumedActivity|topResumedActivity' || true)
    case "$resumed" in
      *"$id"*) return 0 ;;
    esac
    note "launch attempt $attempt: ${resumed:-no resumed activity}"
    sleep 3
  done
  note "launch failed: $id"
  return 1
}

# Confirms a scenario left the state it should have, so summary.txt says what
# the clip really shows.
check() { # <clip> <marker text>
  if ui has "$2" > /dev/null 2>&1; then
    note "$1: verified ('$2')"
  else
    note "$1: marker '$2' missing"
  fi
}

install_app() { # <apk>
  adb uninstall "$app" > /dev/null 2>&1 || true
  adb install -g "$1" > "$out/install.txt" 2>&1 || { note "install failed, see install.txt"; return 1; }
}

# Records <seconds> from just before the gesture the scenario plays. Each
# recording ends on its own; a device-side screenrecord left over from the
# previous clip would make the next one fail.
record() { # <name> <seconds> <command...>
  local name=$1 seconds=$2
  shift 2
  local attempt
  for attempt in 1 2 3; do
    _record_once "$name" "$seconds" "$@" || true
    if [ -s "$out/$name.mp4" ] && [ "$(stat -c%s "$out/$name.mp4")" -gt 4000 ]; then
      return 0
    fi
    note "$name: retrying (attempt $attempt produced no frames)"
  done
  return 0
}

_record_once() { # <name> <seconds> <command...>
  local name=$1 seconds=$2
  shift 2
  adb shell pkill -f screenrecord > /dev/null 2>&1 || true
  sleep 1
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$((seconds + 2))" --bit-rate 6000000 \
    --size 540x1200 /sdcard/rec.mp4 > /dev/null 2>&1 &
  local recorder=$!
  sleep 0.6
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

# ---- gestures ----

tap_point() { tapxy "$1"; }

# Records one gesture on an element found just before the recording starts, so
# a layout that moved since the last dump cannot send the tap elsewhere.
record_tap() { # <name> <seconds> <text> [tap|hold] [marker] [scroll]
  local name=$1 seconds=$2 text=$3 mode=${4:-tap} point
  if [ -n "${6:-}" ]; then
    point=$(find_or_scroll "$text") || { note "$name: no node for '$text'"; return 0; }
  else
    point=$(ui tap "$text") || { note "$name: no node for '$text'"; return 0; }
  fi
  if [ "$mode" = hold ]; then
    record "$name" "$seconds" hold_long "$point" "$((seconds * 1000 + 1200))"
  else
    record "$name" "$seconds" tap_point "$point"
  fi
  [ -n "${5:-}" ] && check "$name" "$5"
  return 0
}

# Fills a labelled field (the Kotlin app labels every input).
fill_label() { # <label> <value>
  local point
  point=$(find_or_scroll "$1") || { note "no field '$1'"; return 1; }
  tapxy "$point"
  sleep 0.5
  type_text "$2"
  hide_keyboard
}

# Fills a text field by class (this build's key and control-server fields carry
# no label of their own).
fill_edit() { # <index> <value>
  local point
  point=$(ui edit "$1") || { note "no text field $1"; return 1; }
  tapxy "$point"
  sleep 0.5
  type_text "$2"
  hide_keyboard
}

dock_row() { # <text>
  local point
  point=$(ui tap "$1") || return 1
  TAB_Y=${point#* }
  screen_size
  TAB_NODES="$((W / 8)) $TAB_Y"
  TAB_SERVICES="$((W * 3 / 8)) $TAB_Y"
  TAB_AGENTS="$((W * 5 / 8)) $TAB_Y"
  TAB_SETTINGS="$((W * 7 / 8)) $TAB_Y"
}

# Tabs through the bottom bar of either app, found from one label.
tabs_row() { dock_row Services; }

tabs_cycle() {
  tapxy "$TAB_SERVICES"; sleep 1.4
  tapxy "$TAB_AGENTS"; sleep 1.4
  tapxy "$TAB_NODES"; sleep 1.2
}

scroll_down() {
  screen_size
  adb shell input swipe "$((W / 2))" "$((SH * 3 / 4))" "$((W / 2))" "$((SH / 2))" 300 > /dev/null 2>&1 || true
  sleep 0.8
}

# Finds a target that a long page keeps below the fold, scrolling as needed.
find_or_scroll() { # <text> [tries]
  local point tries=${2:-3}
  point=$(ui tap "$1") && { echo "$point"; return 0; }
  while [ "$tries" -gt 0 ]; do
    scroll_down
    point=$(ui tap "$1") && { echo "$point"; return 0; }
    tries=$((tries - 1))
  done
  return 1
}

# A drag that crosses the 80 dp threshold and then holds, so the contained dot
# is on screen while the refresh runs.
pull_down() {
  screen_size
  adb shell input swipe "$((W / 2))" 760 "$((W / 2))" 1560 420 > /dev/null 2>&1 || true
  sleep 2.6
}

# ---- this build, signed out ----

flutter_login_scene() {
  # Ripple: a short tap on the text button, the ink spreads from the touch
  # point and fades while the control-server field grows open.
  record_tap flutter-ripple 3 "Control server" tap
  fill_edit 0 "$control_url" || return 0
  # The auth-key section expands: fade + the content growing.
  record_tap flutter-expand 3 "Use an auth key" tap "Connect"
  fill_edit 0 "${auth_key:-tskey-test}" || return 0
  # Press: the filled button held, its pill squashes to CornerSmall while the
  # ripple stays; the release signs the node in, past the end of the clip.
  local point
  point=$(find_or_scroll "Connect") || { note "flutter-press: no Connect"; return 0; }
  record flutter-press 3 hold_long "$point" 4200
  wait_for "Search nodes" 40 || note "flutter login: still on the login screen"
}

# ---- this build, signed in ----

flutter_scene() {
  local point
  if ! ui has "Search nodes" > /dev/null 2>&1; then
    note "flutter: not signed in, the node page stays unrecorded"
    return 0
  fi
  note "flutter: signed in"
  if tabs_row; then
    record flutter-tabs 6 tabs_cycle
    check flutter-tabs "Services"
  fi
  point=$(ui tap "$peer") || { note "flutter-detail: no node '$peer'"; return 0; }
  record flutter-detail 6 tap_point "$point"
  dump flutter-detail
  # The ping result block grows in under the buttons.
  record_tap flutter-size 6 "Ping" tap "ms"
  # The scan block joins the list and resizes with the found port.
  record_tap flutter-scan 14 "Scan common ports" tap "3000" scroll
  dump flutter-scan
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 1.5
  # Pull to refresh: the contained dot morphs with the drag, then spins.
  record flutter-refresh 6 pull_down
  dump flutter-refresh
  # Settings opens the key sheet: a bottom sheet rising over the scrim.
  point=$(ui tap "Settings") || { note "flutter-sheet: no Settings tab"; return 0; }
  tapxy "$point"; sleep 1.5
  record_tap flutter-sheet 4 "Import key" tap "Import key" scroll
  dump flutter-sheet
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 1
}

# ---- the Kotlin app, signed out ----

kotlin_login_scene() {
  local point
  # A fresh install has no device name, and Sign in stays disabled without one.
  if point=$(ui tap "Device name"); then
    tapxy "$point"
    sleep 0.5
    type_text "pixel-motion"
    hide_keyboard
  fi
  record_tap kotlin-ripple 3 "Advanced" tap "Control server"
  fill_label "Control server" "$control_url" || return 0
  fill_label "Auth key" "${auth_key:-tskey-test}" || return 0
  dump kotlin-login
  # Press: the Sign in pill held, its corners squashing to CornerSmall; the
  # release starts the node, past the end of the clip.
  point=$(find_or_scroll "Sign in") || { note "kotlin-press: no Sign in"; return 0; }
  record kotlin-press 3 hold_long "$point" 4200
  wait_for "Search" 40 || note "kotlin login: still on the login screen"
}

# ---- the Kotlin app, signed in ----

kotlin_scene() {
  local point
  if ! ui has "Search" > /dev/null 2>&1; then
    note "kotlin: not signed in, the node page stays unrecorded"
    return 0
  fi
  note "kotlin: signed in"
  if tabs_row; then
    record kotlin-tabs 6 tabs_cycle
    check kotlin-tabs "Services"
  fi
  point=$(ui tap "$peer") || { note "kotlin-detail: no node '$peer'"; return 0; }
  record kotlin-detail 6 tap_point "$point"
  dump kotlin-detail
  record_tap kotlin-size 6 "Ping" tap "ms"
  record_tap kotlin-scan 14 "Scan ports" tap "3000" scroll
  dump kotlin-scan
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 1.5
  record kotlin-refresh 6 pull_down
  dump kotlin-refresh
  point=$(ui tap "Settings") || { note "kotlin-sheet: no Settings action"; return 0; }
  tapxy "$point"; sleep 1.5
  record_tap kotlin-sheet 4 "Import key" tap "Import key" scroll
  dump kotlin-sheet
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 1
}

# ---- run it ----

if [ -n "$control_url" ]; then
  install_app "$kotlin_apk" || true
  launch "$kotlin_apk" "$app"
  kotlin_login_scene
  kotlin_scene
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
else
  note "no control server: the screens behind login stay unrecorded"
fi

install_app "$flutter_apk" || true
# Neither the browser flow nor an external page needs a browser on the device.
adb shell pm disable-user --user 0 com.android.chrome > /dev/null 2>&1 || true
launch "$flutter_apk" "$app" "taildeck://preview/?login=1&lang=en"
if [ -n "$control_url" ]; then
  flutter_login_scene
  flutter_scene
else
  note "no control server: this build stays on its login screen"
fi
adb shell pm enable com.android.chrome > /dev/null 2>&1 || true

# ---- put them side by side: Kotlin on the left, this build on the right ----
label() { # <mp4> <text> <dest>
  ffmpeg -loglevel error -y -i "$1" -vf \
    "pad=iw:ih+34:0:34:color=0x101214,drawtext=text='$2':fontcolor=0xE8EAED:fontsize=18:x=12:y=8" \
    -an "$3" || true
}

pair() { # <kotlin clip> <flutter clip> <name>
  [ -s "$out/$1.mp4" ] && [ -s "$out/$2.mp4" ] || { note "$3: missing clip"; return 0; }
  label "$out/$1.mp4" "Kotlin" "$out/$1.labeled.mp4"
  label "$out/$2.mp4" "Flutter" "$out/$2.labeled.mp4"
  ffmpeg -loglevel error -y -i "$out/$1.labeled.mp4" -i "$out/$2.labeled.mp4" \
    -filter_complex '[0:v]scale=404:-2,pad=404:ih:0:0:color=0x101214[l];[1:v]scale=404:-2,pad=404:ih:0:0:color=0x101214[r];[l][r]hstack=inputs=2' \
    -an "$out/$3.mp4" || true
  [ -s "$out/$3.mp4" ] && note "$3: $(stat -c%s "$out/$3.mp4") bytes"
  return 0
}

pair kotlin-ripple flutter-ripple ripple
pair kotlin-press flutter-press press
pair kotlin-size flutter-size content-size
pair kotlin-scan flutter-scan scan-row
pair kotlin-refresh flutter-refresh pull-refresh
pair kotlin-sheet flutter-sheet sheet
pair kotlin-tabs flutter-tabs motion-tabs
pair kotlin-detail flutter-detail motion-detail

# A GIF is what a pull request can show inline.
for name in ripple press content-size scan-row pull-refresh sheet motion-tabs motion-detail; do
  [ -s "$out/$name.mp4" ] || continue
  ffmpeg -loglevel error -y -i "$out/$name.mp4" -vf \
    'fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
    "$out/$name.gif" || true
done

note "ok: motion recorded"
