#!/usr/bin/env bash
# Checks and records the terminal sheet's input on the Android emulator against
# a real SSH shell: a tap on the grid leaves the IME down and only reaches a
# program that tracks the mouse as a left press and release (SGR 1006); the
# toolbar's keyboard button shows and hides the IME; typing and Compose reach
# the shell. The gate fails the run; vim and htop are recorded, not failed.
#
# The shell comes from the runner's test tailnet: a control plane plus a peer
# node whose sshd serves bash on a pty (tool/motion/peer).
# Usage: tool/termtap_record.sh <flutter-apk> [app-id] [out-dir]
set -euo pipefail

apk=${1:?usage: tool/termtap_record.sh <flutter-apk> [app-id] [out-dir]}
app=${2:-top.bangwu.taildeck}
out=${3:-termtap}
control_url=${CONTROL_URL:-}
auth_key=${AUTH_KEY:-tskey-test}
peer=${PEER:-motionpeer}
mkdir -p "$out"
summary="$out/summary.txt"
: > "$summary"
failures=0
gate_ran=0
note() { echo "$*" | tee -a "$summary"; }
fail() { note "GATE FAIL: $*"; failures=$((failures + 1)); }

adb wait-for-device
adb shell settings put global hide_error_dialogs 1 > /dev/null 2>&1 || true
adb shell settings put global stay_on_while_plugged_in 3 > /dev/null 2>&1 || true
for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$scale" 1 > /dev/null 2>&1 || true
done
adb shell svc power stayon true > /dev/null 2>&1 || true
sleep 15
adb shell input keyevent 82 > /dev/null 2>&1 || true
adb shell wm dismiss-keyguard > /dev/null 2>&1 || true
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true
# The emulator reports a physical keyboard, which hides the IME by default.
adb shell settings put secure show_ime_with_hard_keyboard 1 > /dev/null 2>&1 || true

W= SH=
screen_size() {
  read -r W SH <<< "$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tr -d '\r')"
  W=${W:-1080}; SH=${SH:-2400}
}

dump() {
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$out/ui.xml" > /dev/null 2>&1 || true
}

ui() { # <tap|has|text|bounds|edit> <needle>
  local attempt
  for attempt in 1 2 3; do
    dump
    if python3 tool/ui.py "$out/ui.xml" "$@" 2> /dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

tap_xy() {
  # shellcheck disable=SC2086
  adb shell input tap $1 > /dev/null 2>&1 || true
  sleep 0.8
}

ime_state() {
  adb shell dumpsys input_method 2> /dev/null | grep -o 'mInputShown=[a-z]*' | head -1 || true
}

focused_window() {
  adb shell dumpsys window 2> /dev/null \
    | grep -m1 -E 'mCurrentFocus|mFocusedApp' | tr -d '\r' || true
}

hide_ime() {
  # The capsule knows the state; tapping its button is the same path a user
  # takes and works even when dumpsys reports a stale flag.
  if ui has 'Hide keyboard' > /dev/null 2>&1; then
    tap_label 'Hide keyboard' > /dev/null 2>&1 || true
    sleep 1.5
    return 0
  fi
  [ "$(ime_state)" = "mInputShown=true" ] || return 0
  adb shell input keyevent KEYCODE_BACK > /dev/null 2>&1 || true
  sleep 2
}

open_keyboard() {
  ui has 'Hide keyboard' > /dev/null 2>&1 && return 0
  tap_label 'Show keyboard'
}

type_text() {
  adb shell input text "$(printf '%s' "$1" | sed 's/ /%s/g')" > /dev/null 2>&1 || true
  sleep 0.4
}

shot() { adb exec-out screencap -p > "$out/$1.png" 2> /dev/null || rm -f "$out/$1.png"; }

record() { # <name> <seconds> <function>
  local name=$1 seconds=$2 action=$3
  adb shell pkill -f screenrecord > /dev/null 2>&1 || true
  sleep 0.6
  adb shell rm -f /sdcard/rec.mp4 > /dev/null 2>&1 || true
  adb shell screenrecord --time-limit "$((seconds + 2))" --bit-rate 6000000 \
    /sdcard/rec.mp4 > /dev/null 2>&1 &
  local recorder=$!
  sleep 0.4
  "$action" || true
  wait "$recorder" 2> /dev/null || true
  sleep 0.5
  adb pull /sdcard/rec.mp4 "$out/$name-raw.mp4" > /dev/null 2>&1 || true
  if [ -s "$out/$name-raw.mp4" ]; then
    ffmpeg -loglevel error -y -ss 0.2 -i "$out/$name-raw.mp4" -t "$seconds" \
      -an -vf 'scale=360:-2' "$out/$name.mp4" || true
    [ -s "$out/$name.mp4" ] && note "$name: $(stat -c%s "$out/$name.mp4") bytes"
  else
    note "$name: no recording"
  fi
}

# ---- grid geometry from the a11y tree ------------------------------------
grid_box() { # prints "x1 y1 x2 y2"
  ui bounds 'Terminal output'
}

# A live session's header carries no cols×rows, so the grid is addressed by
# position: fractions of its a11y bounds. The readOnly semantics node covers
# the whole canvas, padding included.
tap_grid() { # <fx> <fy>, both 0..1
  local fx=$1 fy=$2 box gx1 gy1 gx2 gy2 x y
  box=$(grid_box) || { note "no grid bounds"; return 1; }
  read -r gx1 gy1 gx2 gy2 <<< "$box"
  x=$(awk -v f="$fx" -v a="$gx1" -v b="$gx2" 'BEGIN { printf "%d", a + f * (b - a) }')
  y=$(awk -v f="$fy" -v a="$gy1" -v b="$gy2" 'BEGIN { printf "%d", a + f * (b - a) }')
  tap_xy "$x $y"
}

tap_label() {
  local point
  point=$(ui tap "$1") || return 1
  tap_xy "$point"
}

scroll_down() {
  screen_size
  adb shell input swipe "$((W / 2))" "$((SH * 3 / 4))" "$((W / 2))" "$((SH / 2))" 300 > /dev/null 2>&1 || true
  sleep 0.8
}

find_or_scroll() {
  local point tries=${2:-4}
  point=$(ui tap "$1") && { echo "$point"; return 0; }
  while [ "$tries" -gt 0 ]; do
    scroll_down
    point=$(ui tap "$1") && { echo "$point"; return 0; }
    tries=$((tries - 1))
  done
  return 1
}

fill_edit() { # <index> <value>
  local point
  point=$(ui edit "$1") || { note "no text field $1"; return 1; }
  tap_xy "$point"
  type_text "$2"
  hide_ime
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

launch() { # [url]
  local url=${1:-} attempt resumed
  for attempt in 1 2 3; do
    adb shell am force-stop "$app" > /dev/null 2>&1 || true
    sleep 1
    if [ -n "$url" ]; then
      adb shell "am start -W -a android.intent.action.VIEW -d '$url' '$app'" > /dev/null 2>&1 || true
    else
      adb shell monkey -p "$app" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 || true
    fi
    sleep 5
    resumed=$(adb shell dumpsys activity activities 2> /dev/null \
      | grep -m1 -E 'mResumedActivity|topResumedActivity' || true)
    case "$resumed" in
      *"$app"*) return 0 ;;
    esac
    note "launch attempt $attempt: ${resumed:-no resumed activity}"
    sleep 3
  done
  note "launch failed"
  return 1
}

sign_in() {
  [ -n "$control_url" ] || { note "no control server: cannot reach a shell"; return 1; }
  # A cold start can sit on the splash for a while; wait for the first screen
  # before reading its fields.
  local waited=0
  while [ "$waited" -lt 45 ]; do
    if ui has "Nodes" > /dev/null 2>&1; then
      note "sign-in: already signed in"
      return 0
    fi
    ui has "Control server" > /dev/null 2>&1 && break
    sleep 1
    waited=$((waited + 1))
  done
  ui has "Control server" > /dev/null 2>&1 || { note "sign-in: no login screen"; return 1; }
  local point
  point=$(find_or_scroll "Control server") || { note "sign-in: no control-server row"; return 1; }
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$control_url" || return 1
  point=$(find_or_scroll "Use an auth key") || return 1
  tap_xy "$point"
  sleep 1
  fill_edit 0 "$auth_key" || return 1
  point=$(find_or_scroll "Connect") || return 1
  tap_xy "$point"
  wait_for "Nodes" 45 || { note "sign-in: still on the login screen"; return 1; }
  note "sign-in: node up, control $control_url"
}

open_session() {
  local node=$1 point
  point=$(find_or_scroll "$node") || { note "$node: not in the node list"; return 1; }
  tap_xy "$point"
  sleep 1.5
  point=$(find_or_scroll "SSH") || { note "$node: no SSH action"; return 1; }
  tap_xy "$point"
  sleep 1.5
  point=$(find_or_scroll "Connect") || { note "$node: no Connect button"; return 1; }
  tap_xy "$point"
  wait_for "Terminal output" 30 || { note "$node: the terminal did not open"; return 1; }
  note "$node: SSH session up"
}

send_command() { # <text> [settle seconds], through the keyboard button
  if ! open_keyboard; then
    note "no Show keyboard button"
    return 1
  fi
  sleep 1.5
  type_text "$1"
  adb shell input keyevent 66 > /dev/null 2>&1 || true
  sleep "${2:-2}"
  hide_ime
}

# ---- the tap and keyboard gate ------------------------------------------
# 1. a tap on the grid does not show the IME and does not focus an input.
# 2. the toolbar's keyboard button shows the IME.
# 3. typing then reaches the shell.
# 4. the button hides the IME again, and a tap after it keeps it down.
# 5. the d-pad, Ctrl, the arrows and Compose all work from the toolbar.
gate() {
  gate_ran=1
  hide_ime
  [ "$(ime_state)" = "mInputShown=true" ] && { fail "IME did not close"; return 0; }

  tap_grid 0.3 0.35 || fail "no grid point to tap"
  sleep 4
  [ "$(ime_state)" = "mInputShown=true" ] && fail "a tap on the grid showed the IME"
  shot tap-no-keyboard
  adb shell dumpsys input_method > "$out/input-method-tap.txt" 2> /dev/null || true

  if ui has 'Show keyboard' > /dev/null 2>&1; then
    tap_label 'Show keyboard' || fail "the keyboard button did not take a tap"
  else
    cp "$out/ui.xml" "$out/ui-no-keyboard-button.xml" 2> /dev/null || true
    fail "no Show keyboard button on the toolbar"
  fi
  sleep 3
  [ "$(ime_state)" = "mInputShown=true" ] || fail "the keyboard button did not show the IME"
  shot tap-keyboard

  # A trailing x is deleted before Enter, so the run also proves that the
  # IME's backspace reaches the shell as KeyCode.DEL.
  rm -f /tmp/tap-focus-ok
  type_text "touch /tmp/tap-focus-okx"
  adb shell input keyevent 67 > /dev/null 2>&1 || true
  adb shell input keyevent 66 > /dev/null 2>&1 || true
  sleep 3
  if [ -f /tmp/tap-focus-ok ]; then
    note "gate: typing and Backspace after the keyboard button reached the shell"
  else
    fail "typing and Backspace after the keyboard button did not reach the shell"
  fi

  if ui has 'Hide keyboard' > /dev/null 2>&1; then
    tap_label 'Hide keyboard' || fail "the keyboard button did not take a tap"
  else
    fail "no Hide keyboard button while the IME is up"
  fi
  sleep 2.5
  [ "$(ime_state)" = "mInputShown=true" ] && fail "the keyboard button did not hide the IME"

  tap_grid 0.3 0.35
  sleep 3
  [ "$(ime_state)" = "mInputShown=true" ] && fail "a tap after the keyboard button showed the IME again"

  # The d-pad opens the arrows and the custom key pages.
  if ui has 'Arrow keys and more' > /dev/null 2>&1; then
    tap_label 'Arrow keys and more' || fail "the d-pad did not take a tap"
    sleep 1.5
    shot tap-arrows
    tap_label 'Control' || fail "no Control key in the capsule"
    sleep 0.6
    tap_label 'Left arrow' || fail "no arrow key in the expanded panel"
    sleep 0.6
  else
    fail "no d-pad button on the toolbar"
  fi

  # Compose: a multiline sheet whose Send writes the text and Enter.
  rm -f /tmp/tap-compose-ok
  if ui has 'Compose' > /dev/null 2>&1; then
    tap_label 'Compose' || fail "Compose did not take a tap"
    sleep 2
    if point=$(ui edit 0); then
      read -r x y <<< "$point"
      tap_xy "$x $y"
      type_text "touch /tmp/tap-compose-ok"
      if ui has 'Send' > /dev/null 2>&1; then
        tap_label 'Send' || fail "Send did not take a tap"
      else
        fail "no Send button in Compose"
      fi
      sleep 3
      if [ -f /tmp/tap-compose-ok ]; then
        note "gate: Compose wrote its text and Enter to the shell"
      else
        fail "Compose did not run on the shell"
      fi
    else
      fail "no Compose text field"
    fi
  else
    fail "no Compose button on the toolbar"
  fi

  # Close the panel again: it floats over the bottom of the grid, and the vim
  # and htop taps below must land on cells, not on its keys.
  if ui has 'Left arrow' > /dev/null 2>&1; then
    tap_label 'Arrow keys and more' || true
    sleep 1
  fi

  if [ "$failures" -eq 0 ]; then
    note "gate: tap leaves the IME down, the keyboard button and Compose work"
  else
    note "gate: $failures failure(s) so far"
  fi
}

# ---- mouse reporting -----------------------------------------------------
mouse_probe() { # <fx> <fy> [ctrl]
  local fx=$1 fy=$2
  rm -f /tmp/tap-mouse-ready /tmp/tap-mouse.log
  send_command "python3 /tmp/mouseprobe.py" 1
  local waited=0
  while [ ! -f /tmp/tap-mouse-ready ] && [ "$waited" -lt 15 ]; do sleep 1; waited=$((waited + 1)); done
  [ -f /tmp/tap-mouse-ready ] || { fail "the mouse probe did not start"; return 0; }
  [ "${3:-}" = ctrl ] && { tap_label 'Control' || fail "no Control key"; sleep 0.5; }
  tap_grid "$fx" "$fy"
  waited=0
  while [ ! -s /tmp/tap-mouse.log ] && [ "$waited" -lt 12 ]; do sleep 1; waited=$((waited + 1)); done
  if [ -s /tmp/tap-mouse.log ]; then
    note "mouse: $(tr '\n' ' ' < /tmp/tap-mouse.log)"
  else
    fail "no mouse report reached the program"
  fi
}

check_mouse() { # <log> [ctrl]
  local log=${1:-/tmp/tap-mouse.log} status=${2:-0} code=0
  [ -s "$log" ] || return 0
  if [ "$status" = ctrl ]; then code=16; fi
  if grep -q "<$code;[0-9]*;[0-9]*M" "$log" && grep -q "<$code;[0-9]*;[0-9]*m" "$log"; then
    if [ "$code" -eq 16 ]; then
      note "mouse: Ctrl+left press and release carried the modifier"
    else
      note "mouse: plain tap sent a left press and release"
    fi
  else
    fail "the tap did not send a left press and release (button code $code)"
  fi
}

# The press and the release must name the same cell, and it must be inside
# the grid the program drew (the emulator reports cells from 1).
check_cell() { # <log>
  local log=$1 press release
  [ -s "$log" ] || return 0
  press=$(head -1 "$log" | sed -n 's/.*<[0-9]*;\([0-9]*\);\([0-9]*\)[Mm].*/\1 \2/p')
  release=$(tail -1 "$log" | sed -n 's/.*<[0-9]*;\([0-9]*\);\([0-9]*\)[Mm].*/\1 \2/p')
  if [ -n "$press" ] && [ "$press" = "$release" ]; then
    note "mouse: press and release name cell $press"
  else
    fail "press '${press:-none}' and release '${release:-none}' disagree"
  fi
}

# ---- vim and htop --------------------------------------------------------
collapse_panel() {
  if ui has 'Left arrow' > /dev/null 2>&1; then
    tap_label 'Arrow keys and more' || true
    sleep 1
  fi
}

vim_step() {
  # A script on the runner keeps the quotes out of `adb shell input text`,
  # which would otherwise hand vim `-c set` and a file called `mouse=a`.
  # Vim writes the cursor line on every move, so the tap can be asserted.
  cat > /tmp/tapvim.sh <<'VIM'
#!/bin/sh
printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve\n' > /tmp/tapvim.txt
rm -f /tmp/tapvim-cursor
exec vim -u NONE -c 'set mouse=a' -c 'set laststatus=2' -c 'set ruler' \
  -c 'autocmd CursorMoved * call writefile([line(".")], "/tmp/tapvim-cursor")' \
  /tmp/tapvim.txt
VIM
  send_command "sh /tmp/tapvim.sh" 5
  hide_ime
  collapse_panel
  # Fractions of the grid's semantics box: the upper third is always cells,
  # never the floating toolbar.
  tap_grid 0.35 0.22
  sleep 2
  shot tap-vim-before
  local before after
  before=$(cat /tmp/tapvim-cursor 2> /dev/null || echo '')
  tap_grid 0.55 0.12
  sleep 3
  shot tap-vim-after
  after=$(cat /tmp/tapvim-cursor 2> /dev/null || echo '')
  note "vim: cursor line $before -> $after after the tap; stills tap-vim-*.png"
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    note "vim: the tap moved the cursor"
  else
    fail "vim: the tap did not move the cursor (line ${before:-none} -> ${after:-none})"
  fi
  adb shell input keyevent KEYCODE_ESCAPE > /dev/null 2>&1 || true
  # Quit through the page's key handler instead of the IME: `input text`
  # reaches the focused terminal even with the soft keyboard down.
  type_text ':q!'
  adb shell input keyevent 66 > /dev/null 2>&1 || true
  sleep 2
  adb shell input keyevent KEYCODE_ESCAPE > /dev/null 2>&1 || true
  rm -f /tmp/tap-vim-quit
  send_command "touch /tmp/tap-vim-quit" 2
  if [ ! -f /tmp/tap-vim-quit ]; then
    # A swallowed Enter: try once more before failing the run.
    adb shell input keyevent KEYCODE_ESCAPE > /dev/null 2>&1 || true
    type_text ':q!'
    adb shell input keyevent 66 > /dev/null 2>&1 || true
    sleep 2
    send_command "touch /tmp/tap-vim-quit" 2
  fi
  [ -f /tmp/tap-vim-quit ] || fail "vim did not quit before htop"
}

quit_htop() { send_command q 1; }

htop_step() {
  send_command "htop" 4
  hide_ime
  collapse_panel
  tap_grid 0.5 0.3
  sleep 2
  shot tap-htop-before
  tap_grid 0.5 0.45
  sleep 2
  shot tap-htop-after
  note "htop: tapped one process row, then another; stills tap-htop-*.png"
  quit_htop
  rm -f /tmp/tap-htop-quit
  send_command "touch /tmp/tap-htop-quit" 2
  [ -f /tmp/tap-htop-quit ] || fail "htop did not quit"
}

# ---- setup ---------------------------------------------------------------
adb install -r -g "$apk" > "$out/install.txt" 2>&1 || { note "install failed, see install.txt"; exit 1; }
launch || { note "cannot launch the app"; exit 1; }
sign_in || true
open_session "$peer" || true

if ! ui has 'Terminal output' > /dev/null 2>&1; then
  note "no terminal session; the tap gate cannot run"
  echo "termtap: failed (no terminal)" | tee -a "$summary"
  exit 1
fi

record tap-focus 30 gate

# The probe runs on the runner, where the peer's bash runs too.
cat > /tmp/mouseprobe.py <<'PY'
import os, sys, termios, tty, time

fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
reports = []
try:
    tty.setraw(fd)
    os.write(sys.stdout.fileno(), b'\x1b[?1000h\x1b[?1006h')
    open('/tmp/tap-mouse-ready', 'w').close()
    deadline = time.time() + 40
    buf = b''
    while time.time() < deadline and len(reports) < 2:
        b = os.read(fd, 1)
        buf += b
        if b in (b'M', b'm'):
            reports.append(buf.decode('latin1'))
            buf = b''
finally:
    os.write(sys.stdout.fileno(), b'\x1b[?1006l\x1b[?1000l')
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
open('/tmp/tap-mouse.log', 'w').write('\n'.join(reports))
PY

mouse_probe_plain() { mouse_probe 0.3 0.3; }
record tap-mouse 13 mouse_probe_plain
check_mouse /tmp/tap-mouse.log
check_cell /tmp/tap-mouse.log

mouse_probe_ctrl() { mouse_probe 0.6 0.5 ctrl; }
record tap-mouse-ctrl 13 mouse_probe_ctrl
check_mouse /tmp/tap-mouse.log ctrl
check_cell /tmp/tap-mouse.log

record tap-vim 18 vim_step
record tap-htop 16 htop_step

# A gate that never ran is not a gate: the call above must reach it.
[ "$gate_ran" -eq 1 ] || fail "the tap gate did not run"

if [ "$failures" -gt 0 ]; then
  note "termtap: $failures gate failure(s)"
  exit 1
fi
note "termtap: tap focus, keyboard, blank taps, mouse reports, vim and htop recorded"
