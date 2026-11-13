#!/usr/bin/env bash
# Screenshot the built web app with headless Chrome: five pages, phone and desktop.
set -euo pipefail

out=${1:-shots}
base=${2:-http://127.0.0.1:8099/taildeck-ui/}
chrome=${CHROME:-google-chrome}
mkdir -p "$out"

pages=(
  "nodes-en:?lang=en"
  "services:?tab=1"
  "agents:?tab=2"
  "settings:?tab=3"
  "nodes-zh:?lang=zh"
)
sizes=("414x896:phone" "1440x900:desktop")

for size in "${sizes[@]}"; do
  dims=${size%:*}
  label=${size#*:}
  for page in "${pages[@]}"; do
    name=${page%%:*}
    query=${page#*:}
    target="$out/$name-$label-$dims.png"
    for _ in 1 2 3; do
      profile=$(mktemp -d)
      timeout 60 "$chrome" --headless=new --no-sandbox --enable-unsafe-swiftshader --hide-scrollbars \
        --user-data-dir="$profile" --window-size="${dims/x/,}" \
        --virtual-time-budget=8000 --screenshot="$target" "$base$query" >/dev/null 2>&1 || true
      rm -rf "$profile"
      # CanvasKit's first frame can be a flat colour; keep the shot only when it has contrast.
      if [ -s "$target" ] &&
        awk -v s="$(identify -format '%[fx:standard_deviation]' "$target")" 'BEGIN { exit !(s > 0.02) }'; then
        break
      fi
      rm -f "$target"
    done
    [ -s "$target" ] || { echo "no screenshot for $base$query" >&2; exit 1; }
    echo "$target $(stat -c%s "$target") bytes"
  done
done
