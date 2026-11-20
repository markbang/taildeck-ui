#!/usr/bin/env bash
# Offline check of the gate's lost-emulator path: runs the stills gate through
# tool/android_gate_all.sh against a fake adb whose device dies during the
# recorded flow, while the gate still exits 0. Three cases: a clean run, a loss
# the retry survives, and a loss the retry repeats. Takes about 6 minutes (each
# app launch waits 9 s). Usage: tool/gate_lost_test.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin=$work/bin
sdk=$work/sdk
mkdir -p "$bin" "$sdk/emulator"

# The device: `boot` counts boots, `lose` lists the boots whose recorded flow
# kills it, `dead` is set while it is gone, `sdcard/` is its storage.
cat > "$bin/adb" <<'FAKE'
#!/usr/bin/env bash
dev=$FAKE_DEV
[ -e "$dev/dead" ] && { echo "error: device offline" >&2; exit 1; }
case "$1" in
  devices)
    [ -e "$dev/dead" ] || printf 'List of devices attached\nemulator-5554\tdevice\n'
    exit 0 ;;
  shell)
    shift
    case "$1" in
      screenrecord)
        case " $(cat "$dev/lose") " in
          *" $(cat "$dev/boot") "*) touch "$dev/dead"; exit 0 ;;
        esac
        cp "$dev/template.mp4" "$dev/sdcard/rec.mp4"
        exit 0 ;;
      uiautomator) cp "$FAKE_UI" "$dev/sdcard/ui.xml"; exit 0 ;;
      rm) rm -f "$dev/sdcard/$(basename "$3")"; exit 0 ;;
      getprop)
        case "$2" in
          sys.boot_completed) echo 1 ;;
          ro.build.version.release) echo 14 ;;
        esac
        exit 0 ;;
      dumpsys)
        case "$2" in
          window) echo "  mCurrentFocus=Window{1 u0 top.bangwu.taildeck/.MainActivity}" ;;
          *) echo "mResumedActivity: ActivityRecord{1 u0 top.bangwu.taildeck/.MainActivity}" ;;
        esac
        exit 0 ;;
      pidof) exit 1 ;;
      *) exit 0 ;;
    esac ;;
  exec-out) printf 'PNG'; exit 0 ;;
  pull)
    src=$dev/sdcard/${2#/sdcard/}
    [ -e "$src" ] || exit 1
    cp "$src" "$3"; exit 0 ;;
  *) exit 0 ;;
esac
FAKE
cat > "$bin/pgrep" <<'FAKE'
#!/usr/bin/env bash
[ -e "$FAKE_DEV/dead" ] && exit 1
exit 0
FAKE
cat > "$bin/pkill" <<'FAKE'
#!/usr/bin/env bash
rm -f "$FAKE_DEV/dead"
exit 0
FAKE
cat > "$bin/sleep" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
cat > "$bin/sudo" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
cat > "$sdk/emulator/emulator" <<'FAKE'
#!/usr/bin/env bash
n=$(cat "$FAKE_DEV/boot")
echo $((n + 1)) > "$FAKE_DEV/boot"
exit 0
FAKE
chmod +x "$bin"/* "$sdk/emulator/emulator"

# The labels the gate taps and reads: a settings page with its rows.
ui="$work/ui.xml"
cat > "$ui" <<'XML'
<hierarchy rotation="0"><node class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
<node text="Tailnet &amp; device" bounds="[0,400][1080,500]" clickable="true"/>
<node text="Theme" bounds="[0,520][1080,620]" clickable="true"/>
<node text="Light" bounds="[0,640][1080,740]" clickable="true"/>
<node text="Language" bounds="[0,760][1080,860]" clickable="true"/>
<node text="English" bounds="[700,760][1080,860]"/>
<node text="Logs" bounds="[0,880][1080,980]" clickable="true"/>
<node text="controlplane.example" bounds="[0,1000][1080,1100]"/>
</node></hierarchy>
XML

ffmpeg -loglevel error -f lavfi -i color=c=gray:s=320x640:d=2 -y "$work/template.mp4"

# run_case <name> <boots that lose the device during the recorded flow>
run_case() {
  local case_dir=$work/$1 dev=$work/$1-device lose=$2
  mkdir -p "$case_dir" "$dev/sdcard"
  ln -s "$repo/tool" "$case_dir/tool"
  cp "$work/template.mp4" "$dev/template.mp4"
  echo 1 > "$dev/boot"
  echo "$lose" > "$dev/lose"
  : > "$case_dir/app.apk"
  local status=0
  (
    cd "$case_dir"
    PATH="$bin:$PATH" FAKE_DEV="$dev" FAKE_UI="$ui" ANDROID_SDK_ROOT="$sdk" \
      APK="$case_dir/app.apk" GATES=stills SHIP=true GATE_OUT=gates \
      bash tool/android_gate_all.sh > "$case_dir/run.log" 2>&1
  ) || status=$?
  echo "$status" > "$case_dir/exit"
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

run_case clean ""
run_case lost-retried "1"
run_case lost-again "1 2"

for c in clean lost-retried lost-again; do
  check "$c" "exit 0 in ship mode" '^0$' "$work/$c/exit"
done
check clean "clean run says ok 13/13" '^stills: ok 13/13$' "$work/clean/gates/ship-stills.txt"
check clean "no LOST line" '^ok stills: [0-9]+s$' "$work/clean/gates/gate-results.txt"
if grep -q LOST "$work/clean/gates/gate-results.txt"; then
  echo "FAIL clean: unexpected LOST line"
  failures=$((failures + 1))
fi

check lost-retried "loss detected on exit 0 and retried" '^LOST stills: the emulator died under the gate' "$work/lost-retried/gates/gate-results.txt"
check lost-retried "lost attempt kept beside the retry" 'settings-flow: no recording' "$work/lost-retried/smoke-shots-lost/summary.txt"
check lost-retried "ship-stills says ok after the retry" '^stills: ok 13/13 \(retried after a lost emulator\)$' "$work/lost-retried/gates/ship-stills.txt"
check lost-retried "gate-results says ok" '^ok stills: [0-9]+s$' "$work/lost-retried/gates/gate-results.txt"

check lost-again "retry that lost the device too is reported" '^LOST stills: the retry lost the emulator too$' "$work/lost-again/gates/gate-results.txt"
check lost-again "ship-stills says lost emulator" '^stills: lost emulator 12/13$' "$work/lost-again/gates/ship-stills.txt"
if grep -q '^ok stills' "$work/lost-again/gates/gate-results.txt"; then
  echo "FAIL lost-again: gate-results must not say ok"
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed; logs in $work"
  trap - EXIT
  exit 1
fi
echo "all checks passed"
