[English](ARCHITECTURE.md) · [中文](ARCHITECTURE.zh-CN.md) · [Parity](PARITY.md)

# Architecture

> **Status: implemented on Android and Linux; Web is a preview.** The bridge and terminal FFI, the Android host
> hooks and the unsigned desktop/iOS builds have landed (see Milestones). Windows, macOS and iOS have the native
> libraries wired but have not been run. `lib/src/data.dart` remains as the Web preview's data source.

## Goal

One Flutter client for Android, iOS, Windows, Linux and macOS. Web stays a debug and preview target.
The UI, theme and navigation in `lib/` stay shared; only a thin native boundary differs per platform.

## Native boundary

Reuse the existing Go module `bridge/` from [markbang/taildeck](https://github.com/markbang/taildeck) unchanged
where possible. It already contains the tsnet engine, a loopback gateway at `127.0.0.1:18680`, the SSH client and
herdr agent operations. It is vendored as `native/bridge` with a new `cmd/cshared` entry point.

One call path on every platform: the same Go module built with `-buildmode=c-shared` and loaded through `dart:ffi`.

| Platform | Packaging | Call path |
|---|---|---|
| Android | `libtaildeck_bridge.so` in `jniLibs`, built with the NDK clang and 16 KB-page aligned | `dart:ffi` → C ABI → Go |
| iOS | `-buildmode=c-archive` static library linked into the Runner | `dart:ffi` → C ABI → Go (the Dart loader is still missing) |
| Windows / Linux / macOS | `-buildmode=c-shared` DLL / `.so` / dylib shipped next to the app | `dart:ffi` → C ABI → Go |

This replaces the gomobile AAR for the Flutter client. The legacy Kotlin app in
[markbang/taildeck](https://github.com/markbang/taildeck) keeps its own `gomobile bind` AAR / XCFramework build;
the two share the Go source, not the bindings.

The C ABI is the stable contract; JSON in and JSON out for start, stop, status, logs, ping, port probe and gateway
port (`td_start` … `td_free` in `native/README.md`), plus SSH session calls, key and host-key calls, herdr calls, and
a single event callback for state and log pushes. No Go types or pointers cross the boundary, so a Go or Flutter
upgrade does not break the other side.

### What runs today

- `native/bridge` builds for Linux, Android, Windows and macOS (`tool/build_native.sh`), exposing node start/stop,
  logout, status, logs, ping, port probe, SSH, SSH keys, host keys and herdr.
- `native/term` wraps libghostty-vt behind the `td_term_*` C ABI (`tool/build_term.sh`); Flutter paints snapshots
  and forwards encoded input.
- `lib/src/native/` loads both libraries on Android and Linux, with `dart:ffi`; `backend.dart`, `herdr.dart` and
  `services.dart` are the Dart side. Web uses the stubs and `data.dart`.
- CI builds the Android debug APK, the Linux bundle (run on Xvfb for a screenshot) and the Web preview on every PR;
  Windows, macOS and iOS packages build unsigned on a tag or manual run.

### Android platform hooks

Android 11+ blocks the netlink calls behind Go's `net.Interfaces`, and apps have no `resolv.conf`, so the node
starts with `"platform": "host"` on Android. A Kotlin helper (`android/.../PlatformBridge.kt`) supplies
interfaces, the default interface and DNS lookups from `ConnectivityManager`, `NetworkInterface` and `InetAddress`;
the JNI shim `native/bridge/cmd/cshared/platform_jni.c` hands them to `td_set_platform_cb` and forwards default
network changes to `td_network_changed`. Every other platform keeps the Go stdlib adapter.

## Terminal

Reuse `libghostty-vt` behind a small plain C ABI shim, consumed through `dart:ffi`:

`td_term_create` · `td_term_destroy` · `td_term_write` · `td_term_resize` · `td_term_snapshot` ·
`td_term_encode_key` · `td_term_encode_mouse` · `td_term_encode_focus` · `td_term_take_clipboard` ·
`td_term_encode_paste` · `td_term_select` · `td_term_selection_text` · `td_term_title`, declared in
`native/term/term_ffi.h`.

The emulator stays native; Flutter only renders the snapshot and forwards input. Do not reimplement a terminal
emulator in Dart.

## Platforms

| Platform | Node | Terminal | Gateway | Limits |
|---|---|---|---|---|
| Android | in-app tsnet via the c-shared `.so` | `libghostty-vt` `.so`, NDK CMake | `127.0.0.1:18680` loopback | no foreground service yet, so the node stops with the process; no VPN slot; minSdk 26; arm64-v8a, armeabi-v7a and x86_64 native libs; release-signed APKs and AAB built in CI, not device-tested |
| iOS | c-archive linked into the Runner, in-process userspace node only | `libghostty-vt` static library | in-process loopback | the Dart side still needs to open the linked archive, so the app falls back to mock data; no system-wide VPN, other apps cannot use the tailnet; iOS suspends background networking unless a Network Extension or background mode is used (not planned for v1); App Store review may question VPN-like behaviour; unsigned builds only in CI for now |
| Linux | Go c-shared `.so` | `libghostty-vt` static / shared | in-process loopback | the bundle ships both libraries and runs on Xvfb in CI |
| Windows | Go c-shared DLL (cgo toolchain) | `libghostty-vt` built for Windows | in-process loopback | ship DLLs next to the exe; unsigned zip; built on a Windows runner in CI, not yet run |
| macOS | Go c-shared dylib (arm64 + x86_64) | `libghostty-vt` | in-process loopback | unsigned `.app` zip for now, not yet run; notarization and App Sandbox network entitlements are release-time work |
| Web | mock backend with fixtures | mock terminal | none | `dart:ffi` unavailable; preview/debug only, deployed to GitHub Pages |

### Icons

`android/app/src/main/res` keeps the Kotlin app's adaptive icon verbatim — `mipmap-anydpi-v26/ic_launcher.xml`,
`drawable/ic_launcher_fg.xml` (3x3 dots, accent in the middle) and the `ic_bg`/`ic_fg`/`ic_accent` colours — so both
APKs carry the same icon bytes. Do not redraw it and do not let `flutter_launcher_icons` generate one: a change starts
in `markbang/taildeck` and is copied here. `tool/gen_icons.py` renders the Windows `.ico`, the macOS and iOS
`AppIcon.appiconset` entries, the Linux PNG and the Web icons from those same resources, cropped to the 72dp visible
part of the 108dp adaptive viewport the way the launcher mask shows it. `tool/compare_apk_icons.py` diffs the icon
resources of two APKs with `aapt2`, and the `icon-compare` workflow also screenshots both icons on an emulator.

## CI

- Every PR: `ci.yml` builds Android (APK with both native libraries), Linux (bundle, launched on Xvfb for a
  screenshot) and Web (screenshots); `pages.yml` deploys the Web preview from `main`.
- Windows, macOS and iOS: build only on tags or `workflow_dispatch` (`platform-release.yml`); artifacts stay
  unsigned. None of them has been launched.
- Android releases are signed with the Kotlin app's key (`top.bangwu.taildeck`, certificate `A7:6A:FE:7F…`), so
  they upgrade over it; the job verifies the signature of every APK and of the AAB. [SIGNING.md](SIGNING.md).

## Milestones

| Milestone | Scope | Landed |
|---|---|---|
| M0 | release check, these docs, platform scaffolding | 2026-11-13 |
| M1 | native FFI on Android and Linux: node status, peers, ping, login | 2026-11-13 |
| M2 | libghostty-vt terminal (M2a) and SSH sessions (M2b) | 2026-11-13 |
| M3 | services and gateway (M3a), settings, keys and logs (M3b), herdr agents (M3c) | 2026-11-13 – 2026-11-14 |
| M4 | Windows, macOS and unsigned iOS builds | 2026-11-13 |
| Polish | screen readers, Esc, reduce motion (2026-11-14); localized last-seen and key expiry (2026-11-14); Android network hooks (2026-11-14) | 2026-11-14 |
| Remaining | in-app WebView, notification actions, prompt queues, subagent transcripts, images, slash-command completion, Android foreground service, iOS Dart loader, running the desktop/iOS builds, live-tailnet verification | open |

## Remaining

- **WebView** — services open in the system browser; the Kotlin app's proxy-override WebView is not ported.
- **Agents** — notification actions, prompt queues, subagent transcripts, images and slash-command completion.
- **Android** — a foreground service so the node outlives the activity; no device run so far.
- **iOS** — `DynamicLibrary.process()` support so the linked archive is used instead of mock data.
- **Desktop** — run the Windows and macOS packages; signing, notarization and the App Store review are release work.
- **Verification** — a tailnet with a control server and an auth key is still needed for login, peers, SSH, herdr
  and port scans. See [PARITY.md](PARITY.md).

## Docs

English is the default. Every document has a `.zh-CN.md` sibling with the same sections and the same facts, and
README pairs cross-link at the top. [PARITY.md](PARITY.md) tracks feature parity with the Kotlin app and
[SIGNING.md](SIGNING.md) the release signing.
