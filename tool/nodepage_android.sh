#!/usr/bin/env bash
# Node page gate: cold-start, open a node's detail page and fail when the
# content area is the grey ErrorWidget or a Flutter exception reached logcat.
# Uses the debug/profile build, whose demo dataset gives the preview a node.
# Usage: tool/nodepage_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/nodepage_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-node}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
mkdir -p "$out"

fail() {
  echo "FAIL: $*" | tee -a "$out/summary.txt"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  exit 1
}
pass() { echo "ok: $*" | tee -a "$out/summary.txt"; }

adb wait-for-device
activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

if ! adb shell pm path "$app" > /dev/null 2>&1; then
  adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
fi

shot() { adb exec-out screencap -p > "$out/$1.png" || true; }

# The page announces itself before it opens; Flutter has no view ids.
open_node_page() {
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 3
  adb logcat -c > /dev/null 2>&1 || true
  # `?node=*` opens the first node the list has, `?node=devbox` the demo one.
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?node=*' -n $activity" \
    > "$out/launch.txt" 2>&1 || return 1
  grep -q "Activity: $app/" "$out/launch.txt" || return 1
  local shown=$SECONDS
  for _ in $(seq 1 60); do
    if adb logcat -d 2>/dev/null | grep -q "taildeck preview: node="; then
      sleep 5
      gate_survived_focus "$app" "$shown" "$out/summary.txt" || { launch_anr=1; return 1; }
      return 0
    fi
    sleep 1
  done
  return 1
}

launch_anr=0
if ! open_node_page; then
  [ "$launch_anr" = 1 ] || fail "the node page never opened; see launch.txt and logcat.txt"
  echo "launch attempt 1: the app was killed after an ANR at cold start" | tee -a "$out/summary.txt"
  launch_anr=0
  if ! open_node_page; then
    [ "$launch_anr" = 0 ] || fail "$app stopped answering input on two cold starts in a row"
    fail "the node page never opened; see launch.txt and logcat.txt"
  fi
fi

shot node-page

# Flutter paints a failed build as a flat grey box (#B6B6B6) in release and a
# red one in debug; either way the content area has no contrast.
geometry=$(adb shell wm size | tr -d '\r' | grep -oE '[0-9]+x[0-9]+' | tail -1)
width=${geometry%x*}
height=${geometry#*x}
# Drop the status bar and the navigation dock: the page fills the middle.
crop="${width}x$((height * 6 / 10))+0+$((height / 6))"
convert "$out/node-page.png" -crop "$crop" +repage "$out/node-page-content.png" 2>/dev/null || true
readings=$(convert "$out/node-page-content.png" \
  -format '%[fx:mean] %[fx:standard_deviation]' info: 2>/dev/null || echo '1 0')
mean=${readings%% *}
std=${readings##* }
echo "content mean=$mean std=$std ($crop)" | tee -a "$out/summary.txt"

if awk -v s="$std" 'BEGIN { exit !(s < 0.02) }'; then
  fail "the node page content is a flat colour (std $std): the grey ErrorWidget"
fi
if awk -v m="$mean" -v s="$std" 'BEGIN { exit !(m > 0.5 && s < 0.05) }'; then
  fail "the node page content is the grey ErrorWidget (mean $m, std $std)"
fi

exceptions=$(adb logcat -d 2>/dev/null \
  | grep -hE -e 'EXCEPTION CAUGHT BY' -e 'Another exception was thrown' -e 'Bad state: ' \
  | head -n 5 || true)
if [ -n "$exceptions" ]; then
  printf '%s\n' "$exceptions" | tee -a "$out/summary.txt"
  fail "a Flutter exception was logged while the node page was open"
fi

pass "node page rendered with no Flutter exception (content mean $mean, std $std)"
