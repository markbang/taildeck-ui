[English](README.md) · [中文](README.zh-CN.md)

# native

Flutter 应用背后的 C ABI。这里的代码不改动 `lib/`；插件之后再接入。

| 目录 | 内容 | 产物 |
|---|---|---|
| `bridge/` | Go tsnet 节点、`:18680` 本地回环网关、SSH 客户端、herdr 代理操作（`package tsbridge`） | `libtaildeck_bridge.so` |
| `term/` | `libghostty-vt` 绑定：旧 Kotlin 应用用 `term_jni.c`，dart:ffi 用 `term_ffi.c` | `libghostty-vt.a` + 终端 shim |

`bridge/` 是 Taildeck bridge 的唯一源码（模块路径和包 API 不变）。
`markbang/taildeck` 保存一份只读的 vendored 副本，由那边的脚本同步。要修改 bridge，
只在这里改，然后在 `markbang/taildeck` 运行同步（`tool/sync-bridge.sh <sha>`）。

## 构建 bridge

`tool/build_native.sh` 运行下面两种构建，并把每个库放到宿主期望的位置（没有 C 编译器时跳过
`linux`，没有 NDK 时跳过 `android`）：

| 目标 | 产物 | 加载方 |
|---|---|---|
| linux/amd64 | `linux/lib/libtaildeck_bridge.so` | `linux/CMakeLists.txt` 复制到 bundle 的 `lib/`，与可执行文件同目录打开 |
| android/arm64 | `android/app/src/main/jniLibs/arm64-v8a/` | `DynamicLibrary.open('libtaildeck_bridge.so')` |
| android/x86_64 | `android/app/src/main/jniLibs/x86_64/` | 同上，供模拟器使用（`tool/build_native.sh android-x86_64`） |
| windows/x64 | `windows/lib/taildeck_bridge.dll` | `windows/CMakeLists.txt` 安装到 runner exe 旁边 |
| macos（universal） | `macos/Frameworks/libtaildeck_bridge.dylib` | Runner 的 "Copy native libs" 阶段复制到 `Taildeck.app/Contents/Frameworks/` |
| ios/arm64 | `ios/Frameworks/libtaildeck_bridge.a` | 通过 `ios/Flutter/NativeBridge.xcconfig` 链接进 Runner |

两种产物都被 git 忽略，所以全新 checkout 必须先构建它们，应用才能找到节点；没有库时
`lib/src/native/bridge.dart` 返回 null，界面保持模拟数据并显示一条内联提示。

Linux（本仓库的开发机和 CI）：

```bash
cd native/bridge
CGO_ENABLED=1 go build -buildmode=c-shared \
  -trimpath -o build/libtaildeck_bridge.so ./cmd/cshared
```

Android，同样的 c-shared 构建，使用 NDK clang（Go 工具链来自 `go.mod` 的 `toolchain` 行，NDK r28）：

```bash
NDK=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin
CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
  CC=$NDK/aarch64-linux-android26-clang \
  go build -buildmode=c-shared -trimpath \
  -tags badlinkname,tfogo_checklinkname0 -ldflags "-s -w -checklinkname=0" \
  -o build/android-arm64/libtaildeck_bridge.so ./cmd/cshared
```

`tool/build_native.sh` 优先使用 `aarch64-linux-android24-clang` 以匹配 Flutter 应用的
`minSdk`，找不到时回退到 26 的包装器。

每个目标都有名字，所以 CI 只构建任务需要的目标；`tool/build_native.sh all` 构建宿主能产出的每一个。
Windows 需要 `mingw-w64`（`x86_64-w64-mingw32-gcc`）；macOS 和 iOS 需要装有 Xcode 的 macOS，
其他环境会打印提示并跳过。`tool/build_term.sh` 接受同样的名字，并把
`libtaildeck_term.{so,dll,dylib,a}` 放在 bridge 库旁边（iOS 的 `.a` 把 shim 和 libghostty-vt 合并在一起）。

iOS 为 arm64 构建 `-buildmode=c-archive`，并用 `-force_load` 链接 runner，因为没有 Swift 代码引用这些符号：
脚本会写入 `ios/Flutter/{Debug,Release}.xcconfig` 中可选的 `#include? "NativeBridge.xcconfig"`。
iOS 的 Dart 端仍需要 `DynamicLibrary.process()` 而不是文件路径；在那之前，应用在 iOS 上回退到模拟数据。

## bridge ABI

`td_free` 释放库返回的、或交给事件回调的每个 `char*`。它们全部是 JSON：`{"ok":true,...}` 或 `{"ok":false,"error":"..."}`。

| 函数 | 结果字段 |
|---|---|
| `td_start(json)` | `gatewayPort`，启动节点；`{}` 配置不会启动任何有用的东西，`dir` 必填 |
| `td_stop()` / `td_logout()` / `td_network_changed()` | 无 |
| `td_status()` | `state`、`self`、`peers` 等（合并后的 `tsbridge.Status` 对象） |
| `td_logs()` | `logs`（最近 500 行，以 `\n` 分隔） |
| `td_gateway_port()` | `int`，停止时为 0 |
| `td_ping(ip)` | `latencyMs`、`endpoint`、`derp`、`peerRelay`、`error`；5 秒超时 |
| `td_ping_cancel(ip)` | `cancelled`，停止发往 `ip` 的进行中的 ping |
| `td_probe(host, portsCSV)` | `ports`（开放的 TCP 端口）；每个端口 1 秒，总计 8 秒 |

`td_start` 配置：`dir`、`hostname`、`controlURL`、`authKey`、`gatewayPort`、
`platform`（`"go"` 表示 Go 标准库接口加 DNS；`"host"` 表示使用 `td_set_platform_cb` 设置的回调，
Android 11+ 上 `net.Interfaces` 被禁用，需要这种方式）。
`td_set_platform_cb(ifaces, defaultIf, lookup, ctx)` 接受返回 `char*` 的 C 函数，库会复制这些字符串，且从不释放它们。

事件：`td_set_event_cb(cb, ctx)`，回调签名为 `void cb(int kind, char* json, void* ctx)`，
kind `1` 为状态 `{"state","authUrl"}`，`2` 为登录 URL `{"url"}`，`3` 为日志行 `{"line"}`。

每个导出函数都会把 panic 转换为上面的 JSON 错误：Go 的 panic 若展开进 C，会终止进程，在 Android 上是致命的。
会访问网络的调用会阻塞，所以 Dart 端在 worker isolate 上运行它们；见 `docs/ARCHITECTURE.zh-CN.md`。

回调字符串由宿主通过 `malloc` 分配并负责：需要多久就保留多久，每个都用 `td_free` 释放
（Go 不会释放它们，所以 Dart 的异步监听器可以安全读取）。

回调在 Go 线程上到达，从不在 Flutter UI 线程上，并且在回调执行期间仍会继续到达。在 Dart 中这意味着
使用 `NativeCallable.listener`（它投递到 isolate 的事件循环），而不是 `NativeCallable.isolateLocal`，
并且每个负载都要先复制成 Dart 类型，然后再 `td_free`。

## 构建终端

```bash
native/term/build-ghostty.sh          # Zig 0.17 + NDK -> native/term/build/ghostty
clang -c -Wall -Wextra -O2 -Inative/term/build/ghostty/include term_ffi.c
```

`term_ffi.c` 是去掉 JNI 的 JNI shim：相同的 `TdTerm` 状态、相同的回调、`pthread` 互斥锁（Windows 上为 SRWLOCK）。
`td_term_create/destroy/write/resize/snapshot/scroll/encode_key/encode_mouse/encode_focus/take_clipboard/encode_paste/select/selection_text/title/codepoint_width`
声明在 `term_ffi.h` 中；每个返回的缓冲区都用 `malloc` 分配，由 `td_term_free` 释放。与 `term_jni.c` 不同，
`td_term_encode_key` 接受的是 `GhosttyKey` 代码，而不是 Android 键码。`term_jni.c` 仍可为旧应用编译，但这里不构建它。

## 冒烟测试

```bash
CGO_ENABLED=1 go build -buildmode=c-shared -o native/bridge/build/libtaildeck_bridge.so ./native/bridge/cmd/cshared
/root/flutter347/bin/dart run tool/ffi_smoke.dart
```

它通过 `dart:ffi` 加载 `.so`，用错误输入调用 `td_status` / `td_logs` / `td_start`，打印 JSON 并释放每个字符串。
不需要登录 tailnet。
