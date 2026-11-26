[English](TESTING.md) · [中文](TESTING.zh-CN.md)

# Testing the UI

Most UI work is judged here, on this machine, in seconds. The Android
emulator is the slow last step and is only needed where a real device is the
only honest answer.

## The local loop, in order

1. **Widget tests** — `flutter test --exclude-tags golden`. Logic, layout
   numbers, accessibility labels and gestures, without pixels.
2. **Goldens** — `tool/golden.sh`. Pumps the real widgets and pages frame by
   frame (16 ms steps) and compares the frames under `test/golden/goldens/`.
   Covers the settings select opening and closing, the first-level page's top,
   the title handover mid-scroll, a subpage's compact bar, and the Agents tab
   going from a stale failure to connecting. No network, no emulator: the suite
   runs in about 8 s warm (an emulator pass of the same flows took 13–28 min).
   After an intended UI change, `tool/golden.sh --update`; then read
   `git diff --stat test/golden/goldens` and open the changed images before
   committing. A diff you did not mean is a regression.
3. **Linux desktop** — `flutter run -d linux`. Eyeball motion, scrolling and
   spacing at a phone-sized window; the same Dart UI as the phone.
4. **CI emulator or the phone** — only for what the host cannot run: the Go
   tsnet node, SSH, the soft keyboard and IME, notifications, and the platform
   launch path. `android-smoke` covers cold start, back, Ping and a crash scan
   before a release.

Native-loaded widget tests: point `TAILDECK_BRIDGE` and `TAILDECK_TERM` at the
libs from `tool/build_native.sh linux` and `tool/build_term.sh linux`, then run
`flutter test` again. The two native-terminal tests run, and the terminal page
draws with the real emulator. CI does not run this mode: its `linux` job builds
both libs but runs no widget tests after them. Run it locally before changing
the terminal page or the SSH flow.

## What runs in CI

A pull request runs only `ci` (analyze, widget tests, web, Linux, Android debug
APK) and `android-smoke` (one emulator, the PR set of gates). Every
`*-record`, `select-metrics` and `icon-compare` workflow runs only when
dispatched.

"Before" runs that are meant to show a bug, and evidence runs, dispatch
`android-smoke` with `record=true`:

```sh
gh workflow run android-smoke --ref <branch> -f record=true -f gates="termtap"
```

Every selected gate still runs and writes the same results, summary and
artifacts, but a failed gate is a warning and the job stays green, so it does
not page anyone. Pull requests and the release call cannot set it.

A cold start on the emulator can ANR while its software compositor stalls:
every window freezes, not only the app's. The back gate retries a failed cold
start once; a second ANR fails it unless `tool/compositor_stall.py` finds, for
both ANRs, another process frozen for 3 s or more across the app's and the app
absent from the ANR report's CPU top. That earns a third start, twice per run
at most, written to the summary with both processes' numbers; a third stall
fails as "emulator compositor stall". When the ANR report has no CPU list from
before the ANR, the gate's own samples of the app's main thread stand in: under
10% CPU through the focus wait and no wait on a file, or on a futex outside
hwui, EGL or binder in the ANR trace; unreadable samples count as app-only. Each launch's `Displayed` time and the app's own
`taildeck first frame` / `taildeck frames` lines go to `smoke-back/timing.txt`.

The goldens are tagged `golden` and excluded from CI: a runner's rasterizer is
not pixel-stable enough to gate a PR, and `tool/golden.sh` is the same check on
the machine that made them.

## Release gate

`platform-release` calls `android-smoke` in ship mode on the signed x86_64 APK
it just built. To run the same gates on an older build, dispatch with
`full-gate=false`:

```sh
gh workflow run android-smoke --ref main -f full-gate=false \
  -f apk-artifact=android -f apk-run-id=<platform-release run> \
  -f gates="cold-start splash agents stills"
```

| Gate | In ship mode |
| --- | --- |
| `cold-start`, `splash`, `agents` | block the release |
| `stills` | record-only: runs, keeps its stills, never fails the job |

Stills are record-only because the CI emulator has a known qemu freeze on the
settings pages that has nothing to do with the app: a Settings row tap freezes
the guest within ~0.7 s, the last logcat line is from `EGL_emulation`, qemu
exits ~60 s later with no OOM or segfault, and the gate results end with
`emulator: the qemu process is gone`. The regression the stills used to catch,
a page that never stops redrawing, is guarded by `test/theme_open_test.dart`
in the required `ci` job.

Each ship run writes one line, `stills: ok 13/13`, `stills: lost emulator
4/13` or `stills: failed 9/13`, to the job summary, the `ship-stills`
artifact, the release notes and the release asset `ship-stills.txt`. The
release job fails when neither the previous published release nor this run
has `stills: ok`: two releases in a row without visual evidence is a gate to
fix, not one to ship past. A release from before this line ran stills as a
blocking gate, so it counts as green.

A gate that ends with the emulator gone (qemu dead or adb silent), whether it
exits non-zero or 0 (a flow step that finds adb silent records "no recording"
and returns), is run once more on a fresh boot: the results keep `LOST <gate>: the emulator died under
the gate`, a warning names it, the lost attempt stays in `<out>-lost/`, and
only the retry's outcome counts. Stills keep their ship-mode record-only
level through the retry, and write `stills: ok 13/13 (retried after a lost
emulator)` or, when the retry fails too, `stills: lost emulator …`.

Inside the stills run, the device is checked before each shot. A lost device is
restarted (at most three times, each boot at most 120 s), the screen is opened
again by replaying the input since its launch, and the shot is taken again; the
log names the shot, the time and each boot's duration. Only when the restarts
run out does the run end as `stills: lost emulator`. `tool/screenshots_heal_test.sh`
and `tool/gate_lost_test.sh` check this offline.

When a blocking gate still fails after that and the only error is
`emulator: the qemu process is gone`, rerun the failed jobs once (`gh run
rerun <run-id> --failed`) and say so in the release report. Any other red
stops the release.

## Background keep-alive on a device

Not in CI: the emulator gate cannot sit in the background for minutes. On a
phone or an emulator with a signed-in node:

```bash
adb shell input keyevent HOME
sleep 600
adb shell dumpsys activity services top.bangwu.taildeck | grep -A3 TailnetService
adb shell dumpsys activity processes | grep -A2 top.bangwu.taildeck
```

Pass: `TailnetService` is listed with `isForeground=true` and
`foregroundServiceType=0x40000000` (specialUse), the process is still there,
and after reopening the app the node list shows peers without a reconnect.
`adb shell dumpsys deviceidle force-idle` before the sleep adds Doze.

## Adding a golden

Put the test in `test/golden/`, wrap the app in `goldenApp` and the view in
`usePhone` (414 × 896, status bar 47, gesture area 34), then assert the
geometry that must hold and `matchesGoldenFile('goldens/<name>.png')`. Keep
animations out of the sampled area, or make them deterministic: a golden of a
pulsing skeleton fails for the phase of the pulse, not for the UI. A still
frame from `SkeletonPill` starts on the wall clock, so capture above it.
