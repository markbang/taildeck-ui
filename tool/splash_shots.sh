#!/usr/bin/env bash
# Records the cold start (light and dark) of this build and of the Kotlin
# reference app, then puts them side by side: splash stills, first-frame times
# and an hstack video. Fails only when one of the apps never reaches its first
# frame; media problems are written to summary.txt instead.
# Usage: tool/splash_shots.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/splash_shots.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-splash}
kotlin_apk=${KOTLIN_APK:-build/kotlin.apk}
kotlin_url=${KOTLIN_APK_URL:-https://github.com/markbang/taildeck/releases/download/v0.1.0/taildeck-0.1.0-x86_64.apk}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"

note() { echo "$*" | tee -a "$summary"; }

adb wait-for-device

[ -s "$kotlin_apk" ] || curl -fsSL -o "$kotlin_apk" "$kotlin_url"

# The first cut in the recording: launcher -> launch screen.
scene_start() { # <mp4> -> seconds
  ffmpeg -i "$1" -vf "select='gt(scene,0.12)',metadata=print" -f null - 2>&1 \
    | sed -n 's/.*pts_time:\([0-9.]*\).*/\1/p' | head -1
}

# Size of the mark on a still: the splash is a flat colour, so the trim of the
# centre is the icon.
mark_box() { # <png> -> WxH
  local side
  side=$(identify -format '%[fx:int(min(w,h)*0.6)]' "$1")
  convert "$1" -gravity center -crop "${side}x${side}+0+0" +repage \
    -fuzz 4% -trim info: 2>/dev/null | awk '{print $3}'
}

record() { # <label> <apk> <night yes|no>
  local label=$1 a=$2 night=$3 activity total displayed start
  adb shell cmd uimode night "$night" > /dev/null 2>&1 || true
  sleep 2
  adb uninstall "$app" > /dev/null 2>&1 || true
  adb install -g "$a" > "$out/install-$label.txt" 2>&1 \
    || { note "$label: install failed, see install-$label.txt"; return 1; }
  activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null \
    | tail -n 1 | tr -d '\r')
  [ -n "$activity" ] || { note "$label: no launcher activity"; return 1; }
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  # The recording must start on the launcher, not on whatever the previous
  # step left in front, or the first cut in it is not the launch screen.
  adb shell input keyevent KEYCODE_HOME > /dev/null 2>&1 || true
  sleep 3
  adb logcat -c > /dev/null 2>&1 || true
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true

  # The recording starts on the launcher, before the app is launched.
  adb shell screenrecord --time-limit 12 --bit-rate 8000000 /sdcard/rec.mp4 \
    > /dev/null 2>&1 &
  local recorder=$!
  sleep 1.5
  adb shell am start -W -n "$activity" > "$out/launch-$label.txt" 2>&1 || true
  sleep 7
  wait "$recorder" 2> /dev/null || true
  adb pull /sdcard/rec.mp4 "$out/$label.mp4" > /dev/null 2>&1 || true

  total=$(grep -m1 -E '^TotalTime' "$out/launch-$label.txt" | tr -d '\r' || true)
  displayed=$(adb logcat -d 2>/dev/null | grep -m1 "Displayed $app/" | tr -d '\r' || true)
  note "$label: ${total:-TotalTime missing} | ${displayed:-Displayed missing}"
  [ -n "$displayed" ] || return 1

  # am start runs 1.5s into the recording; the launch screen follows within a
  # few hundred ms. Trust the first cut only when it lands in that window.
  start=$(awk -v d="$(scene_start "$out/$label.mp4" || true)" \
    'BEGIN{print (d > 0.8 && d < 3.5) ? d : 1.7}')
  # am start's TotalTime is where the launch screen ends in the recording.
  first=$(awk -v t="${total#*: }" 'BEGIN{print t/1000}')
  note "$label: launch screen at ${start}s, first frame ${first}s later"

  grab() { # <seconds after the launch screen> <name>
    ffmpeg -loglevel error -y \
      -ss "$(awk -v a="$start" -v b="$1" 'BEGIN{print a+b}')" \
      -i "$out/$label.mp4" -frames:v 1 "$out/$label-$2.png" || true
  }
  grab 0.25 splash
  grab "$(awk -v t="$first" 'BEGIN{print t+0.6}')" app
  [ -s "$out/$label-splash.png" ] && note "$label: mark $(mark_box "$out/$label-splash.png")"

  ffmpeg -loglevel error -y -ss "$(awk -v a="$start" -v b=0.3 'BEGIN{print (a>b?a-b:0)}')" \
    -i "$out/$label.mp4" -t 3 -an -vf 'scale=405:-2' "$out/$label-3s.mp4" || true
}

ok=0
for mode in light dark; do
  night=no
  [ "$mode" = dark ] && night=yes
  if record "flutter-$mode" "$apk" "$night"; then ok=$((ok + 1)); fi
done
for mode in light dark; do
  night=no
  [ "$mode" = dark ] && night=yes
  record "kotlin-$mode" "$kotlin_apk" "$night" || true
done

still() { # <png> <label>
  convert "$1" -resize 405x -background '#101214' -gravity south \
    -splice 0x28 -font DejaVu-Sans -pointsize 18 -fill '#E8EAED' \
    -annotate +0+6 "$2" "$1.labeled.png" 2>/dev/null || true
}

pair() { # <a> <b> <dest>; a/b are still names without .png
  [ -s "$out/$1.png" ] && [ -s "$out/$2.png" ] || return 0
  still "$out/$1.png" "$1"
  still "$out/$2.png" "$2"
  montage "$out/$1.png.labeled.png" "$out/$2.png.labeled.png" \
    -tile 2x1 -geometry +12+12 -background '#101214' "$out/$3.png" 2>/dev/null || true
}

pair flutter-light-splash flutter-dark-splash flutter-splash-light-dark
pair kotlin-light-splash flutter-light-splash kotlin-vs-flutter-light
pair kotlin-dark-splash flutter-dark-splash kotlin-vs-flutter-dark

hstack() { # <left> <right> <dest>
  [ -s "$out/$1-3s.mp4" ] && [ -s "$out/$2-3s.mp4" ] || return 0
  ffmpeg -loglevel error -y -i "$out/$1-3s.mp4" -i "$out/$2-3s.mp4" \
    -filter_complex '[0:v]scale=405:-2,pad=405:ih+0:0:0:color=0x101214[l];[1:v]scale=405:-2[r];[l][r]hstack=inputs=2' \
    -an "$out/$3.mp4" || true
}

hstack flutter-light flutter-dark flutter-light-dark
hstack kotlin-light flutter-light kotlin-vs-flutter-light
hstack kotlin-dark flutter-dark kotlin-vs-flutter-dark

# A GIF is what a pull request can show inline; the mp4s go in the artifact.
[ -s "$out/flutter-light-dark.mp4" ] && ffmpeg -loglevel error -y \
  -i "$out/flutter-light-dark.mp4" -vf 'fps=10,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
  "$out/flutter-light-dark.gif" || true
[ -s "$out/kotlin-vs-flutter-light.mp4" ] && ffmpeg -loglevel error -y \
  -i "$out/kotlin-vs-flutter-light.mp4" -vf 'fps=10,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
  "$out/kotlin-vs-flutter-light.gif" || true

for f in "$out"/*-splash.png "$out"/*.gif; do
  [ -s "$f" ] || continue
  note "$(basename "$f"): $(stat -c%s "$f") bytes"
done

# Leave the build under test installed: the Kotlin app shares its application
# id, so a later step would otherwise smoke the wrong app.
adb install -r -g "$apk" > "$out/reinstall.txt" 2>&1 || true

[ "$ok" -ge 2 ] || { note "FAIL: this build did not reach a first frame"; exit 1; }
note "ok: cold start recorded light and dark"
