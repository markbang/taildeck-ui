# native

C ABIs behind the Flutter app. `lib/` is untouched by these; a plugin wires
them up later.

| Dir | What | Output |
|---|---|---|
| `bridge/` | Go tsnet node, `:18680` loopback gateway, SSH client, herdr agent ops (`package tsbridge`) | `libtaildeck_bridge.so` |
| `term/` | `libghostty-vt` bindings: `term_jni.c` for the old Kotlin app, `term_ffi.c` for dart:ffi | `libghostty-vt.a` + term shim |

`bridge/` is a copy of the engine in `markbang/taildeck` (module path and
package API unchanged). `cmd/cshared` is the only new Go code.

## Build the bridge

Linux (this repo's dev box and CI):

```bash
cd native/bridge
CGO_ENABLED=1 go build -buildmode=c-shared \
  -trimpath -o build/libtaildeck_bridge.so ./cmd/cshared
```

Android, same c-shared build with the NDK clang (Go 1.26 module, NDK r28):

```bash
NDK=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin
CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
  CC=$NDK/aarch64-linux-android26-clang \
  go build -buildmode=c-shared -trimpath \
  -tags badlinkname,tfogo_checklinkname0 -ldflags "-s -w -checklinkname=0" \
  -o build/android-arm64/libtaildeck_bridge.so ./cmd/cshared
```

iOS is not wired yet: it needs `-buildmode=c-archive` (Fat/arm64) on macOS
with Xcode, so it cannot be produced from Linux.

## Bridge ABI

`td_free` frees every `char*` the library returns or hands to the event
callback. All of them are JSON: `{"ok":true,...}` or `{"ok":false,"error":"..."}`.

| Function | Result fields |
|---|---|
| `td_start(json)` | `gatewayPort` — starts the node; `{}` config starts nothing useful, `dir` is required |
| `td_stop()` / `td_logout()` / `td_network_changed()` | none |
| `td_status()` | `state`, `self`, `peers`, … (the `tsbridge.Status` object, merged) |
| `td_logs()` | `logs` (last 500 lines, `\n`-separated) |
| `td_gateway_port()` | `int`, 0 when stopped |
| `td_ping(ip)` | `latencyMs`, `endpoint`, `derp`, `error` |

`td_start` config: `dir`, `hostname`, `controlURL`, `authKey`, `gatewayPort`,
`platform` (`"go"` = Go stdlib interfaces + DNS; `"host"` = the callbacks from
`td_set_platform_cb`, needed on Android 11+ where `net.Interfaces` is blocked).
`td_set_platform_cb(ifaces, defaultIf, lookup, ctx)` takes C functions returning
`char*` that the library copies and never frees.

Events: `td_set_event_cb(cb, ctx)` with `void cb(int kind, char* json, void* ctx)`,
kind `1` state `{"state","authUrl"}`, `2` login URL `{"url"}`, `3` log line
`{"line"}`.

Callback strings are `malloc`'d and owned by the host: keep them as long as
needed and release each one with `td_free` (they are not freed by Go, so
Dart's async listener can read them safely).

Callbacks arrive on Go threads, never the Flutter UI thread, and they keep
arriving while the callback runs. On Dart that means a
`NativeCallable.listener` (it posts to the isolate's event loop), never
`NativeCallable.isolateLocal`, and every payload is copied into Dart types and
then `td_free`d.

## Build the terminal

```bash
native/term/build-ghostty.sh          # Zig 0.17 + NDK -> native/term/build/ghostty
clang -c -Wall -Wextra -O2 -Inative/term/build/ghostty/include term_ffi.c
```

`term_ffi.c` is the JNI shim without JNI: same `TdTerm` state, same callbacks,
`pthread` mutex (SRWLOCK on Windows). `td_term_create/destroy/write/resize/
snapshot/scroll/encode_key/encode_mouse/encode_focus/take_clipboard/
encode_paste/select/selection_text/title/codepoint_width` are declared in
`term_ffi.h`; every returned buffer is `malloc`'d for `td_term_free`. Unlike
`term_jni.c`, `td_term_encode_key` takes a `GhosttyKey` code, not an Android
keycode. `term_jni.c` still compiles for the old app and is not built here.

## Smoke test

```bash
CGO_ENABLED=1 go build -buildmode=c-shared -o native/bridge/build/libtaildeck_bridge.so ./native/bridge/cmd/cshared
/root/flutter347/bin/dart run tool/ffi_smoke.dart
```

It loads the `.so` through `dart:ffi`, calls `td_status` / `td_logs` / `td_start`
with bad input, prints the JSON and frees every string. No tailnet login.
