# Motion parity with the Kotlin app

The Kotlin app (`markbang/taildeck`) runs on Material 3 Expressive motion
(`MaterialExpressiveTheme(motionScheme = MotionScheme.expressive())`,
`ui/Theme.kt:46`). Its `Motion` object (`ui/Theme.kt:49`) exposes the specs from
material3 1.5.0-alpha14, and every call site picks one of them.

This file inventories every motion and feedback effect in that app, names the
Flutter implementation, and says what could be verified by recording. Chinese
version: [MOTION-PARITY.zh-CN.md](MOTION-PARITY.zh-CN.md).

## Tokens

Compose plays these as springs. Flutter's `AnimationController` wants a
duration and a curve, so `lib/src/motion.dart` keeps the same spring: the
`SpringCurve` in prism_ui samples the physics, and the duration is the time the
spring needs to settle within 0.1% (what Compose's duration estimate reports).

| Token | Kotlin | Spring (damping / stiffness) | Flutter | Used for |
| --- | --- | --- | --- | --- |
| slow spatial | `Motion.slow()` | 0.8 / 200 → 600 ms | `motion.dart:34` | page slides, tab slide, size changes |
| default effects | `Motion.fade()` | 1.0 / 1600 → 230 ms | `motion.dart:37` | fades, colour changes |
| fast effects | `Motion.fadeFast()` | 1.0 / 3800 → 150 ms | `motion.dart:40` | things leaving |
| animateFloatAsState default | `spring()` | 1.0 / 1500 → 240 ms | `motion.dart:44` | chevron rotations |
| animateItem placement | `spring(0.8, 380)` | 0.8 / 380 → 450 ms | `motion.dart:48` | rows joining or leaving a list |
| (unused by both) | `Motion.fast()`, `Motion.fadeSlow()` | 0.6 / 800, 1.0 / 800 | — | no call site needs them |

Every Flutter use goes through `context.motionDuration(spec)` (`prism_ui`), so
reduce-motion makes the duration zero; loops (pulse, spin, ink, wavy) stop at
their resting phase.

## Inventory

Status: **已对齐** = the Flutter call site uses the same trigger, spring token
and exit spec as the Kotlin one; **Partial** = implemented, with the difference
named; **Missing** = not implemented. The evidence column says which clip in
`docs/motion/` shows it, or why it could not be recorded without a tailnet.

| # | Kotlin (file:line) | Effect, trigger | Duration / curve | Flutter counterpart | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `MainActivity.kt:92` | Push: the new page slides in from 1/5 of the width while it fades | slow spatial | `motion.dart:112` `MotionSwitcher` (`shell.dart:537`) | 已对齐 | `flutter-detail.mp4` (this build) |
| 2 | `MainActivity.kt:93` | Push: the old page slides to -1/10 and fades out | slow spatial, fast effects | same `MotionSwitcher` | 已对齐 | `flutter-detail.mp4` |
| 3 | `MainActivity.kt:94` | Back: the page slides in from -1/10 while it fades | slow spatial | same, `forward: false` | 已对齐 | `flutter-detail.mp4` |
| 4 | `MainActivity.kt:95` | Back: the page slides out to 1/5 and fades | slow spatial, fast effects | same | 已对齐 | `flutter-detail.mp4` |
| 5 | `MainActivity.kt:99` | The login route fades in and out | slow spatial / fast effects | same, scene `login` | 已对齐 | not recorded (needs a signed-out start) |
| 6 | `MainActivity.kt:107` | Signed in: the shell fades in over login and scales up from 0.96 | slow spatial | `MotionSwitcher(fadeThrough: true)` (`shell.dart:539`) | 已对齐 | not recorded (needs a sign-in) |
| 7 | `HomeScreen.kt:152` | Tab switch: slide 1/8 of the width and cross-fade | slow spatial in, fast spatial out | `shell.dart:172` + `_TabPage` (`shell.dart:646`) | 已对齐 | `flutter-tabs.mp4` |
| 8 | `LoginScreen.kt:162` | Login stage swap: fade + vertical slide of 1/6 + size transform | slow spatial | `login.dart:526` `_StageSwap` | 已对齐 | `flutter-start.mp4` |
| 9 | `LoginScreen.kt:129` | The advanced section expands and shrinks | default specs | `login.dart:445` `ExpandVisibility` | 已对齐 | `login-expand.mp4` (Kotlin | Flutter) |
| 10 | `NodeScreen.kt:183` | The ping result row expands and fades in | slow spatial + fade | `node_detail.dart:265` `ExpandVisibility` | 已对齐 | not recordable (no peer to ping) |
| 11 | `NodeScreen.kt:184` | The ping text cross-fades between states | fade / fast effects | `node_detail.dart:619` `FadeThrough` | 已对齐 | not recordable (no peer to ping) |
| 12 | `NodeScreen.kt:224` | The scan result joins the list and resizes | animateItem + content size | `node_detail.dart:276` `ExpandVisibility` (no item animation) | Partial | not recordable (no peer) |
| 13 | `TerminalScreen.kt:273` | The SSH status subtitle cross-fades | fade / fast effects | `terminal.dart:585` `FadeThrough` | 已对齐 | needs a tailnet |
| 14 | `TerminalScreen.kt:279` | The reconnect action appears with a fade and scales from 0.8 | default fade | `terminal.dart:598` `MotionVisibility` | 已对齐 | needs a tailnet |
| 15 | `TerminalScreen.kt:282` | The agents action appears with a fade and scales from 0.6 | fast effects | `terminal.dart:614` `MotionVisibility` | 已对齐 | needs a tailnet |
| 16 | `WebScreen.kt:190` | The back arrow fades in when the page can go back | default fade | `web_view.dart:157` `ExpandVisibility` | 已对齐 | needs a live page |
| 17 | `WebScreen.kt:216` | The page-load progress bar fades in and out | default fade | `web_view.dart:178` `ExpandVisibility` | 已对齐 | needs a live page |
| 18 | `AgentsUi.kt:199` | The herdr summary card expands on the node page | default expand + fade | `node_detail.dart:691` `MotionVisibility` + `:709` `ShapeBadge` | 已对齐 | needs herdr |
| 19 | `AgentsUi.kt:259` | The new-agent action fades and expands in once herdr is ready | default specs | `agents.dart:360` `_NewAgentFab` | 已对齐 | needs herdr |
| 20 | `AgentsUi.kt:279` | The agent list swaps between herdr states | default AnimatedContent | `agents.dart:121` `ScaleFadeSwitcher` | 已对齐 | needs herdr |
| 21 | `AgentsUi.kt:639` | The header status label cross-fades | default AnimatedContent | `agent_chat.dart:529` `FadeThrough` | 已对齐 | needs a live agent |
| 22 | `AgentsUi.kt:749` | The composer swaps to the blocked panel with a vertical slide of 1/3 | default specs | `agent_chat.dart:858` `SlideFadeSwitcher` | 已对齐 | needs a live agent |
| 23 | `AgentsUi.kt:845` | The scroll-to-bottom button fades and scales in | default fade | `agent_chat.dart:1700` `_ScrollToBottom` | 已对齐 | needs a live agent |
| 24 | `AgentExtras.kt:518` | The subagent count chip fades in above the composer | default fade | `agent_chat.dart:1784` `MotionVisibility` in `_WorkingBar` | 已对齐 | needs a live agent |
| 25 | `AgentExtras.kt:217`, `:254`, `:324`, `AgentTimeline.kt:246`, `:448`, `AgentsUi.kt:765`, `:982`, `SettingsScreen.kt:94`, `NodeScreen.kt:224` | Content grows and shrinks with the layout | slow spatial | `motion.dart:56` `AnimatedContentSize` (`agent_chat.dart:1850`, `:2116`, `:2155`, `:2208`, `:2260`, `login.dart:534`) | Partial | the transcript and settings page do not resize |
| 26 | `Expressive.kt:198`, `HomeScreen.kt:272`, `AgentsUi.kt:289`, `:711`, `NodeScreen.kt:224` | Rows animate into place and collapse when removed | animateItem (fade + placement spring) | `controls.dart:139` `AnimatedGroupCard` (`motion.dart:48` placement) | 已对齐 | no clip shows a row joining or leaving |
| 27 | `AgentTimeline.kt:244`, `:445` | Tool-group and todo chevrons rotate 180° | `animateFloatAsState` default | `motion.dart:541` `RotatingChevron` (`agent_chat.dart:1887`, `:2146`, `:2251`) | 已对齐 | needs a live agent |
| 28 | `AgentsUi.kt:977` | Expandable card: the chevron rotates and the content resizes | default | `RotatingChevron` + `AnimatedContentSize` | 已对齐 | needs a live agent |
| 29 | `HomeScreen.kt:126` | Indeterminate wavy linear progress while the node starts | Material 3 wavy, fade in/out | `nodes.dart:147` `MotionVisibility` + `WavyLine` (`wavy.dart:8`) | 已对齐 | needs a signed-in node |
| 30 | `AgentDialogs.kt:145`, `AgentExtras.kt:188`, `:591`, `:746`, `:889`, `:971`, `:1000`, `AgentTimeline.kt:202`, `:253`, `AgentsUi.kt:306`, `:694`, `HomeScreen.kt:221`, `NodeScreen.kt:174`, `:205` | Material 3 wavy loading indicator | 1 s loop | `wavy.dart:128` `WavyActivityIndicator` (login, nodes, node detail, services, settings, chat, buttons) | Partial | an arc rather than the shape-shifting dot |
| 31 | `Expressive.kt:113` | The working badge turns once every 9 s | linear | `shape_badge.dart:61` `ShapeBadge` spin (`9 s`) | 已对齐 | needs herdr |
| 32 | `Expressive.kt:99` | The badge polygon morphs when the status changes | slow spatial | `shape_badge.dart:55` `ShapeBadge` morph (`BlobShape`) | 已对齐 | blob approximation of the MaterialShapes polygon |
| 33 | `Expressive.kt:110` | The badge container colour fades on a status change | default effects | `shape_badge.dart:58` | 已对齐 | needs herdr |
| 34 | `AgentsUi.kt:174` | The agent status dot pulses 0.35 → 1 while working or blocked | 700 ms reverse | `motion.dart:262` `PulsingDot` via `StatusPill` (`foundation.dart:315`, `agents.dart:504`) | 已对齐 | needs a live agent |
| 35 | `AgentExtras.kt:486` | Three “typing” dots light in turn while an agent works | 600 ms, 160 ms stagger, reverse | `motion.dart:570` `InkDots` in `_WorkingBar` (`agent_chat.dart:1769`) | 已对齐 | needs a live agent |
| 36 | `Common.kt:31` | The node status dot colour animates between online and offline | default effects | `PulsingDot` colour tween (`motion.dart:262`) | 已对齐 | no clip changes a node’s state |
| 37 | `Common.kt:112`, `HomeScreen.kt:186`, `AgentsUi.kt:246` | Pull to refresh with a minimum 500–600 ms spinner | Material 3 pull-to-refresh | `foundation.dart:25` + `nodes.dart:35`, `agents.dart:105` | Partial | Material `RefreshIndicator` (circular), not the wavy one |
| 38 | every `clickable`/`Surface(onClick)` | Ripple and state layer on press | Material 3 | prism `PressRegion` tint | Partial | a flat tint, not a ripple |
| 39 | every `IconButton(shapes = …)`, `Button(shapes = …)` | Expressive press shape: the container squishes | Material 3 default | `controls.dart:53` `TapFeedback(scale: true)` (0.97) | Partial | — |
| 40 | `AgentsUi.kt:1070` | Long-press send-now fires a long-press haptic | — | `agent_chat.dart:268` (`HapticFeedback.mediumImpact`) | 已对齐 | needs a live agent |
| 41 | `TerminalView.kt:382` | Long-press selects a word and fires a long-press haptic | — | `term_view.dart:149` `_selectWord` (native `td_term_select`) | 已对齐 | needs an SSH session |
| 42 | `TerminalView.kt:603` | The terminal bell fires a key-tap haptic | — | `terminal.dart:225` (`TermMeta.effects` bit 0 → `selectionClick`) | 已对齐 | needs an SSH session |
| 43 | `AgentExtras.kt` sheets, `AgentDialogs.kt` | Bottom sheets and dialogs slide and scale in | Material 3 | prism sheets and dialogs | Partial | prism motion, not Material |
| 44 | `AgentsUi.kt:474`, `:501`, `:531`, `:589`, `:761`, `WebScreen.kt:135` | Snackbar slides in, waits and slides out | Material 3 | `widgets/snackbar.dart:10` `showMotionSnack` (`agent_chat.dart:129`) | Partial | the web view still reports in the page |

Count: 44 effects, 36 已对齐, 8 Partial, 0 Missing.

## Evidence

`docs/motion/` holds the clips. Two capture paths, because the Android
emulator renders with SwiftShader and its encoder drops most frames while the
GPU is busy:

- `tool/motion_record.sh` (manual workflow `motion-record.yml`) records the
  Kotlin v0.1.0 APK and this build on the same emulator and stacks them,
  Kotlin on the left, this build on the right. `login-expand.mp4` is the one
  effect both apps can reach without a tailnet.
- `tool/motion_web.py` records this build's web preview with Playwright at
  25 fps, which keeps every frame of the animation.

| Clip | What it shows |
| --- | --- |
| `login-expand.mp4` | Kotlin / Flutter: the advanced section expanding, one gesture each |
| `flutter-login-expand.mp4` | This build: the auth-key section expanding (fade + size) |
| `flutter-tabs.mp4` | This build: nodes → services → agents → nodes, sliding 1/8 and cross-fading |
| `flutter-detail.mp4` | This build: node page sliding in from 1/5 and popping back |
| `flutter-start.mp4` | This build: the login stage swap (fade + vertical slide of 1/6) |

The Kotlin app cannot leave its login screen without a tailnet (it starts on
login until a control server accepts it), so the rows that need home, node,
agent, chat or SSH screens are marked with the evidence they need instead of a
clip. They are implemented; only the visual comparison is missing.

### What could not be recorded

- Home, node page, agents and chat on the Kotlin app: behind a working control
  server, and the release APK cannot be preseeded.
- Everything that needs a live tailnet: ping, port scan, SSH, herdr, service
  favicons.
- The press clips: the emulator dropped input events often enough that the
  captured presses did not land on the same control twice.

## Re-recording

```bash
gh workflow run motion-record.yml --ref <branch>   # then download the motion artifact
python3 tool/motion_web.py                         # web clips, needs the build served
```

`tool/motion_record.sh <flutter.apk> <kotlin.apk>` also runs on any attached
device; it needs `adb`, `ffmpeg` and a device with animations at scale 1. It
finds every target through `uiautomator dump` right before its clip, so the
device must use the English locale and be free of system dialogs.
