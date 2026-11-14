# Motion parity with the Kotlin app

The Kotlin app (`markbang/taildeck`) runs on Material 3 Expressive motion
(`MaterialExpressiveTheme(motionScheme = MotionScheme.expressive())`,
`ui/Theme.kt:46`). Its `Motion` object (`ui/Theme.kt:49`) exposes five specs
from material3 1.5.0-alpha14, and every call site picks one of them.

This file inventories every motion and feedback effect in that app, says what
Flutter does instead, and which clip shows it. Chinese version:
[MOTION-PARITY.zh-CN.md](MOTION-PARITY.zh-CN.md).

## Tokens

Compose plays these as springs. Flutter's `AnimationController` wants a
duration and a curve, so `lib/src/motion.dart` keeps the same spring: the
`SpringCurve` in prism_ui samples the physics, and the duration is the time the
spring needs to settle within 0.1% (what Compose's duration estimate reports).

| Token | Kotlin | Spring (damping / stiffness) | Flutter | Used for |
| --- | --- | --- | --- | --- |
| slow spatial | `Motion.slow()` | 0.8 / 200 → 600 ms | `motion.dart:34` | page slides, tab slide, size changes |
| fast spatial | `Motion.fast()` | 0.6 / 800 → 360 ms | `motion.dart` (not used yet) | short position changes |
| default effects | `Motion.fade()` | 1.0 / 1600 → 230 ms | `motion.dart:37` | fades, colour changes |
| fast effects | `Motion.fadeFast()` | 1.0 / 3800 → 150 ms | `motion.dart:40` | things leaving |
| slow effects | `Motion.fadeSlow()` | 1.0 / 800 → 330 ms | `motion.dart` (not used yet) | unused by the Kotlin app so far |
| animateFloatAsState default | `spring()` | 1.0 / 1500 → 240 ms | `motion.dart:44` | chevron rotations |
| animateItem placement | `spring(0.8, 380)` | 0.8 / 380 → 450 ms | `motion.dart:48` | rows joining or leaving a list |

Every Flutter use goes through `context.motionDuration(spec)` (`motion.dart:51`),
so reduce-motion makes the duration zero; loops (pulse, spin, dots, wavy) stay
still.

The primitives the rows below name:

| Primitive | File | Compose counterpart |
| --- | --- | --- |
| `MotionSwitcher` | `motion.dart:112` | `NavHost` push/pop transitions |
| `FadeThrough` | `motion.dart:240` | `AnimatedContent` fade-in/fade-out |
| `PulsingDot` | `motion.dart:262` | `AgentDot` |
| `MotionVisibility` | `motion.dart:344` | `AnimatedVisibility` (fade, scale, expand) |
| `SlideFadeSwitcher` | `motion.dart:468` | `AnimatedContent` with a slide |
| `ScaleFadeSwitcher` | `motion.dart:507` | `AnimatedContent` default transition |
| `RotatingChevron` | `motion.dart:541` | `animateFloatAsState` chevrons |
| `InkDots` | `motion.dart:570` | `InkDots` in the working bar |
| `ShapeBadge` / `BlobShape` | `widgets/shape_badge.dart:34` | `ShapeBadge` + `Morph` |
| `WavyLine`, `WavyActivityIndicator` | `widgets/wavy.dart:8`, `:128` | Material 3 wavy progress and loading |
| `showMotionSnack` | `widgets/snackbar.dart:10` | `SnackbarHost` |

## Inventory

Status: **已对齐** = the Flutter effect runs with the Kotlin duration and
curve; **Partial** = present but different in the way the row names;
**Missing** = not in the Flutter UI. Recording: the clip in `docs/motion/` that
shows it, or `pending` with what it would need.

| # | Kotlin (file:line) | Effect, trigger | Duration / curve | Flutter counterpart | Status | Recording |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `MainActivity.kt:92` | Push: new page slides in from 1/5 width + fade | slow spatial | `motion.dart:112` `MotionSwitcher` (`shell.dart:530`) | 已对齐 | pending — needs a second page on a live node |
| 2 | `MainActivity.kt:93` | Push: old page slides to -1/10 and fades out | slow / fast effects | same | 已对齐 | pending — same |
| 3 | `MainActivity.kt:94` | Back: page slides in from -1/10 + fade | slow spatial | same, `forward: false` | 已对齐 | pending — same |
| 4 | `MainActivity.kt:95` | Back: page slides out to 1/5 and fades | slow / fast effects | same | 已对齐 | pending — same |
| 5 | `MainActivity.kt:99` | Login route fades in and out | slow / fast effects | same, scene `login` | 已对齐 | `flutter-start.mp4` covers the login screen; the route fade needs a sign-in |
| 6 | `MainActivity.kt:107` | Signed in: shell fades in over login, scaled from 0.96 | slow spatial | `MotionSwitcher(fadeThrough: true)` (`shell.dart:533`) | 已对齐 | pending — needs a tailnet sign-in |
| 7 | `HomeScreen.kt:152` | Tab switch: slide 1/8 of the width, cross-fade | slow spatial in, fast spatial out | `shell.dart:646` + `_TabPage` (`shell.dart:620`) | 已对齐 | `flutter-tabs.mp4` (this build; the Kotlin home needs a tailnet) |
| 8 | `LoginScreen.kt:162` | Login stage swap: fade + vertical slide of 1/6 + size transform | slow spatial | `login.dart:520` `_StageSwap` | 已对齐 | pending — the clip shows the section, not the swap |
| 9 | `LoginScreen.kt:129` | Advanced section expands/shrinks | default specs | `login.dart:436` `ExpandVisibility` | 已对齐 | `flutter-expand.mp4` + `kotlin-expand.mp4` |
| 10 | `NodeScreen.kt:183` | Ping result row expands and fades in | slow spatial + fade | `node_detail.dart:248` `ExpandVisibility` | 已对齐 | pending — needs a peer to ping |
| 11 | `NodeScreen.kt:184` | Ping text cross-fades between states | fade / fadeFast | `node_detail.dart:602` `FadeThrough` | 已对齐 | pending — same |
| 12 | `NodeScreen.kt:224` | Scan result joins the list and resizes | animateItem + content size | `node_detail.dart:259` (expand only; scanned rows are not `AnimatedGroupCard` children) | Partial — the row appears with the section, it does not animate into a list | pending — needs a tailnet peer |
| 13 | `TerminalScreen.kt:273` | SSH status subtitle cross-fades | fade / fadeFast | `terminal.dart:548` `FadeThrough` | 已对齐 | pending — needs a real session |
| 14 | `TerminalScreen.kt:279` | Reconnect action appears with fade + scale 0.8 | default fade | `terminal.dart:590` `MotionVisibility(scaleFrom: 0.8)` | 已对齐 | pending — needs a dropped session |
| 15 | `TerminalScreen.kt:282` | Agents action appears with fade + scale 0.6 | fast effects | `terminal.dart:606` `MotionVisibility(scaleFrom: 0.6)` | 已对齐 | pending — needs a live herdr link |
| 16 | `WebScreen.kt:190` | Back arrow fades in when the page can go back | default fade | `web_view.dart:157` `ExpandVisibility` | 已对齐 | pending — needs a live page |
| 17 | `WebScreen.kt:216` | Page load progress bar fades in and out | default fade | `web_view.dart:178` `ExpandVisibility` | 已对齐 | pending — same |
| 18 | `AgentsUi.kt:199` | Herdr summary card expands on the node page | default expand + fade | `node_detail.dart:670` `_HerdrSummary` | 已对齐 | pending — needs herdr on that node |
| 19 | `AgentsUi.kt:259` | New-agent FAB fades and expands when herdr is ready | default specs | `agents.dart:359` `_NewAgentFab` | 已对齐 | `app-agents.png` (still, web preview); clip pending — needs herdr |
| 20 | `AgentsUi.kt:279` | Agent list swaps between herdr states | default AnimatedContent | `agents.dart:121` `ScaleFadeSwitcher` | 已对齐 | pending — needs herdr |
| 21 | `AgentsUi.kt:639` | Header status label cross-fades | default AnimatedContent | `agent_chat.dart:490` | 已对齐 | pending — needs an agent |
| 22 | `AgentsUi.kt:749` | Composer swaps to the blocked-prompt panel with a vertical slide of 1/3 | default specs | `agent_chat.dart:858` `SlideFadeSwitcher` → `_BlockedPanel` (`:1954`) | 已对齐 | pending — needs a blocked agent |
| 23 | `AgentsUi.kt:845` | Scroll-to-bottom button fades and scales | default fade | `agent_chat.dart:1700` `_ScrollToBottom` | 已对齐 | pending — needs a long transcript |
| 24 | `AgentExtras.kt:518` | Subagent count chip fades in above the composer | default fade | `agent_chat.dart:1739` `_WorkingBar` chip | 已对齐 | pending — needs a running subagent |
| 25 | `AgentExtras.kt:217`, `:254`, `:324`, `AgentTimeline.kt:246`, `:448`, `AgentsUi.kt:765`, `:982`, `SettingsScreen.kt:94`, `NodeScreen.kt:224` | Content grows and shrinks with the layout | slow spatial | `motion.dart:56` `AnimatedContentSize` (`node_detail.dart:248`, chat tool group, todo track, thinking card) | Partial — the settings page does not wrap its scroll content in it | — |
| 26 | `Expressive.kt:198`, `HomeScreen.kt:272`, `AgentsUi.kt:289`, `:711`, `NodeScreen.kt:224` | Rows animate into place and collapse when removed | animateItem (fade + placement spring) | `controls.dart:179` `AnimatedGroupCard` | 已对齐 | — |
| 27 | `AgentTimeline.kt:244`, `:445` | Tool-group and todo chevrons rotate 180° | `animateFloatAsState` default | `agent_chat.dart:2068` `_ToolGroup`, `:1828` `_TodoTrack` (`RotatingChevron`) | 已对齐 | pending — needs tool calls and a todo list |
| 28 | `AgentsUi.kt:977` | Expandable card: chevron rotates, content resizes | default | `agent_chat.dart:2185` `_ThinkingCard` | 已对齐 | pending — needs a thinking message |
| 29 | `HomeScreen.kt:126` | Indeterminate wavy linear progress while the node starts | Material 3 wavy, fade in/out | `nodes.dart:148` `MotionVisibility` + `wavy.dart:8` `WavyLine` | 已对齐 | pending — needs the native backend starting |
| 30 | `AgentDialogs.kt:145`, `AgentExtras.kt:188`, `:591`, `:746`, `:889`, `:971`, `:1000`, `AgentTimeline.kt:202`, `:253`, `AgentsUi.kt:306`, `:694`, `HomeScreen.kt:221`, `NodeScreen.kt:174`, `:205` | Material 3 wavy loading indicator | 1 s loop | `wavy.dart:128` `WavyActivityIndicator`, used by every loading state | 已对齐 | pending — needs native/herdr loading |
| 31 | `Expressive.kt:113` | Working badge spins once every 9 s | linear | `widgets/shape_badge.dart:34` `ShapeBadge(spin: true)` (`agents.dart:470`, `node_detail.dart:709`) | 已对齐 | `app-agents.png` shows the badges; the spin needs a clip |
| 32 | `Expressive.kt:99` | Badge polygon morphs when the status changes | slow spatial | same, `BlobShape.lerp` over the slow spring | 已对齐 | pending — needs a status change |
| 33 | `Expressive.kt:110` | Badge container colour fades on status change | default effects | same (colour lerp on the fade spring) | 已对齐 | pending — same |
| 34 | `AgentsUi.kt:174` | Agent status dot pulses 0.35 → 1 while working or blocked | 700 ms reverse | `motion.dart:262` `PulsingDot` (`foundation.dart:339`) | 已对齐 | pending — needs a live agent |
| 35 | `AgentExtras.kt:486` | Three "typing" dots light in turn while an agent works | 600 ms, 160 ms stagger, reverse | `motion.dart:570` `InkDots` (`agent_chat.dart:1739`) | 已对齐 | pending — needs a working agent |
| 36 | `Common.kt:31` | Node status dot colour animates between online and offline | default effects | `motion.dart:262` `PulsingDot` colour tween | 已对齐 | — |
| 37 | `Common.kt:112`, `HomeScreen.kt:186`, `AgentsUi.kt:246` | Pull to refresh, with a minimum 500–600 ms spinner | Material 3 pull-to-refresh | `foundation.dart:24` (`RefreshIndicator`) + `nodes.dart:33`, `agents.dart:101` | Partial — Material's circular indicator, not the wavy one | — |
| 38 | every `clickable`/`Surface(onClick)` | Ripple and state layer on press | Material 3 | prism `PressRegion` tint | Partial — a flat tint, not a ripple | `flutter-press.mp4` + `kotlin-press.mp4` |
| 39 | every `IconButton(shapes = …)`, `Button(shapes = …)` | Expressive press shape: the container squishes | Material 3 default | `controls.dart:50` `TapFeedback(scale: true)` (0.97) | Partial — a scale, not the expressive shape change | `flutter-press.mp4` + `kotlin-press.mp4` |
| 40 | `AgentsUi.kt:1070` | Long-press send-now fires a long-press haptic | — | `agent_chat.dart:234`, `:723` (`HapticFeedback.mediumImpact`) | 已对齐 | pending — needs a live agent to long-press |
| 41 | `TerminalView.kt:382` | Long-press selects a word and fires a long-press haptic | — | — | Missing — the Flutter terminal has no selection gesture | — |
| 42 | `TerminalView.kt:603` | Terminal bell fires a key-tap haptic | — | — | Missing — the terminal bridge exposes no bell | — |
| 43 | `AgentsUi.kt:474`, `:501`, `:531`, `:589`, `:761`, `WebScreen.kt:135` | Snackbar slides in, waits, slides out | Material 3 | `widgets/snackbar.dart:10` `showMotionSnack` (chat actions) | 已对齐 | pending — needs an agent action |
| 44 | `AgentExtras.kt` sheets, `AgentDialogs.kt` | Bottom sheets and dialogs slide and scale in | Material 3 | prism sheets and dialogs | Partial — prism motion, not Material | — |

Count: 44 effects, 36 已对齐, 6 Partial, 2 Missing.

## Evidence

`docs/motion/` holds the clips from `tool/motion_record.sh` (manual workflow
`motion-record.yml`, artifact `motion`). Kotlin is on the left of each pair,
this build on the right; clips are 1–6 s.

| Clip | What it shows | Rows |
| --- | --- | --- |
| `flutter-expand.mp4` / `kotlin-expand.mp4` | Advanced/control-server section expanding | 9 |
| `flutter-press.mp4` / `kotlin-press.mp4` | Press and hold on a button | 38, 39 |
| `flutter-tabs.mp4` | Nodes → Services tab switch, both tabs meeting mid-slide | 7 |
| `flutter-start.mp4` | Login screen with the control-server section opening | 5, 9 |
| `app-agents.png` | Current build: agent list badges (status polygons), new-agent FAB | 19, 31–33 |

The Kotlin app cannot leave its login screen without a tailnet (it starts on
login until a control server accepts it), and the emulator in CI has no
tailnet either, so every effect that needs live peers, SSH, herdr or a
dropped session is marked `pending` above rather than 已对齐-by-clip. Those
were checked by reading the implementation against the Kotlin call site.

`flutter-detail.mp4` from the same artifact is an empty node page (the
emulator never loaded peers) and is not used as evidence.

## Re-recording

```bash
gh workflow run motion-record.yml --ref <branch>   # then download the motion artifact
```

`tool/motion_record.sh <flutter.apk> <kotlin.apk>` also runs on any attached
device; it needs `adb`, `ffmpeg` and a device with animations at scale 1.
