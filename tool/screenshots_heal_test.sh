#!/usr/bin/env bash
# Offline check of the stills step's self-heal: runs tool/screenshots_android.sh
# against a fake adb whose device dies during a screenshot. Cases: a clean run
# (warm-up logged, 1.5 s between shots); a loss the restart survives (the shot
# is taken again on the restarted device, so every shot is still taken); a loss
# no restart survives (three restarts, then "stopped answering adb", which
# stills_outcome reads as lost).
# Usage: tool/screenshots_heal_test.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin=$work/bin
sdk=$work/sdk
mkdir -p "$bin" "$sdk/emulator"

# The device: `dead` is set while it is gone, `shots` counts screenshots,
# `lose` lists the screenshots during which the device dies, `sleeps` logs the
# pauses the script asked for. FAKE_RESTART_OK=0 makes restarts fail.
cat > "$bin/adb" <<'FAKE'
#!/usr/bin/env bash
dev=$FAKE_DEV
case "$1" in
  devices)
    echo "List of devices attached"
    [ -e "$dev/dead" ] || printf 'emulator-5554\tdevice\n'
    exit 0 ;;
  wait-for-device)
    if [ -e "$dev/dead" ]; then
      [ "${FAKE_RESTART_OK:-1}" = 1 ] || exit 1
      rm -f "$dev/dead"
      echo restarted >> "$dev/restarts"
    fi
    exit 0 ;;
  kill-server|install|logcat) exit 0 ;;
esac
[ -e "$dev/dead" ] && { echo "error: device offline" >&2; exit 1; }
case "$1" in
  exec-out)
    n=$(( $(cat "$dev/shots") + 1 ))
    echo "$n" > "$dev/shots"
    case " $(cat "$dev/lose") " in
      *" $n "*) touch "$dev/dead"; exit 1 ;;
    esac
    printf 'PNG'; exit 0 ;;
  pull)
    src=$dev/sdcard/${2#/sdcard/}
    [ -e "$src" ] || exit 1
    cp "$src" "$3"; exit 0 ;;
  shell)
    shift
    case "$1" in
      uiautomator) cp "$FAKE_UI" "$dev/sdcard/ui.xml"; exit 0 ;;
      getprop)
        case "$2" in
          sys.boot_completed) echo 1 ;;
          ro.build.version.release) echo 14 ;;
        esac
        exit 0 ;;
      dumpsys)
        case "$2" in
          window) echo "  mCurrentFocus=Window{1 u0 com.google.android.apps.nexuslauncher/.Launcher}" ;;
          *) echo "  mResumedActivity: ActivityRecord{1 u0 top.bangwu.taildeck/.MainActivity}" ;;
        esac
        exit 0 ;;
      wm) echo "Physical density: 420"; exit 0 ;;
      *) exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac
FAKE
cat > "$bin/sleep" <<'FAKE'
#!/usr/bin/env bash
echo "$1" >> "$FAKE_DEV/sleeps"
exit 0
FAKE
for stub in pkill sudo; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/$stub"
done
printf '#!/usr/bin/env bash\nexit 0\n' > "$sdk/emulator/emulator"
chmod +x "$bin"/* "$sdk/emulator/emulator"

ui="$work/ui.xml"
cat > "$ui" <<'XML'
<hierarchy rotation="0"><node class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
<node text="Tailnet &amp; device" bounds="[0,400][1080,500]" clickable="true"/>
<node text="Theme" bounds="[0,520][1080,620]" clickable="true"/>
<node text="Light" bounds="[0,640][1080,740]" clickable="true"/>
</node></hierarchy>
XML

run_case() { # <name> <shot numbers that lose the device> <restart ok: 1|0>
  local case_dir=$work/$1 dev=$work/$1-device
  mkdir -p "$case_dir/out" "$dev/sdcard"
  echo 0 > "$dev/shots"
  echo "$2" > "$dev/lose"
  : > "$dev/sleeps"
  : > "$case_dir/app.apk"
  (
    cd "$repo"
    PATH="$bin:$PATH" FAKE_DEV="$dev" FAKE_UI="$ui" FAKE_RESTART_OK="$3" \
      ANDROID_SDK_ROOT="$sdk" bash tool/screenshots_android.sh "$case_dir/app.apk" \
      top.bangwu.taildeck "$case_dir/out" > "$case_dir/run.log" 2>&1
  ) || echo "exit $?" >> "$case_dir/run.log"
}

failures=0
check() { # <case> <what> <grep -E pattern> <file>
  if grep -qE "$3" "$4" 2> /dev/null; then
    echo "ok   $1: $2"
  else
    echo "FAIL $1: $2 (no match for: $3)"
    failures=$((failures + 1))
  fi
}
count_shots() { grep -cE '^[[:space:]]*shot [a-z]' "$repo/tool/screenshots_android.sh"; }

run_case clean "" 1
run_case restart-ok "3" 1
run_case restart-fails "3" 0

total=$(grep -cE ': [0-9]+ bytes$' "$work/clean/out/summary.txt")
check clean "warm-up logged before the first shot" '^warm-up: boot_completed=1' "$work/clean/out/summary.txt"
check clean "launcher focus logged" '^warm-up: launcher focus after' "$work/clean/out/summary.txt"
check clean "every shot taken" "^settings-grouped: [0-9]+ bytes" "$work/clean/out/summary.txt"
if grep -q 'self-heal' "$work/clean/out/summary.txt"; then echo "FAIL clean: unexpected self-heal"; failures=$((failures + 1)); fi
if [ "$(grep -c '^1.5$' "$work/clean-device/sleeps")" -lt $((total - 1)) ]; then
  echo "FAIL clean: fewer than $((total - 1)) pauses of 1.5 s between $total shots"; failures=$((failures + 1))
else
  echo "ok   clean: 1.5 s pause between shots ($total shots)"
fi

check restart-ok "device loss named with its shot and the time" '^self-heal: the device was lost before shot ' "$work/restart-ok/out/summary.txt"
check restart-ok "restart booted" '^self-heal: restart 1 booted in ' "$work/restart-ok/out/summary.txt"
check restart-ok "the shot that met the loss is taken again" 'before shot settings-theme again' "$work/restart-ok/out/summary.txt"
check restart-ok "photos taken before the loss are kept" '^settings-grouped: [0-9]+ bytes' "$work/restart-ok/out/summary.txt"
if [ "$(grep -cE ': [0-9]+ bytes$' "$work/restart-ok/out/summary.txt")" -ne "$total" ]; then
  echo "FAIL restart-ok: $(grep -cE ': [0-9]+ bytes$' "$work/restart-ok/out/summary.txt") shots, want $total"; failures=$((failures + 1))
else
  echo "ok   restart-ok: all $total shots taken"
fi
if grep -q 'no screenshot' "$work/restart-ok/out/summary.txt"; then echo "FAIL restart-ok: a shot is missing"; failures=$((failures + 1)); else echo "ok   restart-ok: no shot missing"; fi
check restart-ok "host memory and kernel log kept for the restart" '' "$work/restart-ok/out/host-lost-stills-1.txt"
if grep -q 'stopped answering adb' "$work/restart-ok/out/summary.txt"; then echo "FAIL restart-ok: must not read as lost"; failures=$((failures + 1)); else echo "ok   restart-ok: not counted as lost"; fi

check restart-fails "three restarts tried" 'restart 3 of 3' "$work/restart-fails/out/summary.txt"
check restart-fails "gives up as stopped answering adb" 'stopped answering adb: 3 restarts did not bring it back' "$work/restart-fails/out/summary.txt"
check restart-fails "later shots say the emulator is gone" 'no screenshot \(the emulator is gone\)' "$work/restart-fails/out/summary.txt"

grep -q 'timeout 15 adb exec-out screencap' "$repo/tool/screenshots_android.sh" && echo "ok   per-shot timeout is 15 s" || { echo "FAIL per-shot timeout"; failures=$((failures + 1)); }

if [ "$failures" -eq 0 ]; then echo "all checks passed"; else echo "$failures check(s) failed"; exit 1; fi
