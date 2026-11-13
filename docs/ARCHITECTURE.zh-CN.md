中文 · [English](ARCHITECTURE.md)

# 架构

> **状态：计划中，尚未实现。** 本文描述目标设计。目前应用是跑在模拟数据（`lib/src/data.dart`）上的界面层，
> 还没有接入任何原生代码。

## 目标

一套 Flutter 客户端覆盖 Android、iOS、Windows、Linux 和 macOS。Web 只作为调试和预览目标。
`lib/` 里的界面、主题和导航各平台共用，差异只在一层很薄的原生边界。

## 原生边界

尽量原样复用 [markbang/taildeck](https://github.com/markbang/taildeck) 现有的 Go 模块 `bridge/`。
它已经包含 tsnet 引擎、`127.0.0.1:18680` 的本地回环网关、SSH 客户端和 herdr agent 操作。

| 平台 | 打包方式 | 调用路径 |
|---|---|---|
| Android / iOS | `gomobile bind` → AAR / XCFramework，包在 Flutter 插件里 | Flutter 插件 → Go |
| Windows / Linux / macOS | 同一 Go 模块用 `-buildmode=c-shared` 构建 | `dart:ffi` → C ABI → Go |

C ABI 是稳定的契约：启动、停止、状态、日志、ping 和网关端口均以 JSON 传入、JSON 返回，另有 SSH 会话调用
和一个事件回调用于推送状态与日志。边界上不传 Go 类型或指针，所以升级 Go 或 Flutter 都不会弄坏另一边。

## 终端

复用 `libghostty-vt`，外面套一层很薄的纯 C ABI 转接，通过 `dart:ffi` 调用：

`td_term_create` · `td_term_destroy` · `td_term_write` · `td_term_resize` · `td_term_snapshot` ·
`td_term_encode_key` · `td_term_encode_mouse` · `td_term_clipboard`

模拟器留在原生侧；Flutter 只负责渲染快照、转发输入。不要在 Dart 里重写终端模拟器。

## 平台

| 平台 | 节点 | 终端 | 网关 | 限制 |
|---|---|---|---|---|
| Android | gomobile 承载的应用内 tsnet | `libghostty-vt` `.so`，NDK CMake | `127.0.0.1:18680` 回环 | 退到后台需前台服务保活；不占 VPN 槽位；minSdk 26 |
| iOS | gomobile XCFramework，仅进程内用户态节点 | `libghostty-vt` 静态库 | 进程内回环 | 没有系统级 VPN，其他应用无法使用该 tailnet；除非使用 Network Extension 或后台模式（v1 未计划），iOS 会挂起后台网络；App Store 审核可能质疑类 VPN 行为；目前 CI 只出未签名构建 |
| Linux | Go c-shared `.so` | `libghostty-vt` 静态 / 动态库 | 进程内回环 | 先在本机验证桌面构建 |
| Windows | Go c-shared DLL（cgo 工具链） | 为 Windows 构建的 `libghostty-vt` | 进程内回环 | DLL 与 exe 放在一起；未签名 zip；在 CI 的 Windows runner 上交叉编译 |
| macOS | Go c-shared dylib（arm64 + x86_64） | `libghostty-vt` | 进程内回环 | 目前是未签名 `.app` zip；公证和 App Sandbox 网络授权属于发布阶段的工作 |
| Web | 带固定数据的模拟后端 | 模拟终端 | 无 | 没有 `dart:ffi`；仅用于预览/调试，部署在 GitHub Pages |

## CI

- 每个 PR：构建 Android 和 Linux，并跑一个 Web 截图任务。
- Windows、macOS、iOS：仅在打 tag 或 `workflow_dispatch` 时构建；iOS 和 macOS 产物保持未签名。

## 里程碑

| 里程碑 | 范围 |
|---|---|
| M0 | 发布检查、本文档、各平台骨架 |
| M1 | Android / Linux 原生 FFI：节点状态、对端、ping、登录 |
| M2 | 终端与 SSH |
| M3 | 服务、网关/WebView、agents、设置与密钥管理，与 Kotlin 应用持平 |
| M4 | Windows、macOS 和未签名 iOS |
| M5 | 打包 |

## 文档

英文为默认语言。每份文档都有同名 `.zh-CN.md` 版本，章节和事实保持一致；成对的 README 在顶部互相链接。
