中文 · [English](ARCHITECTURE.md) · [功能对比](PARITY.zh-CN.md)

# 架构

> **状态：Android 和 Linux 已实现，Web 只是预览。** 桥接与终端 FFI、Android 平台钩子、未签名的桌面/iOS 构建
> 都已落地（见里程碑）。Windows、macOS 和 iOS 已接好原生库，但还没运行过。`lib/src/data.dart` 仍作为网页预览的
> 数据源保留。

## 目标

一套 Flutter 客户端覆盖 Android、iOS、Windows、Linux 和 macOS。Web 只作为调试和预览目标。
`lib/` 里的界面、主题和导航各平台共用，差异只在一层很薄的原生边界。

## 原生边界

尽量原样复用 [markbang/taildeck](https://github.com/markbang/taildeck) 现有的 Go 模块 `bridge/`。
它已经包含 tsnet 引擎、`127.0.0.1:18680` 的本地回环网关、SSH 客户端和 herdr agent 操作。这里以
`native/bridge` 引入，只新增了 `cmd/cshared` 入口。

所有平台只有一条调用路径：同一 Go 模块用 `-buildmode=c-shared` 构建，通过 `dart:ffi` 加载。

| 平台 | 打包方式 | 调用路径 |
|---|---|---|
| Android | `libtaildeck_bridge.so` 放进 `jniLibs`，用 NDK clang 构建并对齐 16 KB 页 | `dart:ffi` → C ABI → Go |
| iOS | `-buildmode=c-archive` 静态库，链进 Runner | `dart:ffi` → C ABI → Go（Dart 侧加载器尚缺） |
| Windows / Linux / macOS | `-buildmode=c-shared` 的 DLL / `.so` / dylib，随应用一起分发 | `dart:ffi` → C ABI → Go |

Flutter 客户端由此取代 gomobile AAR；[markbang/taildeck](https://github.com/markbang/taildeck) 里的旧 Kotlin
应用仍保留自己的 `gomobile bind` AAR / XCFramework 构建，两者共用 Go 源码而不是绑定层。

C ABI 是稳定的契约：启动、停止、状态、日志、ping、端口探测和网关端口均以 JSON 传入、JSON 返回（`td_start` …
`td_free`，见 `native/README.md`），另有 SSH 会话调用、密钥与主机密钥调用、herdr 调用，以及一个事件回调用于
推送状态与日志。边界上不传 Go 类型或指针，所以升级 Go 或 Flutter 都不会弄坏另一边。

### 当前已实现

- `native/bridge` 可为 Linux、Android、Windows 和 macOS 构建（`tool/build_native.sh`），导出节点启停、登出、
  状态、日志、ping、端口探测、SSH、SSH 密钥、主机密钥和 herdr。
- `native/term` 把 libghostty-vt 包在 `td_term_*` C ABI 后（`tool/build_term.sh`）；Flutter 只绘制快照并转发
  编码后的输入。
- `lib/src/native/` 在 Android 和 Linux 上通过 `dart:ffi` 加载两个库；Dart 侧还有 `backend.dart`、
  `herdr.dart` 和 `services.dart`。Web 使用桩实现和 `data.dart`。
- CI 每个 PR 构建 Android debug APK、Linux 产物（在 Xvfb 里运行并截图）和网页预览；Windows、macOS 和 iOS
  在打 tag 或手动触发时构建未签名包。

### Android 平台钩子

Android 11+ 屏蔽 Go 的 `net.Interfaces` 所用的 netlink，应用也没有 `resolv.conf`，因此 Android 上节点以
`"platform": "host"` 启动。Kotlin 辅助类（`android/.../PlatformBridge.kt`）用 `ConnectivityManager`、
`NetworkInterface` 和 `InetAddress` 提供网卡列表、默认网卡和 DNS 查询；JNI 转接层
`native/bridge/cmd/cshared/platform_jni.c` 把它们交给 `td_set_platform_cb`，并把默认网络变化转发给
`td_network_changed`。其他平台继续用 Go 标准库实现。

## 终端

复用 `libghostty-vt`，外面套一层很薄的纯 C ABI 转接，通过 `dart:ffi` 调用：

`td_term_create` · `td_term_destroy` · `td_term_write` · `td_term_resize` · `td_term_snapshot` ·
`td_term_encode_key` · `td_term_encode_mouse` · `td_term_encode_focus` · `td_term_take_clipboard` ·
`td_term_encode_paste` · `td_term_select` · `td_term_selection_text` · `td_term_title`，声明在
`native/term/term_ffi.h`。

模拟器留在原生侧；Flutter 只负责渲染快照、转发输入。不要在 Dart 里重写终端模拟器。

## 平台

| 平台 | 节点 | 终端 | 网关 | 限制 |
|---|---|---|---|---|
| Android | c-shared `.so` 承载的应用内 tsnet | `libghostty-vt` `.so`，NDK CMake | `127.0.0.1:18680` 回环 | 还没有前台服务，进程结束节点就停；不占 VPN 槽位；minSdk 26；原生库覆盖 arm64-v8a、armeabi-v7a、x86_64；CI 构建已签名的 APK 与 AAB，未在真机测试 |
| iOS | c-archive 链进 Runner，仅进程内用户态节点 | `libghostty-vt` 静态库 | 进程内回环 | Dart 侧还打不开链接进来的静态库，应用会回退到模拟数据；没有系统级 VPN，其他应用无法使用该 tailnet；除非使用 Network Extension 或后台模式（v1 未计划），iOS 会挂起后台网络；App Store 审核可能质疑类 VPN 行为；目前 CI 只出未签名构建 |
| Linux | Go c-shared `.so` | `libghostty-vt` 静态 / 动态库 | 进程内回环 | 产物带两个原生库，CI 在 Xvfb 里运行 |
| Windows | Go c-shared DLL（cgo 工具链） | 为 Windows 构建的 `libghostty-vt` | 进程内回环 | DLL 与 exe 放在一起；未签名 zip；CI 在 Windows runner 上构建，尚未运行 |
| macOS | Go c-shared dylib（arm64 + x86_64） | `libghostty-vt` | 进程内回环 | 目前是未签名 `.app` zip，尚未运行；公证和 App Sandbox 网络授权属于发布阶段的工作 |
| Web | 带固定数据的模拟后端 | 模拟终端 | 无 | 没有 `dart:ffi`；仅用于预览/调试，部署在 GitHub Pages |

### 图标

`android/app/src/main/res` 原样保留 Kotlin 版的自适应图标 —— `mipmap-anydpi-v26/ic_launcher.xml`、
`drawable/ic_launcher_fg.xml`（3×3 圆点，中心为强调色）以及 `ic_bg`/`ic_fg`/`ic_accent` 三个颜色 —— 因此两个
APK 里的图标字节完全一致。不要重画，也不要让 `flutter_launcher_icons` 生成：改动从 `markbang/taildeck` 开始，
再复制过来。`tool/gen_icons.py` 用同一份资源渲染 Windows `.ico`、macOS 与 iOS 的 `AppIcon.appiconset`、Linux PNG
和网页图标，按启动器遮罩的可见范围裁到 108dp 自适应视口的 72dp 区域；`tool/compare_apk_icons.py` 用 `aapt2`
对比两个 APK 的图标资源，`icon-compare` 工作流还会在模拟器上分别截图两个图标。

## CI

- 每个 PR：`ci.yml` 构建 Android（带两个原生库的 APK）、Linux（产物在 Xvfb 里启动并截图）和 Web（截图）；
  `pages.yml` 从 `main` 部署网页预览。
- Windows、macOS、iOS：仅在打 tag 或 `workflow_dispatch` 时构建（`platform-release.yml`），产物保持未签名，
  都没有启动过。
- Android 发布包用 Kotlin 版的密钥签名（`top.bangwu.taildeck`，证书 `A7:6A:FE:7F…`），可直接升级覆盖；任务会
  逐个校验 APK 与 AAB 的签名。见 [SIGNING.zh-CN.md](SIGNING.zh-CN.md)。

## 里程碑

| 里程碑 | 范围 | 落地 |
|---|---|---|
| M0 | 发布检查、本文档、各平台骨架 | 2026-11-13 |
| M1 | Android / Linux 原生 FFI：节点状态、对端、ping、登录 | 2026-11-13 |
| M2 | libghostty-vt 终端（M2a）与 SSH 会话（M2b） | 2026-11-13 |
| M3 | 服务与网关（M3a）、设置/密钥/日志（M3b）、herdr agents（M3c） | 2026-11-13 – 2026-11-14 |
| M4 | Windows、macOS 和未签名 iOS 构建 | 2026-11-13 |
| 打磨 | 读屏、Esc、减少动态效果（2026-11-14）；最后在线与密钥到期日期本地化（2026-11-14）；Android 网络钩子（2026-11-14） | 2026-11-14 |
| 尚缺 | 应用内 WebView、通知操作、消息队列、子代理会话、图片、斜杠命令补全、Android 前台服务、iOS Dart 加载器、运行桌面/iOS 产物、真实 tailnet 验证 | 未完成 |

## 尚缺

- **WebView** —— 服务目前在系统浏览器打开；Kotlin 版支持代理覆盖的 WebView 还没有移植。
- **Agents** —— 通知操作、消息队列、子代理会话、图片和斜杠命令补全。
- **Android** —— 让节点在 Activity 之外存活的 foreground service；目前没有真机运行。
- **iOS** —— 支持 `DynamicLibrary.process()`，用上链接进来的静态库而不是模拟数据。
- **桌面** —— 实际运行 Windows 和 macOS 产物；签名、公证和 App Store 审核属于发布阶段的工作。
- **验证** —— 仍需要一个带控制服务器和 auth key 的 tailnet 来验证登录、对端、SSH、herdr 和端口扫描。
  见 [PARITY.zh-CN.md](PARITY.zh-CN.md)。

## 文档

英文为默认语言。每份文档都有同名 `.zh-CN.md` 版本，章节和事实保持一致；成对的 README 在顶部互相链接。
[PARITY.zh-CN.md](PARITY.zh-CN.md) 跟踪与 Kotlin 版的功能差距，[SIGNING.zh-CN.md](SIGNING.zh-CN.md) 说明发布签名。
