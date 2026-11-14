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
  adb shell input tap $1 > /dev/null 2>&1 || true
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

# ---- Kotlin: login screen only; the rest needs a control server ----
kotlin_expand() { tapxy "$ADVANCED"; sleep 1.8; tapxy "$ADVANCED"; }
kotlin_start() { tapxy "$SIGNIN"; sleep 5; }
kotlin_press() { holdxy "$SIGNIN" 900; sleep 1; }

# ---- this build: login form, and the preview shell ----
flutter_expand() { tapxy "$CONTROL"; sleep 1.4; tapxy "$AUTHKEY"; sleep 1.6; }
flutter_start() { tapxy "$BROWSER"; sleep 3; }
flutter_press() { holdxy "$BROWSER" 900; sleep 1; }
flutter_tabs() {
  tapxy "$TAB_SERVICES"; sleep 1.4
  tapxy "$TAB_AGENTS"; sleep 1.4
  tapxy "$TAB_NODES"; sleep 1.2
}
flutter_detail() { tapxy "$PEER"; sleep 2; adb shell input keyevent 4 > /dev/null 2>&1 || true; sleep 1.4; }

ADVANCED= SIGNIN= CONTROL= AUTHKEY= BROWSER= TAB_SERVICES= TAB_AGENTS= TAB_NODES= PEER= BACK=

install_app "$kotlin_apk" || true
launch "$kotlin_apk" "$app"
coord ADVANCED Advanced || true
record kotlin-expand 5 kotlin_expand
# A control server that never answers keeps the node in "starting" without
# opening a browser, unlike the real controlplane.
tapxy "$ADVANCED" || true
sleep 1.2
coord CONTROL "Control server" || true
tapxy "$CONTROL" || true
type_text "http://10.255.255.1:1"
adb shell input keyevent 4 > /dev/null 2>&1 || true
sleep 1
if ui has "10.255.255.1" > /dev/null; then
  coord SIGNIN "Sign in" || true
  record kotlin-start 7 kotlin_start
else
  note "kotlin-start: control URL not typed; the real controlplane would open a browser"
fi
record kotlin-press 3 kotlin_press
# A failed sign-in never leaves the app, but a stray browser would follow the
# next clip.
adb shell am force-stop com.android.chrome > /dev/null 2>&1 || true

install_app "$flutter_apk" || true
# The preview shell runs on mock data: no tailnet needed for the tabs.
launch "$flutter_apk" "$app" "taildeck://preview/?preview=1&tab=0&lang=en"
coord TAB_SERVICES Services || true
coord TAB_AGENTS Agents || true
coord TAB_NODES Nodes || true
record flutter-tabs 6 flutter_tabs
launch "$flutter_apk" "$app" "taildeck://preview/?preview=1&tab=0&lang=en"
coord PEER devbox || true
record flutter-detail 5 flutter_detail

launch "$flutter_apk" "$app" "taildeck://preview/?login=1&lang=en"
coord CONTROL "Control server" || true
coord AUTHKEY "auth key" || true
record flutter-expand 6 flutter_expand
launch "$flutter_apk" "$app" "taildeck://preview/?login=1&lang=en"
coord BROWSER "Continue in browser" || true
record flutter-start 4 flutter_start
record flutter-press 3 flutter_press

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
pair kotlin-start flutter-start login-start
pair kotlin-press flutter-press press

# A GIF is what a pull request can show inline.
for name in login-expand login-start press; do
  [ -s "$out/$name.mp4" ] || continue
  ffmpeg -loglevel error -y -i "$out/$name.mp4" -vf \
    'fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
    "$out/$name.gif" || true
done

note "flutter only (Kotlin screens need a tailnet): flutter-tabs, flutter-detail"
note "ok: motion recorded"
