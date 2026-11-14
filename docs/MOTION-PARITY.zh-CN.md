# 与 Kotlin 版的动效对齐

Kotlin 版（`markbang/taildeck`）跑在 Material 3 Expressive 动效上
（`MaterialExpressiveTheme(motionScheme = MotionScheme.expressive())`，
`ui/Theme.kt:46`）。`Motion` 对象（`ui/Theme.kt:49`）暴露 material3
1.5.0-alpha14 的规格，所有调用点都从中选一。

本文件列出该版本里的全部动效与反馈，写明 Flutter 的实现位置，并注明哪些经过
录屏核对。英文版：[MOTION-PARITY.md](MOTION-PARITY.md)。

## 时间参数

Compose 用弹簧。Flutter 的 `AnimationController` 需要时长和曲线，所以
`lib/src/motion.dart` 保留同一条弹簧：prism_ui 的 `SpringCurve` 采样物理
曲线，时长取弹簧稳定到 0.1% 以内的时间（与 Compose 的时长估算一致）。

| 档位 | Kotlin | 弹簧（阻尼 / 刚度） | Flutter | 用途 |
| --- | --- | --- | --- | --- |
| 慢空间 | `Motion.slow()` | 0.8 / 200 → 600 ms | `motion.dart:34` | 页面滑动、标签页滑动、尺寸变化 |
| 默认淡入 | `Motion.fade()` | 1.0 / 1600 → 230 ms | `motion.dart:37` | 淡入淡出、颜色变化 |
| 快速淡出 | `Motion.fadeFast()` | 1.0 / 3800 → 150 ms | `motion.dart:40` | 离场元素 |
| animateFloatAsState 默认 | `spring()` | 1.0 / 1500 → 240 ms | `motion.dart:44` | 箭头旋转 |
| animateItem 归位 | `spring(0.8, 380)` | 0.8 / 380 → 450 ms | `motion.dart:48` | 列表行的加入与移除 |
| （两边都未使用） | `Motion.fast()`、`Motion.fadeSlow()` | 0.6 / 800、1.0 / 800 | — | 没有调用点需要 |

Flutter 侧全部走 `context.motionDuration(spec)`（`prism_ui`），因此系统开启
“减少动态效果”时长归零；循环动效（脉冲、旋转、输入点、波浪）停在静止相位。

## 清单

状态：**已对齐** = Flutter 调用点的触发条件、弹簧档位与离场规格与 Kotlin 一致；
**Partial** = 有实现，差异已写明；**Missing** = 未实现。证据列写明
`docs/motion/` 中的对照片段，或说明为什么没有 tailnet 就录不到。

| # | Kotlin（文件:行） | 动效与触发 | 时长 / 曲线 | Flutter 对应 | 状态 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `MainActivity.kt:92` | 前进：新页面从 1/5 宽度处滑入并淡入 | 慢空间 | `motion.dart:112` `MotionSwitcher` (`shell.dart:537`) | 已对齐 | `flutter-detail.mp4`（本版本） |
| 2 | `MainActivity.kt:93` | 前进：旧页面滑到 -1/10 并淡出 | 慢空间、快速淡出 | same `MotionSwitcher` | 已对齐 | `flutter-detail.mp4` |
| 3 | `MainActivity.kt:94` | 返回：页面从 -1/10 滑入并淡入 | 慢空间 | same, `forward: false` | 已对齐 | `flutter-detail.mp4` |
| 4 | `MainActivity.kt:95` | 返回：页面滑到 1/5 并淡出 | 慢空间、快速淡出 | same | 已对齐 | `flutter-detail.mp4` |
| 5 | `MainActivity.kt:99` | 登录路由淡入淡出 | 慢空间 / 快速淡出 | same, scene `login` | 已对齐 | 未录制（需要未登录启动） |
| 6 | `MainActivity.kt:107` | 登录完成：外壳淡入并从 0.96 放大 | 慢空间 | `MotionSwitcher(fadeThrough: true)` (`shell.dart:539`) | 已对齐 | 未录制（需要一次登录） |
| 7 | `HomeScreen.kt:152` | 切换标签：滑动 1/8 页宽并交叉淡化 | 入慢空间、出快空间 | `shell.dart:172` + `_TabPage` (`shell.dart:646`) | 已对齐 | `flutter-tabs.mp4` |
| 8 | `LoginScreen.kt:162` | 登录阶段切换：淡入 + 垂直滑动 1/6 + 尺寸过渡 | 慢空间 | `login.dart:526` `_StageSwap` | 已对齐 | `flutter-start.mp4` |
| 9 | `LoginScreen.kt:129` | “高级”区域展开与收起 | 默认规格 | `login.dart:445` `ExpandVisibility` | 已对齐 | `login-expand.mp4`（Kotlin | Flutter） |
| 10 | `NodeScreen.kt:183` | Ping 结果行展开并淡入 | 慢空间 + 淡入 | `node_detail.dart:265` `ExpandVisibility` | 已对齐 | 无法录制（没有可 ping 的对端） |
| 11 | `NodeScreen.kt:184` | Ping 文本在状态间交叉淡化 | 淡入 / 快速淡出 | `node_detail.dart:619` `FadeThrough` | 已对齐 | 无法录制（没有可 ping 的对端） |
| 12 | `NodeScreen.kt:224` | 端口扫描结果加入列表并改变高度 | animateItem + 内容尺寸 | `node_detail.dart:276` `ExpandVisibility` (no item animation) | Partial | 无法录制（无对端） |
| 13 | `TerminalScreen.kt:273` | SSH 状态副标题交叉淡化 | 淡入 / 快速淡出 | `terminal.dart:585` `FadeThrough` | 已对齐 | 需要 tailnet |
| 14 | `TerminalScreen.kt:279` | 重连按钮淡入并从 0.8 放大 | 默认淡入 | `terminal.dart:598` `MotionVisibility` | 已对齐 | 需要 tailnet |
| 15 | `TerminalScreen.kt:282` | Agents 按钮淡入并从 0.6 放大 | 快速淡出 | `terminal.dart:614` `MotionVisibility` | 已对齐 | 需要 tailnet |
| 16 | `WebScreen.kt:190` | 可后退时返回箭头淡入 | 默认淡入 | `web_view.dart:157` `ExpandVisibility` | 已对齐 | 需要真实页面 |
| 17 | `WebScreen.kt:216` | 页面加载进度条淡入淡出 | 默认淡入 | `web_view.dart:178` `ExpandVisibility` | 已对齐 | 需要真实页面 |
| 18 | `AgentsUi.kt:199` | 节点页的 herdr 概要卡展开 | 默认展开 + 淡入 | `node_detail.dart:691` `MotionVisibility` + `:709` `ShapeBadge` | 已对齐 | 需要 herdr |
| 19 | `AgentsUi.kt:259` | herdr 就绪时新建 Agent 按钮淡入展开 | 默认规格 | `agents.dart:360` `_NewAgentFab` | 已对齐 | 需要 herdr |
| 20 | `AgentsUi.kt:279` | Agent 列表在 herdr 状态间切换 | 默认 AnimatedContent | `agents.dart:121` `ScaleFadeSwitcher` | 已对齐 | 需要 herdr |
| 21 | `AgentsUi.kt:639` | 页头状态文字交叉淡化 | 默认 AnimatedContent | `agent_chat.dart:529` `FadeThrough` | 已对齐 | 需要在线 Agent |
| 22 | `AgentsUi.kt:749` | 输入区切换为“被阻塞”面板，垂直滑动 1/3 | 默认规格 | `agent_chat.dart:858` `SlideFadeSwitcher` | 已对齐 | 需要在线 Agent |
| 23 | `AgentsUi.kt:845` | 回到底部按钮淡入并放大 | 默认淡入 | `agent_chat.dart:1700` `_ScrollToBottom` | 已对齐 | 需要在线 Agent |
| 24 | `AgentExtras.kt:518` | 子 Agent 数量胶囊淡入 | 默认淡入 | `agent_chat.dart:1784` `MotionVisibility` in `_WorkingBar` | 已对齐 | 需要在线 Agent |
| 25 | `AgentExtras.kt:217`, `:254`, `:324`, `AgentTimeline.kt:246`, `:448`, `AgentsUi.kt:765`, `:982`, `SettingsScreen.kt:94`, `NodeScreen.kt:224` | 内容随布局增减尺寸 | 慢空间 | `motion.dart:56` `AnimatedContentSize` (`agent_chat.dart:1850`, `:2116`, `:2155`, `:2208`, `:2260`, `login.dart:532`) | Partial | 聊天记录与设置页不做尺寸动画 |
| 26 | `Expressive.kt:198`, `HomeScreen.kt:272`, `AgentsUi.kt:289`, `:711`, `NodeScreen.kt:224` | 列表行加入时归位、移除时收起 | animateItem（淡入 + 归位弹簧） | `controls.dart:139` `AnimatedGroupCard` (`motion.dart:48` placement) | 已对齐 | 没有片段拍到行的加入或移除 |
| 27 | `AgentTimeline.kt:244`, `:445` | 工具组与待办箭头旋转 180° | `animateFloatAsState` 默认 | `motion.dart:541` `RotatingChevron` (`agent_chat.dart:1887`, `:2146`, `:2251`) | 已对齐 | 需要在线 Agent |
| 28 | `AgentsUi.kt:977` | 可展开卡片：箭头旋转、内容改变高度 | 默认 | `RotatingChevron` + `AnimatedContentSize` | 已对齐 | 需要在线 Agent |
| 29 | `HomeScreen.kt:126` | 节点启动时的波浪线性进度 | Material 3 波浪，淡入淡出 | `nodes.dart:147` `MotionVisibility` + `WavyLine` (`wavy.dart:8`) | 已对齐 | 需要已登录节点 |
| 30 | `AgentDialogs.kt:145`, `AgentExtras.kt:188`, `:591`, `:746`, `:889`, `:971`, `:1000`, `AgentTimeline.kt:202`, `:253`, `AgentsUi.kt:306`, `:694`, `HomeScreen.kt:221`, `NodeScreen.kt:174`, `:205` | Material 3 波浪加载指示器 | 1 秒循环 | `wavy.dart:128` `WavyActivityIndicator` (login, nodes, node detail, services, settings, chat, buttons) | Partial | 是波浪弧，不是形变的圆点 |
| 31 | `Expressive.kt:113` | 工作中的徽标每 9 秒转一圈 | 线性 | `shape_badge.dart:61` `ShapeBadge` spin (`9 s`) | 已对齐 | 需要 herdr |
| 32 | `Expressive.kt:99` | 状态变化时徽标多边形变形 | 慢空间 | `shape_badge.dart:55` `ShapeBadge` morph (`BlobShape`) | 已对齐 | 用 blob 近似 MaterialShapes 多边形 |
| 33 | `Expressive.kt:110` | 徽标底色随状态淡变 | 默认淡入 | `shape_badge.dart:58` | 已对齐 | 需要 herdr |
| 34 | `AgentsUi.kt:174` | 工作中/被阻塞时状态点 0.35 → 1 脉冲 | 700 ms 往返 | `motion.dart:262` `PulsingDot` via `StatusPill` (`foundation.dart:315`, `agents.dart:504`) | 已对齐 | 需要在线 Agent |
| 35 | `AgentExtras.kt:486` | 三个“输入中”圆点轮流亮起 | 600 ms，错开 160 ms，往返 | `motion.dart:570` `InkDots` in `_WorkingBar` (`agent_chat.dart:1769`) | 已对齐 | 需要在线 Agent |
| 36 | `Common.kt:31` | 节点状态点在线/离线颜色淡变 | 默认淡入 | `PulsingDot` colour tween (`motion.dart:262`) | 已对齐 | 没有片段改变节点状态 |
| 37 | `Common.kt:112`, `HomeScreen.kt:186`, `AgentsUi.kt:246` | 下拉刷新，最少转 500–600 ms | Material 3 下拉刷新 | `foundation.dart:25` + `nodes.dart:35`, `agents.dart:105` | Partial | 用 Material `RefreshIndicator`（圆形），不是波浪 |
| 38 | every `clickable`/`Surface(onClick)` | 按下时的水波与状态层 | Material 3 | prism `PressRegion` tint | Partial | 是平铺着色，不是水波 |
| 39 | every `IconButton(shapes = …)`, `Button(shapes = …)` | Expressive 按下形变：容器轻微压缩 | Material 3 默认 | `controls.dart:53` `TapFeedback(scale: true)` (0.97) | Partial | — |
| 40 | `AgentsUi.kt:1070` | 长按“立即发送”触发长按振动 | — | `agent_chat.dart:268` (`HapticFeedback.mediumImpact`) | 已对齐 | 需要在线 Agent |
| 41 | `TerminalView.kt:382` | 长按选词并触发长按振动 | — | `term_view.dart:149` `_selectWord` (native `td_term_select`) | 已对齐 | 需要 SSH 会话 |
| 42 | `TerminalView.kt:603` | 终端响铃触发按键振动 | — | `terminal.dart:225` (`TermMeta.effects` bit 0 → `selectionClick`) | 已对齐 | 需要 SSH 会话 |
| 43 | `AgentExtras.kt` sheets, `AgentDialogs.kt` | 底部弹层与对话框滑入并缩放 | Material 3 | prism sheets and dialogs | Partial | 用的是 prism 动效 |
| 44 | `AgentsUi.kt:474`, `:501`, `:531`, `:589`, `:761`, `WebScreen.kt:135` | Snackbar 滑入、停留、滑出 | Material 3 | `widgets/snackbar.dart:10` `showMotionSnack` (`agent_chat.dart:129`) | Partial | Web 页仍在页面内提示 |

合计 44 项：已对齐 36，Partial 8，Missing 0。

## 证据

片段放在 `docs/motion/`。录制有两条路径，因为 Android 模拟器用 SwiftShader
渲染，GPU 忙时编码器会丢掉大部分帧：

- `tool/motion_record.sh`（手动工作流 `motion-record.yml`）在同一台模拟器上录
  Kotlin v0.1.0 APK 与本版本，并左右拼接：左 Kotlin，右本版本。
  `login-expand.mp4` 是两个版本都不需要 tailnet 就能到达的那一项。
- `tool/motion_web.py` 用 Playwright 以 25 fps 录本版本的 Web 预览，动画的每
  一帧都在。

| 片段 | 内容 |
| --- | --- |
| `login-expand.mp4` | Kotlin / Flutter：高级区域展开，各一次手势 |
| `flutter-login-expand.mp4` | 本版本：认证密钥区域展开（淡入 + 尺寸变化） |
| `flutter-tabs.mp4` | 本版本：节点 → 服务 → Agent → 节点，滑动 1/8 并交叉淡化 |
| `flutter-detail.mp4` | 本版本：节点页从 1/5 处滑入，返回时反向 |
| `flutter-start.mp4` | 本版本：登录阶段切换（淡入 + 垂直滑动 1/6） |

Kotlin 版在没有 tailnet 时始终停在登录页（要控制服务器接受后才会离开），
所以需要主页、节点页、Agent、聊天或 SSH 界面的行，证据列写的是它需要什么，
而不是片段。这些都已实现，缺的只是视觉对照。

### 无法录到的部分

- Kotlin 版的主页、节点页、Agent 与聊天：都在可用的控制服务器之后，发布 APK
  也无法预置状态。
- 所有需要真实 tailnet 的效果：ping、端口扫描、SSH、herdr、服务图标。
- 按下反馈片段：模拟器丢输入事件太多，两次录制没有落在同一个控件上。

## 重新录制

```bash
gh workflow run motion-record.yml --ref <branch>   # 然后下载 motion 产物
python3 tool/motion_web.py                         # Web 片段，需要本地起静态服务
```

`tool/motion_record.sh <flutter.apk> <kotlin.apk>` 也可以在任意已连接设备上跑，
需要 `adb`、`ffmpeg`，并把动画时长倍率保持为 1。它会在每个片段开始前用
`uiautomator dump` 重新定位控件，因此设备需为英文界面且没有系统弹窗。
