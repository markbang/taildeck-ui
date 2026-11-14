#!/usr/bin/env bash
# Records the same interactions on this build and on the Kotlin reference app,
# then puts the clips side by side. Only effects reachable without a tailnet are
# recorded: both login screens, and the preview shell of this build. Media
# problems are reported in summary.txt and never fail the step.
# Usage: tool/motion_record.sh <flutter-apk> <kotlin-apk> [application-id] [out-dir]
set -euo pipefail

flutter_apk=${1:?usage: tool/motion_record.sh <flutter-apk> <kotlin-apk> [app-id] [out]}
kotlin_apk=${2:?usage: tool/motion_record.sh <flutter-apk> <kotlin-apk> [app-id] [out]}
app=${3:-top.bangwu.taildeck}
out=${4:-motion}
kotlin_url=${KOTLIN_APK_URL:-https://github.com/markbang/taildeck/releases/download/v0.1.0/taildeck-0.1.0-x86_64.apk}
# With a control server both apps can sign in and the screens behind login
# become recordable: control_url is what the emulator reaches, e.g.
# http://10.0.2.2:8080 for a control plane on the runner.
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-}
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
sleep 20
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true

[ -s "$kotlin_apk" ] || curl -fsSL -o "$kotlin_apk" "$kotlin_url"

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

# Resolves the tap point of <text> into the variable <var>, before recording,
# so the gesture itself can be replayed without a slow UI dump.
coord() {
  local point
  point=$(ui tap "$2") || { note "no node for '$2'"; return 1; }
  printf -v "$1" '%s' "$point"
}

tapxy() { # 'x y'
  # shellcheck disable=SC2086
  adb shell input swipe $1 $1 120 > /dev/null 2>&1 || true
  sleep 0.5
}

holdxy() { # 'x y' [ms]
  # shellcheck disable=SC2086
  adb shell input swipe $1 $1 "${2:-800}" > /dev/null 2>&1 || true
  sleep 0.5
}

type_text() {
  adb shell input text "$(printf '%s' "$1" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
  sleep 0.4
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
  adb shell pkill -f screenrecord > /dev/null 2>&1 || true
  sleep 0.7
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$((seconds + 2))" --bit-rate 8000000 \
    /sdcard/rec.mp4 > /dev/null 2>&1 &
  local recorder=$!
  sleep 0.4
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

# ---- scenarios ----

tap_point() { tapxy "$1"; }
hold_point() { holdxy "$1" 900; sleep 1; }

# Records one gesture on an element found just before the recording starts, so
# a layout that moved since the last dump cannot send the tap elsewhere.
record_tap() { # <name> <seconds> <text> [hold]
  local name=$1 seconds=$2 text=$3 mode=${4:-tap} point
  point=$(ui tap "$text") || { note "$name: no node for '$text'"; return 0; }
  if [ "$mode" = hold ]; then
    record "$name" "$seconds" hold_point "$point"
  else
    record "$name" "$seconds" tap_point "$point"
  fi
  [ -n "${5:-}" ] && check "$name" "$5"
  return 0
}

# The dock's four items share a row: find one of them, derive the rest.
dock_row() { # <text>
  local point
  point=$(ui tap "$1") || return 1
  DOCK_Y=${point#* }
  read -r W H <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  TAB_NODES="$((W / 8)) $DOCK_Y"
  TAB_SERVICES="$((W * 3 / 8)) $DOCK_Y"
  TAB_AGENTS="$((W * 5 / 8)) $DOCK_Y"
  [ -n "${W:-}" ]
}

flutter_tabs() {
  tapxy "$TAB_SERVICES"; sleep 1.4
  tapxy "$TAB_AGENTS"; sleep 1.4
  tapxy "$TAB_NODES"; sleep 1.2
}

# Tabs through the bottom bar of either app, found from one label.
tabs_row() { dock_row Services; }

swipe_down() { # 'x y1 y2'
  # shellcheck disable=SC2086
  adb shell input swipe $1 "${2:-400} ${3:-900}" "${4:-400}" > /dev/null 2>&1 || true
  sleep 0.6
}

# ---- signed in (needs a control server) ----

kotlin_login() { # <control-url> <auth-key>
  local field
  field=$(ui tap Advanced) || return 1
  tapxy "$field"; sleep 1.2
  field=$(ui tap "Control server") || return 1
  tapxy "$field"; sleep 0.8
  type_text "$1"
  field=$(ui tap "Auth key") || return 1
  tapxy "$field"; sleep 0.8
  type_text "$2"
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 0.8
  field=$(ui tap "Sign in") || return 1
  tapxy "$field"
  local waited=0
  while [ "$waited" -lt 40 ]; do
    sleep 1
    waited=$((waited + 1))
    ui has "Scan ports" > /dev/null 2>&1 && break
  done
  ui tap "Nodes" > /dev/null 2>&1
}

kotlin_tailnet() {
  local point
  if ! kotlin_login "$1" "$2"; then
    note "kotlin login: could not find the login controls"
    return 0
  fi
  if ! ui has "Nodes" > /dev/null 2>&1; then
    note "kotlin login: still on the login screen (control server $1)"
    return 0
  fi
  note "kotlin login: signed in"
  if tabs_row; then
    record kotlin-tabs 6 flutter_tabs
    check kotlin-tabs "Services"
  fi
  point=$(ui tap devbox) || point=$(ui tap nas) || point=
  if [ -n "$point" ]; then
    record kotlin-detail 6 tap_point "$point"
    record_tap kotlin-ping 8 "Ping" tap
    record_tap kotlin-scan 10 "Scan ports" tap
    adb shell input keyevent 4 > /dev/null 2>&1 || true
    sleep 1.5
  else
    note "kotlin-detail: no peer listed"
  fi
  record kotlin-refresh 6 swipe_down "$((W / 2)) 420 980 500"
}

flutter_tailnet() {
  local point
  if dock_row Services; then
    record flutter-tabs 6 flutter_tabs
  fi
  point=$(ui tap devbox) || point=$(ui tap nas) || point=
  if [ -n "$point" ]; then
    record flutter-detail 6 tap_point "$point"
    record_tap flutter-ping 8 "Ping" tap
    record_tap flutter-scan 10 "Scan ports" tap
    adb shell input keyevent 4 > /dev/null 2>&1 || true
    sleep 1.5
  fi
  record flutter-refresh 6 swipe_down "$((W / 2)) 420 980 500"
}

flutter_detail() {
  local point
  point=$(ui tap devbox) || { note "flutter-detail: no node for 'devbox'"; return 0; }
  record flutter-detail 6 tap_point "$point"
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 1.5
}

W= TAB_SERVICES= TAB_AGENTS= TAB_NODES=

# ---- signed-out gestures: the one screen both apps share ----
install_app "$kotlin_apk" || true
launch "$kotlin_apk" "$app"
record_tap kotlin-expand 3 Advanced tap "Control server"
record_tap kotlin-press 3 Advanced hold "Control server"
# Press and hold the sign-in button: the ripple runs and the pill's corners
# squash, and the app then shows its loading dot while the node starts.
record_tap kotlin-start 6 "Sign in" tap

if [ -n "$control_url" ]; then
  kotlin_tailnet "$control_url" "${auth_key:-tskey-test}"
else
  note "no control server: the screens behind login stay unrecorded"
fi

install_app "$flutter_apk" || true
launch "$flutter_apk" "$app" "taildeck://preview/?login=1&lang=en"
record_tap flutter-loading 6 "Continue in browser" tap
# The preview shell runs on mock data: no tailnet needed for the tabs.
launch "$flutter_apk" "$app" "taildeck://preview/?preview=1&tab=0&lang=en"
if dock_row Services; then
  record flutter-tabs 6 flutter_tabs
  check flutter-tabs "Add service"
else
  note "flutter-tabs: no dock row found"
fi
launch "$flutter_apk" "$app" "taildeck://preview/?preview=1&tab=0&lang=en"
flutter_detail
check flutter-detail "Search nodes"

# Signing in with a key would start a node; no browser on this device keeps a
# real sign-in from leaving the app.
adb shell pm disable-user --user 0 com.android.chrome > /dev/null 2>&1 || true
launch "$flutter_apk" "$app" "taildeck://preview/?login=1&lang=en"
record_tap flutter-expand 3 "auth key" tap "Connect"
record_tap flutter-press 3 "Control server" hold
record_tap flutter-start 6 "Continue in browser" tap
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

pair kotlin-expand flutter-expand login-expand
pair kotlin-press flutter-press press
pair kotlin-start flutter-loading loading
pair kotlin-tabs flutter-tabs motion-tabs
pair kotlin-detail flutter-detail motion-detail
pair kotlin-ping flutter-ping motion-ping
pair kotlin-scan flutter-scan motion-scan
pair kotlin-refresh flutter-refresh motion-refresh

# A GIF is what a pull request can show inline.
for name in login-expand press loading motion-tabs motion-detail motion-ping motion-scan motion-refresh; do
  [ -s "$out/$name.mp4" ] || continue
  ffmpeg -loglevel error -y -i "$out/$name.mp4" -vf \
    'fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
    "$out/$name.gif" || true
done

note "ok: motion recorded"
