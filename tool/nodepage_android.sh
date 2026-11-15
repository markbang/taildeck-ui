#!/usr/bin/env bash
# Node page gate: cold-start, open a node's detail page and fail when the
# content area is the grey ErrorWidget or a Flutter exception reached logcat.
# Uses the debug/profile build, whose demo dataset gives the preview a node.
# Usage: tool/nodepage_android.sh <apk> [application-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/nodepage_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-node}
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

# A fresh install: the gates run different builds of the same package id in
# one job, and a release build's version code or signature would block an
# update from the debug APK.
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"

# `preview=1` shows the signed-in shell without a tailnet, `node=*` opens the
# first node the list has.
adb logcat -c > /dev/null 2>&1 || true
adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&node=*' -n $activity" \
  > "$out/launch.txt" 2>&1 || fail "am start failed, see launch.txt"
grep -q "Activity: $app/" "$out/launch.txt" || fail "am start did not land on $app, see launch.txt"

opened=''
for _ in $(seq 1 60); do
  if adb logcat -d 2>/dev/null | grep -q "taildeck preview: node="; then
    opened=1
    break
  fi
  sleep 1
done
[ -n "$opened" ] || fail "the node page never opened; logcat: $(adb logcat -d 2>/dev/null | grep 'taildeck preview' | tail -n 3 | tr '\n' ' ')"
sleep 4

adb exec-out screencap -p > "$out/node-page.png" || fail "screencap failed"

# Flutter paints a failed build as a flat grey box (#B6B6B6) in release and a
# red one in debug; either way the page has no contrast. Crop away the status
# bar and the navigation dock before measuring.
convert "$out/node-page.png" -gravity center -crop 60%x40%+0+0 +repage \
  "$out/node-page-content.png" 2>/dev/null || fail "could not crop the screenshot"
mean=$(identify -format '%[fx:mean]' "$out/node-page-content.png" 2>/dev/null || echo 1)
std=$(identify -format '%[fx:standard_deviation]' "$out/node-page-content.png" 2>/dev/null || echo 0)
echo "content mean=$mean std=$std" | tee -a "$out/summary.txt"

if awk -v s="$std" 'BEGIN { exit !(s < 0.02) }'; then
  fail "the node page content is a flat colour (std $std): the grey ErrorWidget"
fi
if awk -v m="$mean" -v s="$std" 'BEGIN { exit !(m > 0.5 && s < 0.05) }'; then
  fail "the node page content is the grey ErrorWidget (mean $mean, std $std)"
fi

exceptions=$(adb logcat -d 2>/dev/null \
  | grep -hE -e 'EXCEPTION CAUGHT BY' -e 'Another exception was thrown' -e 'Bad state: ' \
  | head -n 5 || true)
if [ -n "$exceptions" ]; then
  printf '%s\n' "$exceptions" | tee -a "$out/summary.txt"
  fail "a Flutter exception was logged while the node page was open"
fi

pass "node page rendered with no Flutter exception (content mean $mean, std $std)"
