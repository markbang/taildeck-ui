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

# The process is gone, so the next am start reads its deep link from a fresh
# launch. A force-stop of a live app with a pending ANR can leave it running,
# and `am start` then delivers the intent without the app re-reading it.
gate_stop() { # <app>
  local app=$1 waited=0
  adb shell am force-stop "$app" > /dev/null 2>&1 || true
  while [ "$waited" -lt 10 ]; do
    [ -z "$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)" ] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# Clears a system "app isn't responding" dialog between attempts.
gate_dismiss() {
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
}

# One dump, parsed with tool/ui.py: `gate_ui <out> <tools> has Services`.
gate_ui() { # <out-dir> <tool-dir> <ui.py args...>
  local out=$1 tools=$2
  shift 2
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
  python3 "$tools/ui.py" "$out/ui.xml" "$@" 2> /dev/null
}

# The shell is painted and the launch screen has faded. The shell only exists
# once the route is decided, so a dock label (or focus, for a caller that opens
# a sheet) plus the fade is enough; the route log is not required, so a build
# from before that log still passes.
wait_home() { # <app> <out-dir> <tool-dir> [marker] [seconds]
  local app=$1 out=$2 tools=$3 marker=${4:-Services} limit=${5:-45} waited=0
  local attempt
  while [ "$waited" -lt "$limit" ]; do
    # A startup ANR kills the process; retrying the launch is the caller's job.
    [ -n "$(adb shell pidof "$app" 2>/dev/null | tr -d '\r' || true)" ] || return 1
    if gate_in_front "$app"; then
      if [ -n "$marker" ]; then
        gate_ui "$out" "$tools" has "$marker" > /dev/null 2>&1 || {
          sleep 1
          waited=$((waited + 1))
          continue
        }
      fi
      # The launch screen fades over 340 ms after the route is decided.
      sleep 0.8
      gate_in_front "$app" && return 0
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
