#!/usr/bin/env bash
# Tab switch gate: ten switches on a running emulator, each captured mid-flight
# and at rest. A switch may never blend two pages: the app logs what it really
# paints (?tabprobe=1). Mid-animation the accessibility tree holds zero or one
# page header (a fade-through is legitimately between pages); at rest it must
# settle to exactly the target header, never two. Any Flutter exception fails
# the run, and so does a dismissed app: pid and focus are checked every step.
#
# The build must be a debug one: it carries the demo data the preview shell
# needs, the probe and ?slow=, which stretches the transition so a still can
# land inside it.
# Usage: tool/tabs_android.sh <apk> [application-id] [out-dir]
#        TABS_REQUIRE_PROBE=0 records on a build without the probe (the "before"
#        clip) and only checks the resting state.
set -euo pipefail

apk=${1:?usage: tool/tabs_android.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-tabs}
here=$(cd "$(dirname "$0")" && pwd)
slow=${TABS_SLOW:-6}
require_probe=${TABS_REQUIRE_PROBE:-1}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }
fail() {
  echo "FAIL: $*" | tee -a "$summary"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui-fail.xml" > /dev/null 2>&1 || true
  exit 1
}

# The four page headers, in dock order. A build with the demo data titles the
# node list after the demo tailnet; a debug build without it falls back to the
# tab name, so both count as the node page.
titles=(Nodes Services Agents Settings)
names=(Nodes Services Agents Settings)
sequence=(1 2 1 0 3 1 2 1 0 3)

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true

# Always this APK: a gate that reused whatever was installed (the release
# build, with no probe and no demo data) would pass while checking nothing.
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
sleep 2

activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }

ui() {
  local attempt
  for attempt in 1 2 3; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if python3 "$here/ui.py" "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

# The screen size and the four dock tap points, read from their labels once.
W= SH= DOCK_Y= TAP=()
geometry() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  [ -n "${W:-}" ] || fail "no screen size"
}
dock() {
  local point
  point=$(ui tap Services) || fail "no 'Services' in the dock; the shell did not start"
  DOCK_Y=${point#* }
  TAP=(
    "$((W / 8)) $DOCK_Y"
    "$((W * 3 / 8)) $DOCK_Y"
    "$((W * 5 / 8)) $DOCK_Y"
    "$((W * 7 / 8)) $DOCK_Y"
  )
}

# The page must be ours, in front. Without this an empty accessibility tree
# (app gone, screen off) would read as "zero headers", which is legal only
# while a switch is in flight.
alive() { # <step>
  local pid focus
  pid=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
  [ -n "$pid" ] || fail "$1: $app is not running (crashed or was killed)"
  focus=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r' || true)
  case "$focus" in
    *"$app/"*) ;;
    *) fail "$1: $app is not in front ($focus)" ;;
  esac
}

header_count() { # <space-separated headers>
  local n
  n=$(wc -w <<< "$1")
  echo "${n:-0}"
}

# The tab's own header, or the demo tailnet name on the node list.
expect_header() { # <seen> <tab index> <what>
  if [ "$1" = "${titles[$2]}" ] ||
    { [ "$2" = 0 ] && [ "$1" = markbang.github ]; }; then
    return 0
  fi
  fail "$3 left [$1] instead of only '${titles[$2]}'"
}

# One label per page header still on screen: the dock sits below the band, so a
# dump above it holds the headers and nothing that merely repeats their names.
headers() { # <texts-file>
  awk -v titles="${titles[*]}" '
    BEGIN { n = split(titles, t, " ") }
    # The demo dataset titles the node list after the tailnet.
    index($0, "markbang.github") > 0 { print "Nodes"; next }
    { for (i = 1; i <= n; i++) if (index($0, t[i]) > 0) { print t[i]; break } }
  ' "$1" | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

# At rest the page settles to exactly one header. A slow emulator can still be
# mid-fade when the still was taken, so poll instead of trusting one dump; two
# headers are a failure either way.
settle_headers() { # <index> <tag>
  local attempt found=""
  for attempt in 1 2 3 4 5 6; do
    if ui texts "$ymax" > "$out/headers-$2.txt" 2> /dev/null; then
      found=$(headers "$out/headers-$2.txt")
      [ "$(header_count "$found")" -eq 1 ] && { echo "$found"; return 0; }
    fi
    sleep 1
  done
  echo "$found"
  return 1
}

launch() {
  local attempt
  for attempt in 1 2 3; do
    adb shell am force-stop "$app" > /dev/null 2>&1 || true
    sleep 2
    adb logcat -c > /dev/null 2>&1 || true
    adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?preview=1&tab=0&tabprobe=1&splash=0&slow=$slow' -n $activity" \
      > "$out/launch.txt" 2>&1 || true
    if grep -q "Activity: $app/" "$out/launch.txt"; then
      for _ in $(seq 1 90); do
        if ui has Services > /dev/null 2>&1; then sleep 2; return 0; fi
        sleep 1
      done
    fi
    note "launch attempt $attempt: no tab bar yet"
    sleep 5
  done
  fail "the shell never showed a tab bar"
}

geometry
launch
dock
note "screen ${W}x${SH}, dock y=$DOCK_Y"
shot rest-00
ui tap Nodes > /dev/null 2>&1 || true

# Ten switches, each one still mid-animation and once at rest. The probe log
# names the painted pages; the stills are the evidence a person reads.
ymax=$((SH * 3 / 10))
last=0
for i in $(seq 1 10); do
  target=${sequence[$((i - 1))]}
  # shellcheck disable=SC2086
  adb shell input tap ${TAP[$target]} > /dev/null 2>&1 || true
  sleep 0.9
  shot "mid-$(printf %02d "$i")"
  # Mid-flight: zero or one header. Two means two pages are on screen at once.
  ui texts "$ymax" > "$out/mid-headers-$(printf %02d "$i").txt" 2> /dev/null || true
  mid_found=$(headers "$out/mid-headers-$(printf %02d "$i").txt")
  alive "switch $i mid-flight"
  [ "$(header_count "$mid_found")" -le 1 ] ||
    fail "switch $i painted two headers mid-animation [$mid_found]"
  note "switch $i mid-flight: headers [$mid_found]"
  sleep $((slow + 2))
  shot "rest-$(printf %02d "$i")"
  alive "switch $i at rest"
  found=$(settle_headers "$i" "$(printf %02d "$i")") ||
    fail "switch $i never settled to one header at rest [${found:-none}]"
  note "switch $i -> ${names[$target]}: headers [$found] at rest"
  expect_header "$found" "$target" "switch $i"
  last=$target
done

# Ten taps as fast as adb sends them: each one must cancel the last animation
# and the last tab must win.
adb shell screenrecord --time-limit 25 --bit-rate 4000000 --size 540x1200 \
  /sdcard/tabs.mp4 > /dev/null 2>&1 &
recorder=$!
sleep 0.6
for target in "${sequence[@]}"; do
  # shellcheck disable=SC2086
  adb shell input tap ${TAP[$target]} > /dev/null 2>&1 || true
  sleep 0.2
done
wait "$recorder" 2> /dev/null || true
sleep $((slow + 3))
adb pull /sdcard/tabs.mp4 "$out/tabs.mp4" > /dev/null 2>&1 || true
[ -s "$out/tabs.mp4" ] && note "clip: $(stat -c%s "$out/tabs.mp4") bytes" || note "no clip"

shot rest-final
alive "after rapid taps"
found=$(settle_headers final final) ||
  fail "rapid taps never settled to one header at rest [${found:-none}]"
note "after rapid taps: headers [$found], last tap ${names[$last]}"
expect_header "$found" "$last" "rapid taps"

adb logcat -d > "$out/logcat.txt" 2>&1 || true
probes=$(grep -c "taildeck tabprobe:" "$out/logcat.txt" 2> /dev/null || true)
blended=$(grep "taildeck tabprobe:" "$out/logcat.txt" 2> /dev/null | grep -cE 'blend=[1-9]' || true)
mid=$(grep "taildeck tabprobe:" "$out/logcat.txt" 2> /dev/null | grep -c 'painted=2' || true)
note "probe samples: ${probes:-0}, two pages painted: ${mid:-0}, blended: ${blended:-0}"
grep "taildeck tabprobe:" "$out/logcat.txt" 2> /dev/null | tail -40 >> "$summary" || true
if [ "$require_probe" = 1 ]; then
  [ "${probes:-0}" -ge 4 ] || fail "no tab probe samples: the build does not log its painted pages"
  [ "${blended:-0}" -eq 0 ] || fail "$blended probe samples painted two pages at once"
  [ "${mid:-0}" -ge 1 ] ||
    fail "no switch was sampled mid-flight: the app ran with reduced motion"
else
  note "probe not required: recording only"
fi

exceptions=$(grep -hE -e 'EXCEPTION CAUGHT BY' -e 'Another exception was thrown' "$out/logcat.txt" 2> /dev/null | head -n 5 || true)
if [ -n "$exceptions" ]; then
  printf '%s\n' "$exceptions" >> "$summary"
  fail "a Flutter exception was logged during the switches"
fi

# Frames of the transition for a pull request: the clip and the mid stills.
ffmpeg -loglevel error -y -i "$out/tabs.mp4" -vf "fps=8,scale=270:-2" \
  "$out/frames-%03d.png" 2> /dev/null || true
[ -s "$out/mid-02.png" ] && convert "$out/mid-02.png" -resize 360x "$out/frame-mid.png" 2> /dev/null || true

note "ok: 10 switches, at most one header mid-flight, exactly one at rest, no blended frame, no Flutter exception"
