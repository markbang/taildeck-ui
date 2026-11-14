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
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done

[ -s "$kotlin_apk" ] || curl -fsSL -o "$kotlin_apk" "$kotlin_url"

ui() { # <file> <command> [needle]
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
  python3 tool/ui.py "$out/ui.xml" "$@"
}

tap() { # <text>
  local point
  point=$(ui tap "$1" 2> /dev/null) || { note "no node for '$1'"; return 1; }
  # shellcheck disable=SC2086
  adb shell input tap $point
  sleep 0.8
}

hold() { # <text> [ms]
  local point
  point=$(ui tap "$1" 2> /dev/null) || { note "no node for '$1'"; return 1; }
  # shellcheck disable=SC2086
  adb shell input swipe $point $point "${2:-800}"
  sleep 0.8
}

type_text() { # <text>
  adb shell input text "$(printf '%s' "$1" | sed 's/ /%s/g')"
  sleep 0.4
}

launch() { # <apk> <app> [url]
  local apk=$1 id=$2 url=${3:-}
  adb shell am force-stop "$id" > /dev/null 2>&1 || true
  sleep 1
  if [ -n "$url" ]; then
    adb shell am start -W -a android.intent.action.VIEW -d "$url" "$id" > /dev/null 2>&1 || true
  else
    adb shell monkey -p "$id" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
  fi
  sleep 4
}

record() { # <name> <seconds> <command...>
  local name=$1 seconds=$2
  shift 2
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit 40 --bit-rate 8000000 /sdcard/rec.mp4 > /dev/null 2>&1 &
  local recorder=$!
  sleep 1.2
  "$@" || true
  wait "$recorder" 2> /dev/null || true
  adb pull /sdcard/rec.mp4 "$out/$name-raw.mp4" > /dev/null 2>&1 || true
  if [ -s "$out/$name-raw.mp4" ]; then
    # Skip the pre-roll so the clip starts just before the gesture.
    ffmpeg -loglevel error -y -ss 0.9 -i "$out/$name-raw.mp4" -t "$seconds" \
      -an -vf 'scale=360:-2' "$out/$name.mp4" || true
    [ -s "$out/$name.mp4" ] && note "$name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "$name: no recording"
  fi
}

# ---- this build: login form, and the preview shell ----
install_app() { # <apk>
  adb uninstall "$app" > /dev/null 2>&1 || true
  adb install -g "$1" > "$out/install.txt" 2>&1 || { note "install failed, see install.txt"; return 1; }
}

kotlin_expand() { tap Advanced || true; sleep 1.6; tap Advanced || true; }
kotlin_start() {
  tap "Control server" || true
  type_text "http://10.255.255.1:1" || true
  adb shell input keyevent 111 > /dev/null 2>&1 || true # Esc closes the keyboard
  sleep 0.6
  tap "Sign in" || true
  sleep 4
}
kotlin_press() { hold "Sign in" 900 || true; sleep 1 }

flutter_expand() { tap "Control server" || true; sleep 1.2; tap "Use auth key" || true; sleep 1.4; }
flutter_start() { tap "Continue in browser" || true; sleep 3; }
flutter_press() { hold "Continue in browser" 900 || true; sleep 1 }
flutter_tabs() {
  tap "Services" || true; sleep 1.6
  tap "Agents" || true; sleep 1.6
  tap "Nodes" || true; sleep 1.2
}
flutter_detail() { tap "devbox" || true; sleep 2; tap "Back" || true; sleep 1.2; }

install_app "$kotlin_apk" || true
launch "$kotlin_apk" "$app"
record kotlin-expand 5 kotlin_expand
record kotlin-start 8 kotlin_start
record kotlin-press 3 kotlin_press

install_app "$flutter_apk" || true
# The preview shell runs on mock data: no tailnet needed for the tabs.
launch "$flutter_apk" "$app" "taildeck://preview/?preview=1&tab=0&lang=en"
record flutter-tabs 7 flutter_tabs
launch "$flutter_apk" "$app" "taildeck://preview/?preview=1&tab=0&lang=en"
record flutter-detail 5 flutter_detail

launch "$flutter_apk" "$app" "taildeck://preview/?login=1&lang=en"
record flutter-expand 5 flutter_expand
record flutter-start 5 flutter_start
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
