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
  # screenrecord sometimes leaves a file with no frames; try the gesture once
  # more before giving up on the clip.
  local attempt
  for attempt in 1 2 3; do
    sleep 3
    _record_once "$name" "$seconds" "$@" || true
    if [ -s "$out/$name.mp4" ] && [ "$(stat -c%s "$out/$name.mp4")" -gt 2000 ]; then
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

# BACK closes the keyboard; ESC is the fallback when no keyboard is up, so a
# field that never took focus cannot send the app back a screen.
ime_hide() {
  if adb shell dumpsys input_method 2> /dev/null | grep -q "mInputShown=true"; then
    adb shell input keyevent 4 > /dev/null 2>&1 || true
  else
    adb shell input keyevent 111 > /dev/null 2>&1 || true
  fi
  sleep 0.5
}

scroll_down_screen() { adb shell input swipe 540 1700 540 1000 400 > /dev/null 2>&1 || true; sleep 0.8; }

# Keeps the last dump beside a clip that could not find its control, so the
# artifact says what the screen really showed.
keep_ui() { cp "$out/ui.xml" "$out/fail-$1.xml" > /dev/null 2>&1 || true; }

# Records one gesture on an element found just before the recording starts, so
# a layout that moved since the last dump cannot send the tap elsewhere.
record_tap() { # <name> <seconds> <text> [hold]
  local name=$1 seconds=$2 text=$3 mode=${4:-tap} point
  point=$(ui tap "$text") || { note "$name: no node for '$text'"; keep_ui "$name"; return 0; }
  if [ "$mode" = hold ]; then
    record "$name" "$seconds" hold_point "$point"
  else
    record "$name" "$seconds" tap_point "$point"
  fi
  [ -n "${5:-}" ] && check "$name" "$5"
  return 0
}

# A press and hold let go in place: the ripple runs, the surface squashes, and
# the tap it ends with opens the same section in both apps.
record_hold() { # <name> <seconds> <text>
  local name=$1 seconds=$2 text=$3 point
  point=$(ui tap "$text") || { note "$name: no node for '$text'"; keep_ui "$name"; return 0; }
  record "$name" "$seconds" hold_point "$point"
}

wait_for() { # <text> <seconds>
  local i=0
  while [ "$i" -lt "$2" ]; do
    ui has "$1" > /dev/null 2>&1 && return 0
    sleep 1
    i=$((i + 1))
  done
  return 1
}

read_size() {
  read -r W H <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  [ -n "${W:-}" ]
}

# Both apps label their tabs, so a tab switch is the same three taps in each.
tap_tabs() { # <first> <second> <back to>
  local point
  for label in "$1" "$2" "$3"; do
    if point=$(ui tap "$label"); then tapxy "$point"; fi
    sleep 1.4
  done
}

swipe_down() { # <x> <y1> <y2> [ms]
  adb shell input swipe "$1" "$2" "$1" "$3" "${4:-500}" > /dev/null 2>&1 || true
  sleep 0.6
}

# Pull the list down from its top, the gesture both apps' refresh boxes watch.
pull_refresh() { swipe_down "$((W / 2))" 420 1000; }

app_uid() {
  adb shell dumpsys package "$app" 2> /dev/null |
    sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r'
}

# Writes the app's own settings before it starts, so the control server is
# already filled in and the sign-in only needs the key.
seed_flutter_config() { # <control-url>
  local uid
  adb root > /dev/null 2>&1 || true
  adb wait-for-device > /dev/null 2>&1 || true
  sleep 1
  uid=$(app_uid)
  printf '{"controlURL":"%s","hostname":"pixel-motion"}\n' "$1" > /tmp/config.json
  adb shell "mkdir -p /data/data/$app/files" > /dev/null 2>&1 || true
  adb push /tmp/config.json "/data/data/$app/files/config.json" > /dev/null 2>&1 || { note "seed: push failed"; return 1; }
  adb shell "chown ${uid:-0}:${uid:-0} /data/data/$app/files/config.json" > /dev/null 2>&1 || true
  adb shell "restorecon /data/data/$app/files/config.json" > /dev/null 2>&1 || true
  note "seed: $app control server $1"
}

seed_kotlin_settings() { # <control-url>
  local uid
  adb root > /dev/null 2>&1 || true
  adb wait-for-device > /dev/null 2>&1 || true
  sleep 1
  uid=$(app_uid)
  cat > /tmp/taildeck.xml <<XML
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="hostname">pixel-motion</string>
    <string name="controlUrl">$1</string>
</map>
XML
  adb shell "mkdir -p /data/data/$app/shared_prefs" > /dev/null 2>&1 || true
  adb push /tmp/taildeck.xml "/data/data/$app/shared_prefs/taildeck.xml" > /dev/null 2>&1 || { note "seed: push failed"; return 1; }
  adb shell "chown ${uid:-0}:${uid:-0} /data/data/$app/shared_prefs/taildeck.xml" > /dev/null 2>&1 || true
  adb shell "restorecon /data/data/$app/shared_prefs/taildeck.xml" > /dev/null 2>&1 || true
  note "seed: $app control server $1"
}

# ---- sign-in: only the key is left to type ----

kotlin_login() { # <key>
  local point i
  if ! ui has "Auth key" > /dev/null 2>&1; then
    point=$(ui tap Advanced) && { tapxy "$point"; sleep 1; }
  fi
  point=$(ui tap "Auth key") || { keep_ui kotlin-login; return 1; }
  tapxy "$point"; type_text "$1"; ime_hide
  point=
  for i in 1 2 3; do
    point=$(ui tap "Sign in") && break
    scroll_down_screen
  done
  [ -n "$point" ] || { keep_ui kotlin-login; note "kotlin sign in: no Sign in button"; return 1; }
  tapxy "$point"
  wait_for "Services" 60 || { keep_ui kotlin-login; return 1; }
}

flutter_login() { # <key>
  local point
  point=$(ui tap "Use an auth key") && { tapxy "$point"; sleep 1; }
  point=$(ui fieldbelow "Use an auth key") || { keep_ui flutter-login; return 1; }
  tapxy "$point"; type_text "$1"; ime_hide
  point=$(ui tap "Connect") || { keep_ui flutter-login; return 1; }
  tapxy "$point"
  wait_for "Settings" 75 || { keep_ui flutter-login; return 1; }
}

# ---- signed-out clips: the login screen both apps share ----

signed_out_kotlin() { # <hanging-url>
  local point i
  launch "$kotlin_apk" "$app"
  sleep 3
  record_hold kotlin-ripple 4 Advanced
  check kotlin-ripple "Control server"
  record_hold kotlin-press 4 "Control server"
  sleep 1
  # A control server that never answers keeps the app on its loading stage.
  if point=$(ui tap "Control server"); then
    tapxy "$point"; type_text "$1"; ime_hide
    point=
    for i in 1 2 3; do
      point=$(ui tap "Sign in") && break
      scroll_down_screen
    done
    if [ -n "$point" ]; then
      record kotlin-loading 7 tap_point "$point"
      check kotlin-loading "Connecting"
    else
      note "kotlin-loading: no Sign in button"
      keep_ui kotlin-loading
    fi
  else
    note "kotlin-loading: no control server field"
    keep_ui kotlin-loading
  fi
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 1
}

signed_out_flutter() { # <hanging-url>
  local point
  seed_flutter_config "$1"
  launch "$flutter_apk" "$app"
  sleep 3
  record_hold flutter-ripple 4 "Control server"
  sleep 2
  record_hold flutter-press 4 "Control server"
  sleep 1
  if point=$(ui tap "Use an auth key"); then tapxy "$point"; sleep 1; fi
  if point=$(ui fieldbelow "Use an auth key"); then
    tapxy "$point"; type_text "tskey-hang"; ime_hide
  fi
  point=$(ui tap "Connect") || point=
  if [ -n "$point" ]; then
    record flutter-loading 7 tap_point "$point"
    check flutter-loading "Starting the node"
  else
    note "flutter-loading: no Connect button"
    keep_ui flutter-loading
  fi
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 1
}

# ---- signed-in clips ----

kotlin_tailnet() { # <key>
  local point
  launch "$kotlin_apk" "$app"
  sleep 3
  if ! kotlin_login "$1"; then
    note "kotlin sign in: still on the login screen"
    return 0
  fi
  note "kotlin sign in: signed in"
  read_size
  record kotlin-tabs 6 tap_tabs Services Nodes Services
  check kotlin-tabs "Services"
  point=$(ui tap "Nodes") && { tapxy "$point"; sleep 1.5; }
  record kotlin-refresh 6 pull_refresh
  # The scan block joins the list and resizes: one gesture recorded once for
  # the row and once for the content size.
  for clip in kotlin-scan-row kotlin-content-size; do
    launch "$kotlin_apk" "$app"
    sleep 3
    point=$(ui wide "pixel-motion") || point=$(ui wide "This device") || point=
    if [ -n "$point" ]; then
      tapxy "$point"; sleep 2
      record_tap "$clip" 10 "Scan ports"
      adb shell input keyevent 4 > /dev/null 2>&1 || true
      sleep 1.5
    else
      note "$clip: no node row to open"
      keep_ui "$clip"
    fi
  done
  if point=$(ui tap Settings); then
    tapxy "$point"; sleep 2
    point=$(ui tap "Sign out") || point=
    if [ -n "$point" ]; then
      record kotlin-dialog 5 tap_point "$point"
      check kotlin-dialog "Sign out and remove"
      point=$(ui tap Cancel) && tapxy "$point"
    else
      note "kotlin-dialog: no sign-out row"
      keep_ui kotlin-dialog
    fi
  fi
}

flutter_tailnet() { # <key>
  local point
  launch "$flutter_apk" "$app"
  sleep 3
  if ! flutter_login "$1"; then
    note "flutter sign in: did not reach the shell"
    return 0
  fi
  note "flutter sign in: signed in"
  read_size
  record flutter-tabs 6 tap_tabs Services Agents Nodes
  check flutter-tabs "Nodes"
  point=$(ui tap "Nodes") && { tapxy "$point"; sleep 1.5; }
  record flutter-refresh 6 pull_refresh
  for clip in flutter-scan-row flutter-content-size; do
    launch "$flutter_apk" "$app"
    sleep 3
    point=$(ui wide "This device") || point=$(ui wide "pixel-motion") || point=
    if [ -n "$point" ]; then
      tapxy "$point"; sleep 2
      record_tap "$clip" 10 "Scan common ports"
      adb shell input keyevent 4 > /dev/null 2>&1 || true
      sleep 1.5
    else
      note "$clip: no node row to open"
      keep_ui "$clip"
    fi
  done
  if point=$(ui tap Settings); then
    tapxy "$point"; sleep 2
    point=$(ui tap "Sign out of the tailnet") || point=
    if [ -n "$point" ]; then
      record flutter-dialog 5 tap_point "$point"
      check flutter-dialog "Sign out?"
      point=$(ui tap Cancel) && tapxy "$point"
    else
      note "flutter-dialog: no sign-out row"
      keep_ui flutter-dialog
    fi
  fi
}

W= H=
hang_url=${HANG_URL:-http://10.0.2.2:9}
key=${AUTH_KEY:-tskey-test}

install_app "$kotlin_apk" || true
signed_out_kotlin "$hang_url"

if [ -n "$control_url" ]; then
  seed_kotlin_settings "$control_url"
  kotlin_tailnet "$key" || note "kotlin scenarios stopped early"
else
  note "no control server: the screens behind login stay unrecorded"
fi

install_app "$flutter_apk" || true
signed_out_flutter "$hang_url"

if [ -n "$control_url" ]; then
  seed_flutter_config "$control_url"
  flutter_tailnet "$key" || note "flutter scenarios stopped early"
else
  note "no control server: the screens behind login stay unrecorded"
fi

# ---- put them side by side: Kotlin on the left, this build on the right ----
label() { # <mp4> <text> <dest>
  ffmpeg -loglevel error -y -i "$1" -vf \
    "scale=404:-2,pad=404:ih+34:0:34:color=0x101214,drawtext=text='$2':fontcolor=0xE8EAED:fontsize=18:x=12:y=8" \
    -an -c:v libx264 -preset veryfast -crf 26 "$3" || true
}

pair() { # <kotlin clip> <flutter clip> <name>
  [ -s "$out/$1.mp4" ] && [ -s "$out/$2.mp4" ] || { note "$3: missing clip"; return 0; }
  label "$out/$1.mp4" "Kotlin" "$out/$1.labeled.mp4"
  label "$out/$2.mp4" "Flutter" "$out/$2.labeled.mp4"
  ffmpeg -loglevel error -y -i "$out/$1.labeled.mp4" -i "$out/$2.labeled.mp4" \
    -filter_complex '[0:v]scale=404:932:force_original_aspect_ratio=increase,crop=404:932[l];[1:v]scale=404:932:force_original_aspect_ratio=increase,crop=404:932[r];[l][r]hstack=inputs=2' \
    -an -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p "$out/$3.mp4" || true
  [ -s "$out/$3.mp4" ] && note "$3: $(stat -c%s "$out/$3.mp4") bytes"
  return 0
}

pair kotlin-expand flutter-expand login-expand
pair kotlin-ripple flutter-ripple ripple
pair kotlin-press flutter-press press-squish
pair kotlin-loading flutter-loading loading
pair kotlin-refresh flutter-refresh refresh
pair kotlin-scan-row flutter-scan-row scan-row
pair kotlin-content-size flutter-content-size content-size
pair kotlin-dialog flutter-dialog dialog

# A GIF is what a pull request can show inline.
for name in login-expand ripple press-squish loading refresh scan-row content-size dialog; do
  [ -s "$out/$name.mp4" ] || continue
  ffmpeg -loglevel error -y -i "$out/$name.mp4" -vf \
    'fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
    "$out/$name.gif" || true
done

note "ok: motion recorded"
