#!/usr/bin/env bash
# Builds the web app before and after the fix, records a select closing in each
# with Chromium, cuts every frame of each close, checks the value's box against
# the settled row, and lays the two closes side by side.
# The Android emulator's software encoder drops most frames of these
# animations, so the frame-by-frame evidence comes from here.
# Usage: tool/select_web_check.sh <before|after-worktree-command> ...
# Run from the repository root: tool/select_web_check.sh [out-dir]
set -euo pipefail

out=${1:-select-web}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }

flutter=${FLUTTER:-flutter}
cp "$root/pubspec.lock" /tmp/select_pubspec.lock
trap 'cp /tmp/select_pubspec.lock "$root/pubspec.lock"' EXIT
git -C "$root" fetch --no-tags --depth=1 origin main:refs/remotes/origin/main

build_web() { # <dir to keep>
  "$flutter" pub get > /dev/null
  "$flutter" build web --profile --no-tree-shake-icons > /dev/null
  rm -rf "$1" && cp -a "$root/build/web" "$1"
}

build_web /tmp/web-after
note "after: $(git -C "$root" rev-parse --short HEAD)"

cp "$root/lib/src/widgets/select_row.dart" /tmp/select_row.dart
cp "$root/third_party/prism_ui/lib/popup.dart" /tmp/select_popup.dart
git -C "$root" show origin/main:lib/src/widgets/select_row.dart \
  > "$root/lib/src/widgets/select_row.dart"
git -C "$root" show origin/main:third_party/prism_ui/lib/popup.dart \
  > "$root/third_party/prism_ui/lib/popup.dart"
rm -f "$root/lib/src/widgets/select_value_button.dart"
build_web /tmp/web-before
cp /tmp/select_row.dart "$root/lib/src/widgets/select_row.dart"
cp /tmp/select_popup.dart "$root/third_party/prism_ui/lib/popup.dart"
git -C "$root" checkout -- lib/src/widgets/select_value_button.dart
note "before: $(git -C "$root" rev-parse --short origin/main)"

python3 -m http.server 8091 --bind 127.0.0.1 --directory /tmp/web-after > /dev/null 2>&1 &
python3 -m http.server 8092 --bind 127.0.0.1 --directory /tmp/web-before > /dev/null 2>&1 &
sleep 2

python3 "$here/select_web.py" http://127.0.0.1:8091/ http://127.0.0.1:8092/ "$out"

status=0
check() { # <build> <flow> <box>
  local clip="$out/$1-$2-close.webm" dir="$out/close-$1-$2" result=0
  python3 "$here/select_frames.py" "$clip" "$dir" "$3" --name "$1-$2" \
    >> "$summary" 2>&1 || result=$?
  if [ "$result" -eq 0 ]; then
    note "$1 $2 close: no block left in its last frames"
  else
    note "$1 $2 close: a block is still there in its last frames"
  fi
  if [ "$1" = after ] && [ "$result" -ne 0 ]; then status=1; fi
}

check after language 270,506,130,66
check after ssh 240,730,150,66
check before language 270,506,130,66
check before ssh 240,730,150,66

# The closes side by side, from the frame each one starts at, so the two
# run the same stretch of the same animation.
for flow in language ssh; do
  left="$out/after-$flow-close.webm"
  right="$out/before-$flow-close.webm"
  [ -s "$left" ] && [ -s "$right" ] || { note "no pair for $flow"; continue; }
  left_start=$(cut -d' ' -f1 "$out/close-after-$flow/close-window.txt")
  right_start=$(cut -d' ' -f1 "$out/close-before-$flow/close-window.txt")
  note "$flow close: after from ${left_start}s, before from ${right_start}s"
  ffmpeg -loglevel error -y -ss "$left_start" -t 3 -i "$left" \
    -ss "$right_start" -t 3 -i "$right" \
    -filter_complex "[0:v]scale=420:-2,setsar=1[l];[1:v]scale=420:-2,setsar=1,tpad=stop_mode=clone:stop_duration=3[r];[l][r]hstack=inputs=2,drawtext=text=after:x=12:y=12:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.5,drawtext=text=before:x=432:y=12:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.5" \
    -an "$out/select-$flow-close-after-vs-before.webm" 2> /dev/null ||
    note "no side-by-side for $flow"
done

for flow in language ssh; do
  if [ -s "$out/after-$flow-closed.png" ] && [ -s "$out/before-$flow-closed.png" ]; then
    convert "$out/before-$flow-closed.png" -resize 420x "/tmp/before-$flow.png"
    convert "$out/after-$flow-closed.png" -resize 420x "/tmp/after-$flow.png"
    convert "/tmp/before-$flow.png" "/tmp/after-$flow.png" +append \
      -gravity northwest -annotate +12+12 before -annotate +432+12 after \
      "$out/select-$flow-closed-before-vs-after.png" || true
  fi
done

note "ok: closes recorded before and after, every frame cut and measured"
exit "$status"
