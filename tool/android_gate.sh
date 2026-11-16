#!/usr/bin/env bash
# Waits shared by the emulator gates. Sourced by tabs/agents/back, not run.
#
# The startup route holds a launch screen over the shell until the saved login
# is read (up to 1.5 s). A gate that starts tapping as soon as a dock label
# exists can hit that screen, so every gate waits for the app to be in front,
# the route to be the shell, and the launch screen's fade to finish.

# The app is ours, alive and the focused window.
gate_in_front() { # <app>
  local app=$1 pid focus
  pid=$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)
  [ -n "$pid" ] || return 1
  focus=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r' || true)
  case "$focus" in
    *"$app/"*) return 0 ;;
  esac
  return 1
}

# One dump, parsed with tool/ui.py: `gate_ui <out> <tools> has Services`.
# A dump taken while Flutter is still publishing its tree can come back
# without labels, so a miss is retried before it is believed.
gate_ui() { # <out-dir> <tool-dir> <ui.py args...>
  local out=$1 tools=$2 attempt
  shift 2
  for attempt in 1 2 3; do
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
wait_home() { # <app> <out-dir> <tool-dir> [marker] [seconds]
  local app=$1 out=$2 tools=$3 marker=${4:-Services} limit=${5:-45} waited=0
  local attempt
  while [ "$waited" -lt "$limit" ]; do
    if gate_in_front "$app" &&
      adb logcat -d 2>/dev/null | grep -q 'taildeck route: shell'; then
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
