#!/usr/bin/env bash
# Cold-start routing gate: sign in once against a test control plane, then cold
# start 20 times and prove the login page never appears on the way to the shell.
#
# Every cold start records its first 3 s. A frame is a login frame when its
# downscaled signature matches a reference shot of this build's login page,
# captured before signing in; the run first proves that reference separates
# (a second login shot matches it, the shell does not), so a silent mismatch
# cannot pass. Semantics back the frames up: each start must show a dock label
# and must never show a login-only label.
#
# Usage: tool/coldstart_gate.sh <apk> [application-id] [out-dir]
#        CONTROL_URL=http://10.0.2.2:8080 AUTH_KEY=tskey-test
#        RUNS=20 (the report asks for 20)
set -euo pipefail

apk=${1:?usage: tool/coldstart_gate.sh <apk> [application-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-smoke-coldstart}
control_url=${CONTROL_URL:?CONTROL_URL is required (test control plane)}
auth_key=${AUTH_KEY:?AUTH_KEY is required (test control plane)}
runs=${RUNS:-20}
mkdir -p "$out/frames"
summary="$out/summary.txt"
: > "$summary"
here=$(cd "$(dirname "$0")" && pwd)

note() { echo "$*" | tee -a "$summary"; }
fail() {
  echo "FAIL: $*" | tee -a "$summary"
  adb logcat -d > "$out/logcat-fail.txt" 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui-fail.xml" > /dev/null 2>&1 || true
  exit 1
}

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
adb shell svc power stayon true > /dev/null 2>&1 || true

# A fresh install: the sign-in below is the only login record the run has.
adb uninstall "$app" > /dev/null 2>&1 || true
adb install -g "$apk" > "$out/install.txt" 2>&1 || fail "adb install failed, see install.txt"
activity=$(adb shell cmd package resolve-activity --brief "$app" 2>/dev/null | tail -n 1 | tr -d '\r')
[ -n "$activity" ] || fail "no launcher activity for $app"

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

tapxy() { # 'x y'
  # shellcheck disable=SC2086
  adb shell input swipe $1 $1 120 > /dev/null 2>&1 || true
  sleep 0.5
}

type_text() { adb shell input text "$(printf '%s' "$1" | sed 's/ /%s/g')" > /dev/null 2>&1 || true; }

hide_keyboard() {
  adb shell dumpsys input_method 2> /dev/null | grep -q 'mInputShown=true' || return 0
  adb shell input keyevent 4 > /dev/null 2>&1 || true
  sleep 0.8
}

find_or_scroll() { # <text> [tries]
  local point tries=${2:-3} W SH
  point=$(ui tap "$1") && { echo "$point"; return 0; }
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  while [ "$tries" -gt 0 ]; do
    adb shell input swipe "$((W / 2))" "$((SH * 3 / 4))" "$((W / 2))" "$((SH / 2))" 300 > /dev/null 2>&1 || true
    sleep 0.8
    point=$(ui tap "$1") && { echo "$point"; return 0; }
    tries=$((tries - 1))
  done
  return 1
}

wait_for() { # <marker> <seconds>
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    ui has "$1" > /dev/null 2>&1 && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

field_count() { ui edits 2> /dev/null | wc -l | tr -d ' '; }

tap_until_fields() { # <text> <expected field count>
  local point x y dx
  point=$(find_or_scroll "$1") || fail "no node for '$1'"
  tapxy "$point"
  sleep 1
  [ "$(field_count)" -ge "$2" ] && return 0
  x=${point% *}
  y=${point#* }
  for dx in -300 -150 150 300; do
    tapxy "$((x + dx)) $y"
    sleep 1
    [ "$(field_count)" -ge "$2" ] && return 0
  done
  fail "'$1' did not open $2 text field(s), $(field_count) on screen"
}

fill_edit() { # <index> <value>
  local point
  point=$(ui edit "$1") || fail "no text field $1"
  tapxy "$point"
  type_text "$2"
  hide_keyboard
}

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }

# Normalized RMSE of two frames, 0 for identical: downscale both to the same
# small grayscale grid so the status bar clock cannot decide a match.
rmse() { # <a> <b>
  compare -metric RMSE "$1" "$2" null: 2>&1 \
    | sed -n 's/.*(\([0-9.]*\)).*/\1/p' || true
}

signature() { # <png> <dest>: one comparison grid
  rm -f "$2"
  convert "$1" -colorspace Gray -resize 72x128! "$2" 2> /dev/null || true
}

# Login markers: the signed-out choices and the "starting the node" caption the
# report saw under them. None may be on screen at any cold start.
check_no_login() { # <label>
  local needle attempt
  for attempt in 1 2 3; do
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    [ -s "$out/ui.xml" ] && break
    sleep 0.4
  done
  [ -s "$out/ui.xml" ] || return 0
  for needle in "Use an auth key" "Continue in browser" "Sign in to your control server" \
    "Waiting for approval"; do
    if python3 "$here/ui.py" "$out/ui.xml" has "$needle" 2> /dev/null; then
      fail "$1: the login page shows \"$needle\""
    fi
  done
}

launch_plain() { # starts the launcher activity exactly as a user does
  adb logcat -c > /dev/null 2>&1 || true
  adb shell am start -W -n "$activity" > "$out/launch.txt" 2>&1 || return 1
  grep -q "Activity: $app/" "$out/launch.txt" || return 1
}

# ---- sign in ----

launch_plain || fail "am start failed, see launch.txt"
wait_for "Use an auth key" 40 || fail "no login page after the fresh install; see ui.xml"
shot login-ref
sleep 1
shot login-ref2

tap_until_fields "Control server" 1
fill_edit 0 "$control_url"
tap_until_fields "Use an auth key" 2
fill_edit 0 "$auth_key"
point=$(find_or_scroll "Connect") || fail "no Connect button on the login page"
tapxy "$point"
wait_for "Services" 90 || { shot signin-failed; fail "sign-in did not reach the shell"; }
sleep 4
shot shell-ref
note "signed in to $control_url"

# A still of the launch screen: it is dark and sparse like the login page, so
# a splash frame must not be the closest one to the login reference.
adb shell am force-stop "$app" > /dev/null 2>&1 || true
sleep 1
adb shell "am start -W -a android.intent.action.VIEW \
  -d 'taildeck://preview/?splash=hold&lang=en' -n $activity" \
  > "$out/launch-splash.txt" 2>&1 || fail "could not open the splash preview"
sleep 2
shot splash-ref
adb shell am force-stop "$app" > /dev/null 2>&1 || true

# The references must separate on this emulator, in this theme, or a frame
# would be classified by noise instead of layout.
signature "$out/login-ref.png" "$out/login.sig.png"
signature "$out/login-ref2.png" "$out/login2.sig.png"
signature "$out/shell-ref.png" "$out/shell.sig.png"
signature "$out/splash-ref.png" "$out/splash.sig.png"
ref_same=$(rmse "$out/login.sig.png" "$out/login2.sig.png")
ref_shell=$(rmse "$out/login.sig.png" "$out/shell.sig.png")
ref_splash=$(rmse "$out/login.sig.png" "$out/splash.sig.png")
ref_pair=$(rmse "$out/splash.sig.png" "$out/shell.sig.png")
note "references: login/log in $ref_same, login/shell $ref_shell, login/splash $ref_splash, splash/shell $ref_pair"
if [ -z "$ref_same" ] || [ -z "$ref_shell" ] || [ -z "$ref_splash" ] || [ -z "$ref_pair" ]; then
  fail "could not measure the reference frames (imagemagick compare)"
fi
if ! awk -v same="$ref_same" -v shell="$ref_shell" -v splash="$ref_splash" -v pair="$ref_pair" \
  'BEGIN { exit !(same < 0.02 && shell > 0.03 && splash > 0.03 && pair > 0.03) }'; then
  fail "the reference frames do not separate ($ref_same/$ref_shell/$ref_splash/$ref_pair)"
fi

# ---- 20 cold starts ----

for run in $(seq 1 "$runs"); do
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  sleep 1
  adb shell input keyevent KEYCODE_HOME > /dev/null 2>&1 || true
  sleep 1
  adb shell rm -f /sdcard/cold.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit 30 --bit-rate 8000000 /sdcard/cold.mp4 \
    > /dev/null 2>&1 &
  recorder=$!
  sleep 1.0
  launch_plain || fail "run $run: am start failed, see launch.txt"

  # Semantics: neither login label may ever be on screen; the dock must be.
  sleep 0.9
  check_no_login "run $run (0.9 s)"
  sleep 0.9
  check_no_login "run $run (1.8 s)"
  wait_for "Services" 25 || fail "run $run: the shell never showed its dock"
  adb pull /sdcard/ui.xml "$out/ui-$run.xml" > /dev/null 2>&1 || true

  # Three more seconds, so the clip always carries the first 3 s after the
  # app painted even on a slow cold start. Stopping the recorder ourselves and
  # waiting for it keeps the file whole before the pull.
  sleep 3
  adb shell pkill -INT screenrecord > /dev/null 2>&1 || true
  wait "$recorder" 2> /dev/null || true
  sleep 1
  adb pull /sdcard/cold.mp4 "$out/run-$run.mp4" > /dev/null 2>&1 \
    || fail "run $run: could not pull the recording"

  # The clip starts on the launcher; the app's first screen is the first frame
  # that is close to one of the references.
  rm -f "$out"/frames/*.png
  ffmpeg -loglevel error -y -i "$out/run-$run.mp4" -vf fps=10 \
    "$out/frames/%04d.png" 2> /dev/null || fail "run $run: ffmpeg could not read the clip"
  [ -n "$(ls "$out/frames"/*.png 2> /dev/null | head -1)" ] \
    || fail "run $run: the recording has no frames"

  low=2
  low_frame=
  start_at=
  saw_splash=0
  started=0
  seen=0
  for frame in $(ls "$out/frames"/*.png | sort); do
    signature "$frame" "$out/frame.sig.png"
    d_login=$(rmse "$out/login.sig.png" "$out/frame.sig.png")
    d_splash=$(rmse "$out/splash.sig.png" "$out/frame.sig.png")
    d_shell=$(rmse "$out/shell.sig.png" "$out/frame.sig.png")
    [ -n "$d_login" ] && [ -n "$d_splash" ] && [ -n "$d_shell" ] || continue
    if [ "$started" -eq 0 ]; then
      if awk -v login="$d_login" -v splash="$d_splash" -v shell="$d_shell" \
        'BEGIN { exit !(login < 0.05 || splash < 0.05 || shell < 0.05) }'; then
        started=1
        start_at=$(( (10#$(basename "$frame" .png) - 1) / 10 ))
      else
        continue
      fi
    fi
    seen=$((seen + 1))
    if awk -v a="$d_splash" 'BEGIN { exit !(a < 0.05) }'; then saw_splash=1; fi
    # Near the login still and nearer to it than to either other screen: only
    # then is this the login page. The launcher and a black screen stay far
    # from all three and can never trip this.
    if awk -v login="$d_login" -v splash="$d_splash" -v shell="$d_shell" \
      'BEGIN { exit !(login < 0.05 && login < splash && login < shell) }'; then
      cp "$out/run-$run.mp4" "$out/failed-$run.mp4" || true
      cp "$frame" "$out/failed-$run.png"
      fail "run $run: frame $frame is the login page (login $d_login, splash $d_splash, shell $d_shell)"
    fi
    if awk -v a="$d_login" -v b="$low" 'BEGIN { exit !(a < b) }'; then
      low=$d_login
      low_frame=$frame
    fi
  done
  [ "$seen" -ge 25 ] || fail "run $run: $seen frames after the first screen, less than 3 s"
  [ "$saw_splash" -eq 1 ] || fail "run $run: the app's launch screen never appeared in the recording"
  [ -n "$low_frame" ] || fail "run $run: no frame could be compared"
  cp "$low_frame" "$out/worst-$run.png"
  if awk -v a="$low" -v b="${closest:-2}" 'BEGIN { exit !(a < b) }'; then closest=$low; fi
  note "run $run: closest frame to the login page RMSE $low"
  # Keep the first clip and a contact sheet as evidence; the rest go away so
  # the artifact stays small.
  if [ "$run" -eq 1 ]; then
    cp "$out/run-$run.mp4" "$out/coldstart-full.mp4" || true
    ffmpeg -loglevel error -y -ss "${start_at:-0}" -i "$out/run-$run.mp4" -t 3 \
      -vf 'fps=4,scale=270:-2,tile=4x3' "$out/coldstart-sheet.png" 2> /dev/null || true
  fi
  rm -f "$out/run-$run.mp4"
done

# Leave the device clean: the gates after this one install their own APK.
adb uninstall "$app" > /dev/null 2>&1 || true

echo "ok: $runs cold starts with a saved login never painted the login page (closest login RMSE ${closest:-?})" \
  | tee -a "$summary"
