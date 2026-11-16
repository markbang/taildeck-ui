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

The goldens are tagged `golden` and excluded from CI: a runner's rasterizer is
not pixel-stable enough to gate a PR, and `tool/golden.sh` is the same check on
the machine that made them.

## Adding a golden

Put the test in `test/golden/`, wrap the app in `goldenApp` and the view in
`usePhone` (414 × 896, status bar 47, gesture area 34), then assert the
geometry that must hold and `matchesGoldenFile('goldens/<name>.png')`. Keep
animations out of the sampled area, or make them deterministic: a golden of a
pulsing skeleton fails for the phase of the pulse, not for the UI. A still
frame from `SkeletonPill` starts on the wall clock, so capture above it.
