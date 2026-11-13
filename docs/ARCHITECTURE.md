[English](ARCHITECTURE.md) · [中文](ARCHITECTURE.zh-CN.md)

# Architecture

> **Status: planned, not implemented.** This document describes the target design. The M1 native core ABIs live in
> `native/` (see `native/README.md`); `lib/` is still a UI layer on mock data (`lib/src/data.dart`).

## Goal

One Flutter client for Android, iOS, Windows, Linux and macOS. Web stays a debug and preview target.
The UI, theme and navigation in `lib/` stay shared; only a thin native boundary differs per platform.

## Native boundary

Reuse the existing Go module `bridge/` from [markbang/taildeck](https://github.com/markbang/taildeck) unchanged
where possible. It already contains the tsnet engine, a loopback gateway at `127.0.0.1:18680`, the SSH client and
herdr agent operations.

One call path on every platform: the same Go module built with `-buildmode=c-shared` and loaded through `dart:ffi`.

| Platform | Packaging | Call path |
|---|---|---|
| Android | `libtaildeck_bridge.so` in `jniLibs`, built with the NDK clang and 16 KB-page aligned; a small Kotlin foreground service keeps the process alive | `dart:ffi` → C ABI → Go |
| iOS | `-buildmode=c-archive` static library linked into the Runner | `dart:ffi` → C ABI → Go |
| Windows / Linux / macOS | `-buildmode=c-shared` DLL / `.so` / dylib shipped next to the app | `dart:ffi` → C ABI → Go |

This replaces the gomobile AAR for the Flutter client. The legacy Kotlin app in
[markbang/taildeck](https://github.com/markbang/taildeck) keeps its own `gomobile bind` AAR / XCFramework build;
the two share the Go source, not the bindings.

The C ABI is the stable contract; JSON in and JSON out for start, stop, status, logs, ping and gateway port
(`td_start` … `td_free` in `native/README.md`), plus SSH session calls and a single event callback for state and
log pushes. No Go types or pointers cross the boundary, so a Go or Flutter upgrade does not break the other side.

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
| Android | in-app tsnet via the c-shared `.so` | `libghostty-vt` `.so`, NDK CMake | `127.0.0.1:18680` loopback | foreground service keeps the node alive when backgrounded; no VPN slot; minSdk 26 |
| iOS | c-archive linked into the Runner, in-process userspace node only | `libghostty-vt` static library | in-process loopback | no system-wide VPN, other apps cannot use the tailnet; iOS suspends background networking unless a Network Extension or background mode is used (not planned for v1); App Store review may question VPN-like behaviour; unsigned builds only in CI for now |
| Linux | Go c-shared `.so` | `libghostty-vt` static / shared | in-process loopback | local desktop build verified first |
| Windows | Go c-shared DLL (cgo toolchain) | `libghostty-vt` built for Windows | in-process loopback | ship DLLs next to the exe; unsigned zip; cross-compiled in CI on a Windows runner |
| macOS | Go c-shared dylib (arm64 + x86_64) | `libghostty-vt` | in-process loopback | unsigned `.app` zip for now; notarization and App Sandbox network entitlements are release-time work |
| Web | mock backend with fixtures | mock terminal | none | `dart:ffi` unavailable; preview/debug only, deployed to GitHub Pages |

## CI

- Every PR: Android and Linux builds plus a Web screenshot job.
- Windows, macOS and iOS: build only on tags or `workflow_dispatch`; iOS and macOS artifacts stay unsigned.

## Milestones

| Milestone | Scope |
|---|---|
| M0 | release check, these docs, platform scaffolding |
| M1 | native FFI on Android and Linux: node status, peers, ping, login |
| M2 | terminal and SSH |
| M3 | services, gateway/WebView, agents, settings and key management at parity with the Kotlin app |
| M4 | Windows, macOS and unsigned iOS |
| M5 | packaging |

## Docs

English is the default. Every document has a `.zh-CN.md` sibling with the same sections and the same facts, and
README pairs cross-link at the top.
