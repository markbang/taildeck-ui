#!/usr/bin/env bash
# Tab switch gate: ten switches on a running emulator, each captured mid-flight
# and at rest. A switch may never blend two pages: the app logs what it really
# paints (?tabprobe=1). That probe log says when a switch has arrived (p=1.00,
# painted=1, blend=0), so the accessibility tree is read only after the app
# itself calls the page final. The tree then has to expose one page, and the
# target one. Headers are read by each node's top edge inside the title band: a
# page whose body is one merged semantics node carries its title over the whole
# screen, and that node's centre sits below any such band.
#
# A dump taken before the tree is published, or while a spinner keeps
# uiautomator from idling, comes back empty or stale, so a switch that has not
# arrived yet, or a tree with no header in it, is waited out. Two headers, or a
# page that never becomes the target, fail at once. A failure names the switch,
# the probe sample and the tree it saw, and leaves the dump behind.
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
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
slow=${TABS_SLOW:-6}
require_probe=${TABS_REQUIRE_PROBE:-1}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
note() { echo "$*" | tee -a "$summary"; }

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }

# What the failing step saw, on disk and in the artifact: the dump, every label
# in the title band, the current probe samples and a still.
dump_fail() { # <label>
  local label=$1
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb shell uiautomator dump /sdcard/ui.xml > "$out/uiautomator-fail.txt" 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui-fail-$label.xml" > /dev/null 2>&1 || true
  python3 "$here/ui.py" "$out/ui-fail-$label.xml" toptexts "${ymax:-720}" \
    > "$out/ui-fail-$label.txt" 2> /dev/null || true
  shot "fail-$label"
}
fail() {
  echo "FAIL: $*" | tee -a "$summary"
  dump_fail "${step:-run}"
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

ui() {
  local attempt
  for attempt in 1 2 3; do
    # A stale dump must not stand in for this one: a failed pull would
    # otherwise leave the previous tree in place.
    rm -f "$out/ui.xml"
    adb shell uiautomator dump /sdcard/ui.xml > "$out/uiautomator.txt" 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    if python3 "$here/ui.py" "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

# The probe is the app's own record of what it painted: one line per sampled
# frame, "taildeck tabprobe: from=0 to=3 p=1.00 painted=1 blend=0 tabs=3".
probes() { adb logcat -d -s flutter 2> /dev/null | grep 'taildeck tabprobe:' || true; }
probe_count() { probes | wc -l | tr -d ' '; }
probe_since() { probes | tail -n +"$(( $1 + 1 ))" || true; }

# A switch has arrived when a sample after the tap reports the target page at
# p=1.00 with one page painted and no blend.
arrival() { # <base-count> <target>
  probe_since "$1" | awk -v to="to=$2" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == to) seen = 1
        if ($i == "p=1.00") done = 1
        if ($i == "painted=1") one = 1
        if ($i ~ /^blend=[1-9]/) blend = 1
      }
      if (seen && done && one && !blend) hit = $0
      seen = done = one = blend = 0
    }
    END { if (hit) print hit }'
}

wait_arrival() { # <base-count> <target> <limit-seconds>
  local i=0 limit=$3 line
  [ "$require_probe" = 1 ] || return 0
  while [ "$i" -lt "$limit" ]; do
    line=$(arrival "$1" "$2")
    [ -z "$line" ] || { echo "$line"; return 0; }
    sleep 1
    i=$((i + 1))
  done
  return 1
}

# How the probe saw the frames since the tap: the check is that no frame
# blended two pages, whatever a still happens to catch.
mid_flight() { # <base-count> <what>
  local samples painted blended
  [ "$require_probe" = 1 ] || return 0
  samples=$(probe_since "$1")
  [ -n "$samples" ] || { note "$2 mid-flight: no probe sample yet"; return 0; }
  blended=$(grep -cE ' blend=[1-9]' <<< "$samples" || true)
  painted=$(grep -oE ' painted=[0-9]+' <<< "$samples" | sed 's/ painted=//' | sort -u | paste -sd, -)
  if [ "${blended:-0}" -ne 0 ]; then
    tail -n 10 <<< "$samples" >> "$summary"
    fail "$2 painted a blended frame mid-animation ($blended samples)"
  fi
  note "$2 mid-flight: painted=$painted blend=0, $(wc -l <<< "$samples") samples"
}

# The screen size and the four dock tap points, read from their labels once.
W= SH= DOCK_Y= TAP=()
geometry() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  [ -n "${W:-}" ] || fail "no screen size"
}
dock() {
  local point attempt
  # The dock's labels reach the accessibility tree a moment after the shell
  # paints; wait for them instead of calling the shell missing.
  for attempt in $(seq 1 15); do
    point=$(ui tap Services) && break
    sleep 2
  done
  [ -n "${point:-}" ] || {
    shot dock-fail
    ui toptexts "$SH" > "$out/dock-fail.txt" 2> /dev/null || true
    fail "no 'Services' in the dock after 30 s; the shell did not start"
  }
  DOCK_Y=${point#* }
  TAP=(
    "$((W / 8)) $DOCK_Y"
    "$((W * 3 / 8)) $DOCK_Y"
    "$((W * 5 / 8)) $DOCK_Y"
    "$((W * 7 / 8)) $DOCK_Y"
  )
}

# The page must be ours, in front. Without this an empty accessibility tree
# (app gone, screen off) would read as "no page", which is legal only while a
# switch is in flight. The shared check also reads the focused app and the
# resumed activity: mCurrentFocus names the launcher for a moment after a
# switch on this emulator while the app's window is already ours.
alive() { # <step>
  gate_in_front "$app" && return 0
  adb shell pidof "$app" > /dev/null 2>&1 \
    || fail "$1: $app is not running (crashed or was killed)"
  fail "$1: $app is not in front ($(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'))"
}

header_count() { # <space-separated headers>
  local n
  n=$(wc -w <<< "$1")
  echo "${n:-0}"
}

# One label per page header in the title band. The dock sits below it, so a
# dump of the band holds the headers and nothing that merely repeats them.
headers() { # <texts-file>
  awk -v titles="${titles[*]}" '
    BEGIN { n = split(titles, t, " ") }
    # The demo dataset titles the node list after the tailnet.
    index($0, "markbang.github") > 0 { print "Nodes"; next }
    { for (i = 1; i <= n; i++) if (index($0, t[i]) > 0) { print t[i]; break } }
  ' "$1" | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

# The tab's own header, or the demo tailnet name on the node list.
page_is() { # <seen> <tab index>
  [ "$1" = "${titles[$2]}" ] && return 0
  [ "$2" = 0 ] && [ "$1" = markbang.github ] && return 0
  return 1
}

# At rest the page is the target and only the target. The wait is for the app
# to arrive (probe) and for the tree to catch up (a dump that still shows the
# page being left, or none at all, is a tree that has not published yet); the
# assertion runs on what the tree finally says. Two headers end the wait at
# once and fail with it. Sets settled and settle_error.
settle() { # <index> <tag> <target> <base-count>
  local tag=$2 target=$3 base=$4 attempt line count
  settled=""
  settle_error=""
  if ! line=$(wait_arrival "$base" "$target" 25); then
    settle_error="switch $1 never arrived on ${names[$target]}: no probe sample reached p=1.00 painted=1 to=$target in 25 s"
    return 1
  fi
  [ -z "$line" ] || note "switch $1 arrival: $line"
  for attempt in 1 2 3 4 5 6 7 8; do
    ui heads "$ymax" > "$out/headers-$tag.txt" 2>> "$out/uiautomator.txt" || true
    settled=$(headers "$out/headers-$tag.txt")
    count=$(header_count "$settled")
    [ "$count" -lt 2 ] || break
    if page_is "$settled" "$target"; then return 0; fi
    sleep 1
  done
  count=$(header_count "$settled")
  if [ "$count" -ne 1 ]; then
    settle_error="switch $1 exposed [$settled] at rest; exactly one page must be on screen"
    return 1
  fi
  settle_error="switch $1 left [$settled] where only '${titles[$target]}' may be"
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
      # The shell must be in front with its launch screen gone before a tap.
      wait_home "$app" "$out" "$here" Services 45 && return 0
    fi
    note "launch attempt $attempt: no tab bar yet"
    sleep 5
  done
  fail "the shell never showed a tab bar"
}

geometry
launch
dock
step=setup
note "screen ${W}x${SH}, dock y=$DOCK_Y"
shot rest-00
ui tap Nodes > /dev/null 2>&1 || true

# Ten switches, each one still mid-animation and once at rest. The probe log
# names the painted pages; the stills are the evidence a person reads.
ymax=$((SH * 3 / 10))
last=0
for i in $(seq 1 10); do
  target=${sequence[$((i - 1))]}
  tag=$(printf %02d "$i")
  step="switch-$tag-mid"
  base=$(probe_count)
  # shellcheck disable=SC2086
  adb shell input tap ${TAP[$target]} > /dev/null 2>&1 || true
  sleep 0.9
  shot "mid-$tag"
  mid_flight "$base" "switch $i"
  alive "switch $i mid-flight"
  step="switch-$tag-rest"
  if ! settle "$i" "$tag" "$target" "$base"; then
    probe_since "$base" | tail -n 10 >> "$summary"
    fail "$settle_error"
  fi
  shot "rest-$tag"
  alive "switch $i at rest"
  note "switch $i -> ${names[$target]}: headers [$settled] at rest"
  last=$target
done

# Ten taps as fast as adb sends them: each one must cancel the last animation
# and the last tab must win.
adb shell screenrecord --time-limit 25 --bit-rate 4000000 --size 540x1200 \
  /sdcard/tabs.mp4 > /dev/null 2>&1 &
recorder=$!
sleep 0.6
base=$(probe_count)
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
step=rapid-taps
if ! settle final rapid "$last" "$base"; then
  probe_since "$base" | tail -n 10 >> "$summary"
  fail "$settle_error"
fi
note "after rapid taps: headers [$settled], last tap ${names[$last]}"

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

note "ok: 10 switches, no blended frame, one page at rest each time, no Flutter exception"
