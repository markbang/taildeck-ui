# 与 Kotlin 版的动效对齐

Kotlin 版（`markbang/taildeck`）跑在 Material 3 Expressive 动效上
（`MaterialExpressiveTheme(motionScheme = MotionScheme.expressive())`，
`ui/Theme.kt:46`）。`Motion` 对象（`ui/Theme.kt:49`）从 material3
1.5.0-alpha14 取出五档规格，所有调用点都从中选一。

本文件列出该版本里的全部动效与反馈，写明 Flutter 版的对等实现，以及哪段
录屏能证明它。英文版：[MOTION-PARITY.md](MOTION-PARITY.md)。

## 时间参数

Compose 用弹簧。Flutter 的 `AnimationController` 需要时长和曲线，所以
`lib/src/motion.dart` 保留同一条弹簧：prism_ui 的 `SpringCurve` 采样物理
曲线，时长取弹簧稳定到 0.1% 以内的时间（与 Compose 的时长估算一致）。

| 档位 | Kotlin | 弹簧（阻尼 / 刚度） | Flutter | 用途 |
| --- | --- | --- | --- | --- |
| 慢空间 | `Motion.slow()` | 0.8 / 200 → 600 ms | `motion.dart:34` | 页面滑动、标签页滑动、尺寸变化 |
| 快空间 | `Motion.fast()` | 0.6 / 800 → 360 ms | 暂未单独使用 | 短距离位移 |
| 默认淡入 | `Motion.fade()` | 1.0 / 1600 → 230 ms | `motion.dart:37` | 淡入淡出、颜色变化 |
| 快速淡出 | `Motion.fadeFast()` | 1.0 / 3800 → 150 ms | `motion.dart:40` | 离场元素 |
| 慢速淡入 | `Motion.fadeSlow()` | 1.0 / 800 → 330 ms | 暂未使用 | Kotlin 版也未使用 |
| animateFloatAsState 默认 | `spring()` | 1.0 / 1500 → 240 ms | `motion.dart:44` | 箭头旋转 |
| animateItem 归位 | `spring(0.8, 380)` | 0.8 / 380 → 450 ms | `motion.dart:48` | 列表行的加入与移除 |

Flutter 侧全部走 `context.motionDuration(spec)`（`motion.dart:51`），因此
系统开启“减少动态效果”时长归零；循环动效（脉冲、旋转、圆点、波浪）静止。

下表用到的组件：

| 组件 | 文件 | Compose 对应 |
| --- | --- | --- |
| `MotionSwitcher` | `motion.dart:112` | `NavHost` 推入/返回 |
| `FadeThrough` | `motion.dart:240` | `AnimatedContent` 淡入淡出 |
| `PulsingDot` | `motion.dart:262` | `AgentDot` |
| `MotionVisibility` | `motion.dart:344` | `AnimatedVisibility`（淡入、缩放、展开） |
| `SlideFadeSwitcher` | `motion.dart:468` | 带滑动的 `AnimatedContent` |
| `ScaleFadeSwitcher` | `motion.dart:507` | `AnimatedContent` 默认过渡 |
| `RotatingChevron` | `motion.dart:541` | `animateFloatAsState` 箭头 |
| `InkDots` | `motion.dart:570` | 工作条里的 `InkDots` |
| `ShapeBadge` / `BlobShape` | `widgets/shape_badge.dart:34` | `ShapeBadge` + `Morph` |
| `WavyLine`、`WavyActivityIndicator` | `widgets/wavy.dart:8`、`:128` | Material 3 波浪进度与加载 |
| `showMotionSnack` | `widgets/snackbar.dart:10` | `SnackbarHost` |

## 清单

状态：**已对齐** = Flutter 用 Kotlin 的时长与曲线实现；**Partial** = 有实现
但差异已在本表写明；**Missing** = Flutter 界面里还没有。录屏列写
`docs/motion/` 里的片段，或 `pending` 及所需条件。

| # | Kotlin（文件:行） | 动效与触发 | 时长 / 曲线 | Flutter 对应 | 状态 | 录屏 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `MainActivity.kt:92` | 前进：新页面从 1/5 宽度处滑入 + 淡入 | 慢空间 | `motion.dart:112` `MotionSwitcher`（`shell.dart:530`） | 已对齐 | pending — 需要真实节点上的第二个页面 |
| 2 | `MainActivity.kt:93` | 前进：旧页面滑到 -1/10 并淡出 | 慢空间 / 快速淡出 | 同上 | 已对齐 | pending — 同上 |
| 3 | `MainActivity.kt:94` | 返回：页面从 -1/10 滑入 + 淡入 | 慢空间 | 同上，`forward: false` | 已对齐 | pending — 同上 |
| 4 | `MainActivity.kt:95` | 返回：页面滑到 1/5 并淡出 | 慢空间 / 快速淡出 | 同上 | 已对齐 | pending — 同上 |
| 5 | `MainActivity.kt:99` | 登录路由淡入淡出 | 慢空间 / 快速淡出 | 同上，场景 `login` | 已对齐 | `flutter-start.mp4` 有登录页；路由切换需要登录 |
| 6 | `MainActivity.kt:107` | 登录完成：外壳淡入并从 0.96 放大 | 慢空间 | `MotionSwitcher(fadeThrough: true)`（`shell.dart:533`） | 已对齐 | pending — 需要 tailnet 登录 |
| 7 | `HomeScreen.kt:152` | 切换标签：滑动 1/8 页宽并交叉淡化 | 入：慢空间；出：快空间 | `shell.dart:646` + `_TabPage`（`shell.dart:620`） | 已对齐 | `flutter-tabs.mp4`（本版本；Kotlin 主页需要 tailnet） |
| 8 | `LoginScreen.kt:162` | 登录阶段切换：淡入 + 垂直滑动 1/6 + 尺寸过渡 | 慢空间 | `login.dart:520` `_StageSwap` | 已对齐 | pending — 片段拍的是区块，不是阶段切换 |
| 9 | `LoginScreen.kt:129` | “高级”区域展开/收起 | 默认规格 | `login.dart:436` `ExpandVisibility` | 已对齐 | `flutter-expand.mp4` + `kotlin-expand.mp4` |
| 10 | `NodeScreen.kt:183` | Ping 结果行展开并淡入 | 慢空间 + 淡入 | `node_detail.dart:248` `ExpandVisibility` | 已对齐 | pending — 需要对端 |
| 11 | `NodeScreen.kt:184` | Ping 文本状态间交叉淡化 | 淡入 / 快速淡出 | `node_detail.dart:602` `FadeThrough` | 已对齐 | pending — 同上 |
| 12 | `NodeScreen.kt:224` | 端口扫描结果加入列表并改变高度 | animateItem + 内容尺寸 | `node_detail.dart:259`（只有展开；扫描行不是 `AnimatedGroupCard` 的子项） | Partial — 随区块出现，没有加入列表的归位动画 | pending — 需要 tailnet 对端 |
| 13 | `TerminalScreen.kt:273` | SSH 状态副标题交叉淡化 | 淡入 / 快速淡出 | `terminal.dart:548` `FadeThrough` | 已对齐 | pending — 需要真实会话 |
| 14 | `TerminalScreen.kt:279` | 重连按钮淡入 + 从 0.8 放大 | 默认淡入 | `terminal.dart:590` `MotionVisibility(scaleFrom: 0.8)` | 已对齐 | pending — 需要断开的会话 |
| 15 | `TerminalScreen.kt:282` | Agents 按钮淡入 + 从 0.6 放大 | 快速淡出 | `terminal.dart:606` `MotionVisibility(scaleFrom: 0.6)` | 已对齐 | pending — 需要 herdr 连接 |
| 16 | `WebScreen.kt:190` | 可后退时返回箭头淡入 | 默认淡入 | `web_view.dart:157` `ExpandVisibility` | 已对齐 | pending — 需要真实页面 |
| 17 | `WebScreen.kt:216` | 页面加载进度条淡入淡出 | 默认淡入 | `web_view.dart:178` `ExpandVisibility` | 已对齐 | pending — 同上 |
| 18 | `AgentsUi.kt:199` | 节点页的 herdr 概要卡展开 | 默认展开 + 淡入 | `node_detail.dart:670` `_HerdrSummary` | 已对齐 | pending — 需要该节点上的 herdr |
| 19 | `AgentsUi.kt:259` | herdr 就绪时新建 Agent 悬浮按钮淡入展开 | 默认规格 | `agents.dart:359` `_NewAgentFab` | 已对齐 | `app-agents.png`（静态，网页预览）；片段 pending |
| 20 | `AgentsUi.kt:279` | Agent 列表在 herdr 状态间切换 | 默认 AnimatedContent | `agents.dart:121` `ScaleFadeSwitcher` | 已对齐 | pending — 需要 herdr |
| 21 | `AgentsUi.kt:639` | 页头状态文字交叉淡化 | 默认 AnimatedContent | `agent_chat.dart:490` | 已对齐 | pending — 需要在线 Agent |
| 22 | `AgentsUi.kt:749` | 输入区切换为“被阻塞”提示面板，垂直滑动 1/3 | 默认规格 | `agent_chat.dart:858` `SlideFadeSwitcher` → `_BlockedPanel`（`:1954`） | 已对齐 | pending — 需要被阻塞的 Agent |
| 23 | `AgentsUi.kt:845` | 回到底部按钮淡入并放大 | 默认淡入 | `agent_chat.dart:1700` `_ScrollToBottom` | 已对齐 | pending — 需要很长的会话记录 |
| 24 | `AgentExtras.kt:518` | 子 Agent 数量胶囊淡入 | 默认淡入 | `agent_chat.dart:1739` `_WorkingBar` 胶囊 | 已对齐 | pending — 需要运行中的子 Agent |
| 25 | `AgentExtras.kt:217`、`:254`、`:324`、`AgentTimeline.kt:246`、`:448`、`AgentsUi.kt:765`、`:982`、`SettingsScreen.kt:94`、`NodeScreen.kt:224` | 内容随布局增减尺寸 | 慢空间 | `motion.dart:56` `AnimatedContentSize`（`node_detail.dart:248`、聊天工具组、待办条、思考卡） | Partial — 设置页的滚动内容没套 | — |
| 26 | `Expressive.kt:198`、`HomeScreen.kt:272`、`AgentsUi.kt:289`、`:711`、`NodeScreen.kt:224` | 列表行加入时归位、移除时收起 | animateItem（淡入 + 归位弹簧） | `controls.dart:179` `AnimatedGroupCard` | 已对齐 | — |
| 27 | `AgentTimeline.kt:244`、`:445` | 工具组与待办箭头旋转 180° | `animateFloatAsState` 默认 | `agent_chat.dart:2068` `_ToolGroup`、`:1828` `_TodoTrack`（`RotatingChevron`） | 已对齐 | pending — 需要工具调用与待办 |
| 28 | `AgentsUi.kt:977` | 可展开卡片：箭头旋转、内容改变高度 | 默认 | `agent_chat.dart:2185` `_ThinkingCard` | 已对齐 | pending — 需要思考消息 |
| 29 | `HomeScreen.kt:126` | 节点启动时的波浪线性进度 | Material 3 波浪，淡入淡出 | `nodes.dart:148` `MotionVisibility` + `wavy.dart:8` `WavyLine` | 已对齐 | pending — 需要原生后端启动中 |
| 30 | `AgentDialogs.kt:145`、`AgentExtras.kt:188`、`:591`、`:746`、`:889`、`:971`、`:1000`、`AgentTimeline.kt:202`、`:253`、`AgentsUi.kt:306`、`:694`、`HomeScreen.kt:221`、`NodeScreen.kt:174`、`:205` | Material 3 波浪加载指示器 | 1 秒循环 | `wavy.dart:128` `WavyActivityIndicator`，所有加载态都用它 | 已对齐 | pending — 需要原生/herdr 加载态 |
| 31 | `Expressive.kt:113` | 工作中的徽标每 9 秒转一圈 | 线性 | `widgets/shape_badge.dart:34` `ShapeBadge(spin: true)`（`agents.dart:470`、`node_detail.dart:709`） | 已对齐 | `app-agents.png` 有徽标；旋转需要片段 |
| 32 | `Expressive.kt:99` | 状态变化时徽标多边形变形 | 慢空间 | 同上，`BlobShape.lerp` 跑慢空间弹簧 | 已对齐 | pending — 需要状态变化 |
| 33 | `Expressive.kt:110` | 徽标底色随状态淡变 | 默认淡入 | 同上（颜色补间跑淡入弹簧） | 已对齐 | pending — 同上 |
| 34 | `AgentsUi.kt:174` | 工作中/被阻塞时状态点 0.35 → 1 脉冲 | 700 ms 往返 | `motion.dart:262` `PulsingDot`（`foundation.dart:339`） | 已对齐 | pending — 需要在线 Agent |
| 35 | `AgentExtras.kt:486` | 三个“输入中”圆点轮流亮起 | 600 ms，错开 160 ms，往返 | `motion.dart:570` `InkDots`（`agent_chat.dart:1739`） | 已对齐 | pending — 需要工作中的 Agent |
| 36 | `Common.kt:31` | 节点状态点在线/离线颜色淡变 | 默认淡入 | `motion.dart:262` `PulsingDot` 颜色补间 | 已对齐 | — |
| 37 | `Common.kt:112`、`HomeScreen.kt:186`、`AgentsUi.kt:246` | 下拉刷新，最少转 500–600 ms | Material 3 下拉刷新 | `foundation.dart:24`（`RefreshIndicator`）+ `nodes.dart:33`、`agents.dart:101` | Partial — 用 Material 的圆形指示器，不是波浪 | — |
| 38 | 所有 `clickable`/`Surface(onClick)` | 按下时的水波与状态层 | Material 3 | prism `PressRegion` 的着色 | Partial — 是平铺着色，不是水波 | `flutter-press.mp4` + `kotlin-press.mp4` |
| 39 | 所有 `IconButton(shapes = …)`、`Button(shapes = …)` | Expressive 按下形变：容器轻微压缩 | Material 3 默认 | `controls.dart:50` `TapFeedback(scale: true)`（0.97） | Partial — 是缩放，不是形变 | `flutter-press.mp4` + `kotlin-press.mp4` |
| 40 | `AgentsUi.kt:1070` | 长按“立即发送”触发长按振动 | — | `agent_chat.dart:234`、`:723`（`HapticFeedback.mediumImpact`） | 已对齐 | pending — 需要在线 Agent 才能长按 |
| 41 | `TerminalView.kt:382` | 长按选词并触发长按振动 | — | — | Missing — Flutter 终端没有选择手势 | — |
| 42 | `TerminalView.kt:603` | 终端响铃触发按键振动 | — | — | Missing — 终端桥没有暴露响铃事件 | — |
| 43 | `AgentsUi.kt:474`、`:501`、`:531`、`:589`、`:761`、`WebScreen.kt:135` | Snackbar 滑入、停留、滑出 | Material 3 | `widgets/snackbar.dart:10` `showMotionSnack`（聊天里的操作结果） | 已对齐 | pending — 需要 Agent 操作 |
| 44 | `AgentExtras.kt` 各 sheet、`AgentDialogs.kt` | 底部弹层与对话框滑入并缩放 | Material 3 | prism 弹层与对话框 | Partial — 用的是 prism 动效 | — |

合计 44 项：已对齐 36，Partial 6，Missing 2。

## 证据

`docs/motion/` 放的是 `tool/motion_record.sh`（手动工作流
`motion-record.yml`，产物名 `motion`）录下的片段。左边 Kotlin，右边本版本，
时长 1–6 秒。

| 片段 | 内容 | 对应行 |
| --- | --- | --- |
| `flutter-expand.mp4` / `kotlin-expand.mp4` | “高级 / 控制服务器”区域展开 | 9 |
| `flutter-press.mp4` / `kotlin-press.mp4` | 长按一个按钮 | 38、39 |
| `flutter-tabs.mp4` | 节点 → 服务标签切换，两页在中间相遇 | 7 |
| `flutter-start.mp4` | 登录页与控制服务器区块展开 | 5、9 |
| `app-agents.png` | 当前版本：Agent 列表徽标（状态多边形）、新建按钮 | 19、31–33 |

Kotlin 版在没有 tailnet 时始终停在登录页（要控制服务器接受后才会离开），
CI 模拟器同样没有 tailnet，所以所有需要真实对端、SSH、herdr 或断开会话的
动效都标为 `pending`，而不是拿片段当已对齐；这些是按实现对 Kotlin 调用点
逐条核对的。

同一次产物里的 `flutter-detail.mp4` 是空的节点页（模拟器没读到对端），
不作为证据。

## 重新录制

```bash
gh workflow run motion-record.yml --ref <branch>   # 然后下载 motion 产物
```

`tool/motion_record.sh <flutter.apk> <kotlin.apk>` 也能在任何已连接设备上跑；
需要 `adb`、`ffmpeg`，以及动画缩放为 1 的设备。
