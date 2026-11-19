#!/usr/bin/env bash
# Waits shared by the emulator gates. Sourced by each gate, not run.
#
# The startup route holds a launch screen over the shell until the saved login
# is read (up to 1.5 s). A gate that starts tapping as soon as a dock label
# exists can hit that screen, so every gate waits for the app to be in front,
# the route to be the shell, and the launch screen's fade to finish.

# The app is ours, alive and in front. mCurrentFocus alone is not enough: it
# reads null for a while after am start on this emulator, while the window and
# the resumed activity are already ours.
gate_in_front() { # <app>
  local app=$1 pid focus
  pid=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
  [ -n "$pid" ] || return 1
  focus=$(adb shell dumpsys window 2>/dev/null \
    | grep -E 'mCurrentFocus|mFocusedApp' | tr -d '\r' || true)
  case "$focus" in
    *"$app/"*) return 0 ;;
  esac
  adb shell dumpsys activity activities 2>/dev/null \
    | grep -q "topResumedActivity.*$app/" && return 0
  return 1
}

# The emulator's software compositor can stall a cold start's first frames for
# 6 s, past the 5 s input timeout on the window's focus. That ANR is raised 5-6
# s after the first frame, and with error dialogs hidden the system kills the
# app some seconds later, in the middle of whatever the gate does next. A
# launch is only used once that window has passed without an ANR; after one,
# this waits for the kill and fails so the caller starts the app again.
gate_survived_focus() { # <app> <SECONDS when the first frame was shown> <summary>
  local app=$1 shown=$2 summary=$3
  while [ $((SECONDS - shown)) -lt "${GATE_FOCUS_WINDOW:-9}" ]; do sleep 1; done
  adb logcat -d 2>/dev/null | grep -q "ANR in .*$app" || return 0
  adb logcat -d 2>/dev/null | grep -m1 "ANR in .*$app" | cut -c1-200 >> "$summary"
  for _ in $(seq 1 20); do
    adb shell pidof "$app" > /dev/null 2>&1 || break
    sleep 1
  done
  return 1
}

# One dump, parsed with tool/ui.py: `gate_ui <out> <tools> has Services`.
# A dump taken while Flutter is still publishing its tree can come back
# without labels, so a miss is retried before it is believed.
gate_ui() { # <out-dir> <tool-dir> <ui.py args...>
  local out=$1 tools=$2 attempt
  shift 2
  for attempt in 1 2 3; do
    # A failed pull must not leave the previous step's tree in place.
    rm -f "$out/ui.xml"
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
    adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
    python3 "$tools/ui.py" "$out/ui.xml" "$@" 2> /dev/null && return 0
    sleep 0.5
  done
  return 1
}

# The shell is painted and the launch screen has faded. The cheap signals come
# first: a uiautomator dump during a cold start is what ANRs the app on a loaded
# emulator, so the tree is read only after the route is the shell.
wait_home() { # <app> <out-dir> <tool-dir> [marker] [seconds] [routes]
  # ${4-Services}, not ${4:-Services}: an empty marker means "no dock label
  # expected" (a launch that opens a sheet covers it).
  local app=$1 out=$2 tools=$3 marker=${4-Services} limit=${5:-45} routes=${6:-shell} waited=0
  local attempt
  while [ "$waited" -lt "$limit" ]; do
    if gate_in_front "$app" &&
      adb logcat -d 2>/dev/null | grep -qE "taildeck route: ($routes)"; then
      # The launch screen fades over 340 ms after the route is decided; the
      # tree can then take a few more seconds to carry the dock's labels.
      sleep 0.8
      for attempt in $(seq 1 10); do
        gate_in_front "$app" || return 1
        if [ -z "$marker" ] || gate_ui "$out" "$tools" has "$marker" > /dev/null 2>&1; then
          return 0
        fi
        sleep 2
      done
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
