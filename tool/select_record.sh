#!/usr/bin/env bash
# Records one select closing on one emulator: Settings > Language and the SSH
# sheet's Authentication row, on the build before and the build after the
# close-animation fix, plus FlClash closing its language menu. Cuts every frame
# of each close, checks that the value's box has settled by the clip's last
# frames, and lays the closes side by side.
# Usage: tool/select_record.sh <after.apk> <before.apk> <flclash.apk> [out-dir]
set -euo pipefail

after_apk=${1:?usage: tool/select_record.sh <after.apk> <before.apk> <flclash.apk> [out]}
before_apk=${2:?no before APK}
flclash_apk=${3:?no FlClash APK}
out=${4:-select}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tool/android_gate.sh
. "$here/android_gate.sh"
slow=${SELECT_SLOW:-5}
tail=${SELECT_TAIL:-15}
limit=${SELECT_LIMIT:-1.5}
app=top.bangwu.taildeck
flclash=com.follow.clash
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

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
sleep 5

W= SH=
geometry() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  [ -n "${W:-}" ] || fail "no screen size"
}

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }
back_key() { adb shell input keyevent 4 > /dev/null 2>&1 || true; }

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

tap_point() { # 'x y' [settle seconds]
  # shellcheck disable=SC2086
  adb shell input tap $1 > /dev/null 2>&1 || true
  sleep "${2:-1}"
}

tap_label() { # <text>
  local point
  point=$(ui tap "$1") || return 1
  tap_point "$point" 0.8
}

value_point() { # <text>: the row's value at its end, where a select opens from
  local box x1 y1 x2 y2
  box=$(ui bounds "$1") || return 1
  read -r x1 y1 x2 y2 <<< "$box"
  echo "$((x2 - 40)) $(((y1 + y2) / 2))"
}

value_box() { # <text>: x,y,w,h of the row's trailing end, for the frame check
  local box x1 y1 x2 y2 height width
  box=$(ui bounds "$1") || return 1
  read -r x1 y1 x2 y2 <<< "$box"
  height=$((y2 - y1))
  width=$((height * 4))
  echo "$((x2 - width)),$((y1 - 6)),$((width + 6)),$((height + 12))"
}

wait_for() { # <text> [seconds]
  local waited=0 limit=${2:-30}
  while [ "$waited" -lt "$limit" ]; do
    ui has "$1" > /dev/null 2>&1 && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# Records a clip while a step runs: screenrecord stops when the step ends.
record() { # <name> <seconds> <command...>
  local name=$1 seconds=$2
  shift 2
  adb shell rm -f "/sdcard/$name.mp4" > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$seconds" --bit-rate 12000000 \
    "/sdcard/$name.mp4" > /dev/null 2>&1 &
  local recorder=$!
  sleep 0.8
  "$@" || note "$name: the step reported a miss"
  wait "$recorder" 2> /dev/null || true
  sleep 0.5
  adb pull "/sdcard/$name.mp4" "$out/$name.mp4" > /dev/null 2>&1 || true
  if [ -s "$out/$name.mp4" ]; then
    note "clip $name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "clip $name: none"
  fi
}

dismiss_system_dialogs() {
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
  for label in Allow 允许 OK; do
    if point=$(ui tap "$label" 2> /dev/null); then
      # shellcheck disable=SC2086
      tap_point "$point" 1
    fi
  done
}

component="$app/${TAILDECK_ACTIVITY:-top.bangwu.taildeck_ui.MainActivity}"

launch() { # <query> <marker>
  local query=$1 marker=$2 attempt
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 2
  adb logcat -c > /dev/null 2>&1 || true
  adb shell "am start -W -a android.intent.action.VIEW -d 'taildeck://preview/?$query' -n $component" \
    > /dev/null 2>&1 || true
  sleep 4
  dismiss_system_dialogs
  for attempt in $(seq 1 25); do
    if gate_in_front "$app" && ui has "$marker" > /dev/null 2>&1; then
      sleep 1
      return 0
    fi
    sleep 2
  done
  shot "$marker-launch-fail"
  fail "no '$marker' after 50 s"
}

# ---- one Taildeck build ---------------------------------------------------

# <tag> <language|ssh>: opens the select, closes it by tapping the page, and
# checks that the menu listed its choices.
language_open() { tap_point "$language_point" 0.2; sleep $((slow + 1)); }
language_close() { tap_point "$((W / 8)) $((SH / 10))" 0.2; sleep $((slow + 1)); }
ssh_open() { tap_point "$auth_point" 0.2; sleep $((slow + 1)); }
ssh_close() { tap_point "$((W / 2)) $((SH / 10))" 0.2; sleep $((slow + 1)); }

record_language() { # <tag>
  local tag=$1
  launch "preview=1&tab=3&lang=en&splash=0&slow=$slow" Language
  shot "$tag-settings"
  language_point=$(value_point Language) || fail "$tag: no bounds for Language"
  box=$(value_box Language) || fail "$tag: no box for Language"
  record "$tag-language-open" 12 language_open
  shot "$tag-language-open"
  ui has 中文 > /dev/null 2>&1 || fail "$tag: the language menu did not open"
  record "$tag-language-close" 14 language_close
  shot "$tag-language-closed"
  ui has 中文 > /dev/null 2>&1 && note "$tag: the language menu stayed open"
  note "$tag language: box $box"
}

record_ssh() { # <tag>
  local tag=$1
  launch "preview=1&tab=0&lang=en&sheet=ssh&splash=0&slow=$slow" Authentication
  shot "$tag-ssh-sheet"
  auth_point=$(value_point Authentication) || fail "$tag: no bounds for Authentication"
  ssh_box=$(value_box Authentication) || fail "$tag: no box for Authentication"
  record "$tag-ssh-open" 12 ssh_open
  shot "$tag-ssh-open"
  ui has Password > /dev/null 2>&1 || fail "$tag: the authentication menu did not open"
  record "$tag-ssh-close" 14 ssh_close
  shot "$tag-ssh-closed"
  note "$tag ssh: box $ssh_box"
}

# The same gestures on one build, then the choice it picks.
taildeck() { # <tag> <apk>
  local tag=$1 apk=$2
  adb uninstall "$app" > /dev/null 2>&1 || true
  adb install -g "$apk" > "$out/install-$tag.txt" 2>&1 ||
    fail "adb install of $tag failed, see install-$tag.txt"
  record_language "$tag"
  # A value picked from the same menu: the language the UI then speaks.
  language_open
  if point=$(ui tap 中文 2> /dev/null); then
    tap_point "$point" 0.4
    sleep $((slow + 1))
    shot "$tag-language-zh"
    if ui has 设置 > /dev/null 2>&1; then
      note "$tag language: 中文 picked, the list is in Chinese"
    else
      note "$tag language: 中文 picked, the list did not switch"
    fi
  else
    note "$tag language: no 中文 entry"
  fi
  record_ssh "$tag"
  back_key
  sleep 1
  local alive
  alive=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
  [ -n "$alive" ] || fail "$tag died during the recording"
  local exceptions
  exceptions=$(adb logcat -d 2> /dev/null |
    grep -hE -e 'EXCEPTION CAUGHT BY' -e 'Another exception was thrown' | head -n 3 || true)
  [ -z "$exceptions" ] || fail "$tag logged a Flutter exception: $exceptions"
  note "$tag: alive, no Flutter exception"
}

geometry
taildeck after "$after_apk"
taildeck before "$before_apk"

# ---- FlClash --------------------------------------------------------------

disclaimer_statement="The Software itself does not provide any proxy server, node, subscription, or network access service, and has no partnership, agency, or guarantee relationship with any provider of such services."

type_pieces() { # <text>
  local text=$1 offset=0 piece
  while [ "$offset" -lt "${#text}" ]; do
    piece=${text:offset:24}
    adb shell input text "$(printf '%s' "$piece" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
    offset=$((offset + 24))
    sleep 0.25
  done
}

accept_flclash_disclaimer() {
  local point
  point=$(ui tap Agree 2> /dev/null) || point=$(ui tap 同意 2> /dev/null) || return 0
  tap_point "$point" 2
  if ui has Confirm > /dev/null 2>&1; then
    if point=$(ui edit 0 2> /dev/null); then
      tap_point "$point" 1
      type_pieces "$disclaimer_statement"
      sleep 2
    elif point=$(ui tap "I have read" 2> /dev/null); then
      tap_point "$point" 1
    fi
    point=$(ui tap Confirm 2> /dev/null) && tap_point "$point" 3
  fi
}

launch_flclash() {
  adb shell am force-stop "$flclash" > /dev/null 2>&1 || true
  sleep 2
  adb shell monkey -p "$flclash" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
  sleep 10
  dismiss_system_dialogs
  accept_flclash_disclaimer
  sleep 3
  if wait_for Tools 20 || wait_for 工具 5; then return 0; fi
  adb shell input tap "$((W * 7 / 8))" "$((SH - 160))" > /dev/null 2>&1 || true
  sleep 2
  ui has Language > /dev/null 2>&1 || ui has Theme > /dev/null 2>&1
}

open_flclash_tools() {
  if tap_label Tools || tap_label 工具; then
    sleep 2
    return 0
  fi
  adb shell input tap "$((W * 7 / 8))" "$((SH - 160))" > /dev/null 2>&1 || true
  sleep 2
  ui has Language > /dev/null 2>&1 || ui has Theme > /dev/null 2>&1
}

adb install -g "$flclash_apk" > "$out/install-flclash.txt" 2>&1 ||
  note "FlClash install failed, see install-flclash.txt"
if launch_flclash && open_flclash_tools; then
  shot flclash-tools
  if wait_for Language 15; then
    flclash_point=$(value_point Language) || flclash_point=""
    if [ -n "$flclash_point" ]; then
      flclash_open() { tap_point "$flclash_point" 3; }
      flclash_close() { tap_point "$((W / 8)) $((SH / 10))" 3; }
      record flclash-language-open 12 flclash_open
      shot flclash-language-open
      ui has English > /dev/null 2>&1 || note "FlClash: no English entry in its menu"
      record flclash-language-close 14 flclash_close
      shot flclash-language-closed
      note "FlClash: language select recorded"
    else
      note "FlClash: no bounds for Language"
    fi
  else
    note "FlClash: no language row in the dump"
  fi
else
  note "FlClash never showed its Tools tab; only Taildeck is recorded"
fi

# ---- every frame of each close -------------------------------------------

check_close() { # <clip> <out sub-dir> <box> <name> <expected: pass|fail>
  local clip=$1 dir=$2 box=$3 name=$4 expected=$5 status=0
  if [ ! -s "$clip" ]; then
    note "$name: no clip to cut"
    return 0
  fi
  python3 "$here/select_frames.py" "$clip" "$out/$dir" "$box" --name "$name" \
    --tail "$tail" --limit "$limit" >> "$summary" 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    note "$name: tail settled (expected $expected)"
  else
    note "$name: tail still shows a block (expected $expected)"
  fi
  if [ "$expected" = pass ] && [ "$status" -ne 0 ]; then
    fail "$name: the close left a block in its last $tail frames"
  fi
}

check_close "$out/after-language-close.mp4" language-after "$box" language-after pass
check_close "$out/before-language-close.mp4" language-before "$box" language-before fail
check_close "$out/after-ssh-close.mp4" ssh-after "$ssh_box" ssh-after pass
check_close "$out/before-ssh-close.mp4" ssh-before "$ssh_box" ssh-before fail
check_close "$out/flclash-language-close.mp4" flclash-language "$box" flclash-language any

# ---- side by side --------------------------------------------------------

scene_time() { # <clip>: seconds of its first frame that differs much
  local time
  time=$(ffmpeg -loglevel error -i "$1" -vf "select='gt(scene,0.06)',metadata=print:file=-" \
    -f null - 2> /dev/null | sed -n 's/.*pts_time:\([0-9.]*\).*/\1/p' | head -n 1)
  awk -v t="${time:-0}" 'BEGIN { printf "%.2f", (t > 0.35 ? t - 0.35 : 0) }'
}

side_by_side() { # <name> <left clip> <right clip> [seconds]
  local name=$1 left=$2 right=$3 length=${4:-6}
  [ -s "$out/$left.mp4" ] && [ -s "$out/$right.mp4" ] || { note "no pair for $name"; return 0; }
  local left_start right_start
  left_start=$(scene_time "$out/$left.mp4")
  right_start=$(scene_time "$out/$right.mp4")
  note "$name: left from ${left_start}s, right from ${right_start}s"
  ffmpeg -loglevel error -y -ss "$left_start" -t "$length" -i "$out/$left.mp4" \
    -ss "$right_start" -t "$length" -i "$out/$right.mp4" \
    -filter_complex "[0:v]scale=540:-2,setsar=1[l];[1:v]scale=540:-2,setsar=1,tpad=stop_mode=clone:stop_duration=$length[r];[l][r]hstack=inputs=2,drawtext=text=Taildeck:x=14:y=14:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5,drawtext=text=FlClash:x=554:y=14:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5" \
    -an "$out/$name.mp4" 2> /dev/null || true
  [ -s "$out/$name.mp4" ] && note "side by side $name: $out/$name.mp4" || note "side by side $name: none"
}

side_by_side select-closed-vs-flclash after-language-close flclash-language-close 5
side_by_side select-open-vs-flclash after-language-open flclash-language-open 4

# Still pairs for the pull request.
pair() { # <name> <left png> <right png> <left label> <right label>
  local name=$1 left=$2 right=$3 llabel=$4 rlabel=$5
  if [ -s "$out/$left.png" ] && [ -s "$out/$right.png" ]; then
    convert "$out/$left.png" -resize 540x "$out/left-$name.png" 2> /dev/null || true
    convert "$out/$right.png" -resize 540x "$out/right-$name.png" 2> /dev/null || true
    convert "$out/left-$name.png" "$out/right-$name.png" +append \
      -gravity northwest -annotate +14+14 "$llabel" -annotate +554+14 "$rlabel" \
      "$out/select-$name.png" 2> /dev/null || true
    [ -s "$out/select-$name.png" ] && note "still pair: select-$name.png"
  fi
}

pair language-open after-language-open flclash-language-open Taildeck FlClash
pair language-close after-language-closed flclash-language-closed Taildeck FlClash
pair language-before-after before-language-closed after-language-closed before after
pair ssh-before-after before-ssh-closed after-ssh-closed before after

note "ok: selects recorded, every close cut, before/after and FlClash compared"
