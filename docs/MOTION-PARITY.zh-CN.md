# 与 Kotlin 版的动效对齐

Kotlin 版（`markbang/taildeck`）跑在 Material 3 Expressive 动效上
（`MaterialExpressiveTheme(motionScheme = MotionScheme.expressive())`，
`ui/Theme.kt:46`）。`Motion` 对象（`ui/Theme.kt:49`）从 material3
1.5.0-alpha14 取出五档规格，所有调用点都从中选一。

本文件列出该版本里的全部动效与反馈，写明 Flutter 版的对等实现，并注明哪些
经过录屏核对。英文版：[MOTION-PARITY.md](MOTION-PARITY.md)。

## 时间参数

Compose 用弹簧。Flutter 的 `AnimationController` 需要时长和曲线，所以
`lib/src/motion.dart` 保留同一条弹簧：prism_ui 的 `SpringCurve` 采样物理
曲线，时长取弹簧稳定到 0.1% 以内的时间（与 Compose 的时长估算一致）。

| 档位 | Kotlin | 弹簧（阻尼 / 刚度） | Flutter | 用途 |
| --- | --- | --- | --- | --- |
| 慢空间 | `Motion.slow()` | 0.8 / 200 → 600 ms | `motion.dart:33` | 页面滑动、标签页滑动、尺寸变化 |
| 快空间 | `Motion.fast()` | 0.6 / 800 → 360 ms | `motion.dart:36` | 短距离位移 |
| 默认淡入 | `Motion.fade()` | 1.0 / 1600 → 230 ms | `motion.dart:39` | 淡入淡出、颜色变化 |
| 快速淡出 | `Motion.fadeFast()` | 1.0 / 3800 → 150 ms | `motion.dart:42` | 离场元素 |
| 慢速淡入 | `Motion.fadeSlow()` | 1.0 / 800 → 330 ms | `motion.dart:45` | Kotlin 版暂未使用 |
| animateFloatAsState 默认 | `spring()` | 1.0 / 1500 → 240 ms | `motion.dart:49` | 箭头旋转 |
| animateItem 归位 | `spring(0.8, 380)` | 0.8 / 380 → 450 ms | `motion.dart:53` | 列表行的加入与移除 |

Flutter 侧全部走 `context.motionDuration(spec)`（`prism_ui`），因此系统开启
“减少动态效果”时长归零；循环动效（脉冲、旋转）保持静止。

## 清单

状态：**已对齐** = 时长与 Kotlin 一致，并在录屏中核对过；**Partial** = 有实现
但差异已在本表写明；**Missing** = Flutter 界面里还没有。

| # | Kotlin（文件:行） | 动效与触发 | 时长 / 曲线 | Flutter 对应 | 状态 |
| --- | --- | --- | --- | --- | --- |
| 1 | `MainActivity.kt:92` | 前进：新页面从 1/5 宽度处滑入 + 淡入 | 慢空间 | `motion.dart:117` `MotionSwitcher`（`shell.dart:510`） | 已对齐 |
| 2 | `MainActivity.kt:93` | 前进：旧页面滑到 -1/10 并淡出 | 慢空间 / 快速淡出 | 同上 | 已对齐 |
| 3 | `MainActivity.kt:94` | 返回：页面从 -1/10 滑入 + 淡入 | 慢空间 | 同上，`forward: false` | 已对齐 |
| 4 | `MainActivity.kt:95` | 返回：页面滑到 1/5 并淡出 | 慢空间 / 快速淡出 | 同上 | 已对齐 |
| 5 | `MainActivity.kt:99` | 登录路由淡入淡出 | 慢空间 / 快速淡出 | 同上，场景 `login` | 已对齐 |
| 6 | `MainActivity.kt:107` | 登录完成：外壳淡入并从 0.96 放大 | 慢空间 | `MotionSwitcher(fadeThrough: true)`（`shell.dart:513`） | 已对齐 |
| 7 | `HomeScreen.kt:152` | 切换标签：滑动 1/8 页宽并交叉淡化 | 入：慢空间；出：快空间 | `shell.dart:169` + `_TabPage`（`shell.dart:624`） | Partial — Kotlin 主页需要 tailnet，只录了本版本 |
| 8 | `LoginScreen.kt:162` | 登录阶段切换：淡入 + 垂直滑动 1/6 + 尺寸过渡 | 慢空间 | `login.dart:520` `_StageSwap` | 已对齐 |
| 9 | `LoginScreen.kt:129` | “高级”区域展开/收起 | 默认规格 | `login.dart:436` `ExpandVisibility` | 已对齐 |
| 10 | `NodeScreen.kt:183` | Ping 结果行展开并淡入 | 慢空间 + 淡入 | `node_detail.dart:248` | Partial — 只在本地预览录到（无对端可 ping） |
| 11 | `NodeScreen.kt:184` | Ping 文本状态间交叉淡化 | 淡入 / 快速淡出 | `node_detail.dart:602` `FadeThrough` | Partial — 同上 |
| 12 | `NodeScreen.kt:224` | 端口扫描结果加入列表并改变高度 | animateItem + 内容尺寸 | `node_detail.dart:259`（只有展开，无行动画） | Partial |
| 13 | `TerminalScreen.kt:273` | SSH 状态副标题交叉淡化 | 淡入 / 快速淡出 | `terminal.dart:545` | Partial — 会话状态需要 tailnet |
| 14 | `TerminalScreen.kt:279` | 重连按钮淡入 + 从 0.8 放大 | 默认淡入 | — | Missing — Flutter 终端没有重连按钮 |
| 15 | `TerminalScreen.kt:282` | Agents 按钮淡入 + 从 0.6 放大 | 快速淡出 | — | Missing |
| 16 | `WebScreen.kt:190` | 可后退时返回箭头淡入 | 默认淡入 | `web_view.dart:157` | Partial — 需要真实页面 |
| 17 | `WebScreen.kt:216` | 页面加载进度条淡入淡出 | 默认淡入 | `web_view.dart:178` | Partial — 同上 |
| 18 | `AgentsUi.kt:199` | 节点页的 herdr 概要卡展开 | 默认展开 + 淡入 | — | Missing — Flutter 节点页没有概要卡 |
| 19 | `AgentsUi.kt:259` | herdr 就绪时新建 Agent 悬浮按钮淡入展开 | 默认规格 | — | Missing — Flutter 把 “+” 放在页头 |
| 20 | `AgentsUi.kt:279` | Agent 列表在 herdr 状态间切换 | 默认 AnimatedContent | `agents.dart:98`（行有动画，状态切换瞬时） | Partial |
| 21 | `AgentsUi.kt:639` | 页头状态文字交叉淡化 | 默认 AnimatedContent | `agent_chat.dart:490` | 已对齐 |
| 22 | `AgentsUi.kt:749` | 输入区切换为“被阻塞”提示面板，垂直滑动 1/3 | 默认规格 | — | Missing — Flutter 聊天没有被阻塞面板 |
| 23 | `AgentsUi.kt:845` | 回到底部按钮淡入并放大 | 默认淡入 | — | Missing — Flutter 聊天始终停在底部 |
| 24 | `AgentExtras.kt:518` | 子 Agent 数量胶囊淡入 | 默认淡入 | — | Missing — 没有数量胶囊 |
| 25 | `AgentExtras.kt:217`、`:254`、`:324`、`AgentTimeline.kt:246`、`:448`、`AgentsUi.kt:765`、`:982`、`SettingsScreen.kt:94`、`NodeScreen.kt:224` | 内容随布局增减尺寸 | 慢空间 | `motion.dart:61` `AnimatedContentSize`（`login.dart:528`、`node_detail.dart:248`） | Partial — 只用在展开的区块上，聊天记录不做尺寸动画 |
| 26 | `Expressive.kt:198`、`HomeScreen.kt:272`、`AgentsUi.kt:289`、`:711`、`NodeScreen.kt:224` | 列表行加入时归位、移除时收起 | animateItem（淡入 + 归位弹簧） | `controls.dart:179` `AnimatedGroupCard` | 已对齐 |
| 27 | `AgentTimeline.kt:244`、`:445` | 工具组与待办箭头旋转 180° | `animateFloatAsState` 默认 | — | Missing — Flutter 聊天没有可折叠工具组和待办 |
| 28 | `AgentsUi.kt:977` | 可展开卡片：箭头旋转、内容改变高度 | 默认 | — | Missing |
| 29 | `HomeScreen.kt:126` | 节点启动时的波浪线性进度 | Material 3 波浪，淡入淡出 | — | Missing — 本版本改用状态文字 |
| 30 | `AgentDialogs.kt:145`、`AgentExtras.kt:188`、`:591`、`:746`、`:889`、`:971`、`:1000`、`AgentTimeline.kt:202`、`:253`、`AgentsUi.kt:306`、`:694`、`HomeScreen.kt:221`、`NodeScreen.kt:174`、`:205` | Material 3 波浪加载指示器 | 1 秒循环 | prism `ActivityIndicator`（`third_party/prism_ui/lib/loading.dart:28`） | Partial — 是圆弧转圈，不是波浪 |
| 31 | `Expressive.kt:113` | 工作中的徽标每 9 秒转一圈 | 线性 | — | Missing — Flutter 徽标是静态的 |
| 32 | `Expressive.kt:99` | 状态变化时徽标多边形变形 | 慢空间 | — | Missing — Flutter 徽标没有多边形 |
| 33 | `Expressive.kt:110` | 徽标底色随状态淡变 | 默认淡入 | `motion.dart:264` `PulsingDot` 只淡变圆点颜色 | Partial |
| 34 | `AgentsUi.kt:174` | 工作中/被阻塞时状态点 0.35 → 1 脉冲 | 700 ms 往返 | `foundation.dart:339`（`StatusPill(dot: true, pulse: true)`） | Partial — 已实现，未录到（需要在线 Agent） |
| 35 | `AgentExtras.kt:486` | 三个“输入中”圆点轮流亮起 | 600 ms，错开 160 ms，往返 | — | Missing — Flutter 聊天没有工作条可以承载 |
| 36 | `Common.kt:31` | 节点状态点在线/离线颜色淡变 | 默认淡入 | `foundation.dart:339` `PulsingDot` 颜色补间 | 已对齐 |
| 37 | `Common.kt:112`、`HomeScreen.kt:186`、`AgentsUi.kt:246` | 下拉刷新，最少转 500–600 ms | Material 3 下拉刷新 | `foundation.dart:24` + `nodes.dart:33`、`agents.dart:101` | Partial — 用 Material `RefreshIndicator`（圆形），不是波浪 |
| 38 | 所有 `clickable`/`Surface(onClick)` | 按下时的水波与状态层 | Material 3 | prism `PressRegion` 的着色 | Partial — 是平铺着色，不是水波 |
| 39 | 所有 `IconButton(shapes = …)`、`Button(shapes = …)` | Expressive 按下形变：容器轻微压缩 | Material 3 默认 | `controls.dart:50` `TapFeedback(scale: true)`（0.97） | Partial |
| 40 | `AgentsUi.kt:1070` | 长按“立即发送”触发长按振动 | — | `agent_chat.dart:234`、`:722`（`HapticFeedback.mediumImpact`） | Partial — 需要在线 Agent 才能长按 |
| 41 | `TerminalView.kt:382` | 长按选词并触发长按振动 | — | — | Missing — Flutter 终端没有选择手势 |
| 42 | `TerminalView.kt:603` | 终端响铃触发按键振动 | — | — | Missing — Flutter 终端没有暴露响铃事件 |
| 43 | `AgentsUi.kt:474`、`:501`、`:531`、`:589`、`:761`、`WebScreen.kt:135` | Snackbar 滑入、停留、滑出 | Material 3 | 原地 `InlineNotice` | Missing — 本版本在页面内提示，不用 Snackbar |
| 44 | `AgentExtras.kt` 各 sheet、`AgentDialogs.kt` | 底部弹层与对话框滑入并缩放 | Material 3 | prism 弹层与对话框 | Partial — 用的是 prism 动效 |

合计 44 项：已对齐 9，Partial 18，Missing 17。

## 证据

`docs/motion/` 放的是 `tool/motion_record.sh`（手动工作流 `motion-record.yml`）
录下的片段。左边 Kotlin，右边本版本，每边 404 px，时长 3–8 秒。

| 片段 | 内容 |
| --- | --- |
| `login-expand.mp4` | “高级 / 控制服务器”区域展开与收起 |
| `login-start.mp4` | 登录进入启动中状态（转圈、阶段切换） |
| `press.mp4` | 长按按钮时的按下反馈 |

Kotlin 版在没有 tailnet 时始终停在登录页（要控制服务器接受后才会离开），
因此第 7、10–13、16–17、20–24、27–28、34、40 项只录到本版本或无法录制，
标为 Partial / Missing 而不是已对齐。

## 重新录制

```bash
gh workflow run motion-record.yml --ref <branch>   # 然后下载 motion 产物
```

`tool/motion_record.sh <flutter.apk> <kotlin.apk>` 也可以在任意已连接设备上跑，
需要 `adb`、`ffmpeg`，并把动画时长倍率保持为 1。
