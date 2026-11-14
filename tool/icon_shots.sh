#!/usr/bin/env bash
# Installs two APKs one after the other on a booted emulator, screenshots the
# icon the system draws for each and builds side-by-side montages.
# Usage: tool/icon_shots.sh <apk-a> <apk-b> [out-dir]
set -euo pipefail

a=${1:?usage: tool/icon_shots.sh <apk-a> <apk-b> [out-dir]}
b=${2:?usage: tool/icon_shots.sh <apk-a> <apk-b> [out-dir]}
out=${3:-icons}
app=${APP_ID:-top.bangwu.taildeck}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"

adb wait-for-device
adb shell input keyevent KEYCODE_WAKEUP > /dev/null 2>&1 || true

# first node whose attributes match one of the patterns: bounds_of <file> <regex...>
bounds_of() {
  python3 - "$@" <<'PY'
import re, sys
try:
    xml = open(sys.argv[1]).read()
except OSError:
    xml = ''
for tag in re.findall(r'<node[^>]*>', xml):
    if any(re.search(p, tag) for p in sys.argv[2:]):
        m = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        if m:
            print(*m.groups())
            break
PY
}

dump() { # fresh UI dump -> path in $out
  adb shell uiautomator dump /sdcard/icon_dump.xml > /dev/null 2>&1 || true
  adb shell cat /sdcard/icon_dump.xml > "$out/dump-$1.xml" 2>/dev/null || true
  echo "$out/dump-$1.xml"
}

crop() { # crop <png> <x> <y> <w> <h> <dest>
  convert "$1" -crop "$4x$5+$2+$3" +repage "$6"
}

shoot() { # shoot <label> <apk>
  local label=$1 apk=$2 file box lbox x1 y1 x2 y2 tries=0
  adb uninstall "$app" > /dev/null 2>&1 || true
  adb install -g "$apk" > "$out/install-$label.txt" 2>&1 \
    || { echo "$label: install failed" >> "$summary"; return 1; }

  # Launcher drawer: the entry as the launcher lays it out, icon and label.
  adb shell input keyevent KEYCODE_HOME > /dev/null 2>&1 || true
  sleep 2
  adb shell input swipe 540 2100 540 600 250 > /dev/null 2>&1 || true
  sleep 3
  file=$(dump "$label-drawer")
  box=$(bounds_of "$file" 'text="Taildeck"' 'content-desc="Taildeck"' | head -1)
  adb exec-out screencap -p > "$out/$label-launcher.png"
  if [ -n "$box" ]; then
    set -- $box
    echo "$label launcher entry: $box" >> "$summary"
    crop "$out/$label-launcher.png" "$(( $1 - 12 ))" "$(( $2 - 12 ))" \
      "$(( $3 - $1 + 24 ))" "$(( $4 - $2 + 24 ))" "$out/$label-cell.png"
  else
    echo "$label launcher entry: not found in the drawer" >> "$summary"
  fi
  adb shell input keyevent KEYCODE_HOME > /dev/null 2>&1 || true

  # App info: the icon and label the system draws, at a fixed position, which
  # is what the pixel comparison uses. Settings is Compose on API 34, so the
  # icon node has no id and the label anchors the crop.
  adb shell am start -W -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:$app" > /dev/null 2>&1 || true
  until grep -q 'package="com.android.settings"' "$(dump "$label-info")" || [ "$tries" -ge 10 ]; do
    tries=$(( tries + 1 ))
    sleep 1
  done
  adb exec-out screencap -p > "$out/$label-appinfo.png"
  file="$out/dump-$label-info.xml"
  lbox=$(bounds_of "$file" 'text="Taildeck"' | head -1)
  if grep -q 'package="com.android.settings"' "$file" && [ -n "$lbox" ]; then
    set -- $lbox; x1=$1; y1=$2; x2=$3; y2=$4
    echo "$label app info label: $lbox" >> "$summary"
    crop "$out/$label-appinfo.png" "$(( (x1 + x2) / 2 - 110 ))" "$(( y1 - 180 ))" 220 170 "$out/$label-icon.png"
    convert "$out/$label-appinfo.png" \
      -crop "$(identify -format %w "$out/$label-appinfo.png")x$((y2 + 120))+0+0" +repage "$out/$label-header.png"
  else
    echo "$label app info: settings did not come up" >> "$summary"
  fi
  adb shell input keyevent KEYCODE_HOME > /dev/null 2>&1 || true
  sleep 1
}

shoot a "$a"
shoot b "$b"

for shot in icon header; do
  [ -s "$out/a-$shot.png" ] && [ -s "$out/b-$shot.png" ] || continue
  if [ "$(identify -format '%wx%h' "$out/a-$shot.png")" = "$(identify -format '%wx%h' "$out/b-$shot.png")" ]; then
    diff=$(compare -metric AE "$out/a-$shot.png" "$out/b-$shot.png" "$out/diff-$shot.png" 2>&1 || true)
    echo "$shot: pixels differing ${diff:-unknown} (of $(identify -format '%wx%h' "$out/a-$shot.png"))" >> "$summary"
  fi
done

montage -font DejaVu-Sans -pointsize 24 -fill '#E8EAED' -background '#101214' \
  -label "Kotlin app v0.1.0\n$app" "$out/a-icon.png" \
  -label "Flutter app (this build)\n$app" "$out/b-icon.png" \
  -tile 2x1 -geometry '440x+24+24' "$out/icon-compare.png"
for pair in 'cell:launcher-compare' 'header:appinfo-compare'; do
  src=${pair%%:*}; dest=${pair#*:}
  [ -s "$out/a-$src.png" ] && [ -s "$out/b-$src.png" ] || continue
  montage -font DejaVu-Sans -pointsize 24 -fill '#E8EAED' -background '#101214' \
    -label "Kotlin app v0.1.0\n$app" "$out/a-$src.png" \
    -label "Flutter app (this build)\n$app" "$out/b-$src.png" \
    -tile 2x1 -geometry '440x+24+24' "$out/$dest.png"
done

cat "$summary"
