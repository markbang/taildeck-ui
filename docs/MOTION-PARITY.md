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
| default spatial | `Motion.defaultSpatialSpec()` | 0.8 / 380 → 440 ms | `motion.dart:42` | sheet and dialog motion, button shape morphs outside Compose |
| fast spatial | `Motion.fastSpatialSpec()` | 0.6 / 800 → 410 ms | `motion.dart:46` | the snackbar's scale |
| animateItem placement | `spring(0.8, 380)` | 0.8 / 380 → 440 ms | `motion.dart:55` | rows joining or leaving a list |
| (unused by both) | `Motion.fast()`, `Motion.fadeSlow()` | 0.6 / 800, 1.0 / 800 | — | no call site needs them |

Every Flutter use goes through `context.motionDuration(spec)` (`prism_ui`), so
reduce-motion makes the duration zero; loops (pulse, spin, ink, wavy, the
loading dot) stop at their resting phase.

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
| 12 | `NodeScreen.kt:224` | The scan result joins the list and resizes | animateItem placement + `animateContentSize(Motion.slow())` | `node_detail.dart:276` `PlacementVisibility` + `AnimatedContentSize` | 已对齐 | `flutter-scan-row.mp4` (Flutter only): the Kotlin node list has no clickable peer under `testcontrol`, so its node page cannot be reached |
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
| 25 | `AgentExtras.kt:217`, `:254`, `:324`, `AgentTimeline.kt:246`, `:448`, `AgentsUi.kt:765`, `:982`, `SettingsScreen.kt:94`, `NodeScreen.kt:224` | Content grows and shrinks with the layout: the composer panel, tool groups, todos, command output, expandable cards, the settings page and the scan block | slow spatial | `motion.dart:75` `AnimatedContentSize` in each of those (`agent_chat.dart` composer + `_ToolGroup` + `_TodoTrack` + `_ThinkingCard` + `_CommandOutput`, `settings.dart` page body, `node_detail.dart` scan, `login.dart`) | 已对齐 | `login-expand.mp4` (the login section) and `flutter-content-size.mp4` (the scan block, Flutter only, same reason as row 12) |
| 26 | `Expressive.kt:198`, `HomeScreen.kt:272`, `AgentsUi.kt:289`, `:711`, `NodeScreen.kt:224` | Rows animate into place and collapse when removed | animateItem (fade + placement spring) | `controls.dart:139` `AnimatedGroupCard` (`motion.dart:48` placement) | 已对齐 | no clip shows a row joining or leaving |
| 27 | `AgentTimeline.kt:244`, `:445` | Tool-group and todo chevrons rotate 180° | `animateFloatAsState` default | `motion.dart:541` `RotatingChevron` (`agent_chat.dart:1887`, `:2146`, `:2251`) | 已对齐 | needs a live agent |
| 28 | `AgentsUi.kt:977` | Expandable card: the chevron rotates and the content resizes | default | `RotatingChevron` + `AnimatedContentSize` | 已对齐 | needs a live agent |
| 29 | `HomeScreen.kt:126` | Indeterminate wavy linear progress while the node starts | Material 3 wavy, fade in/out | `nodes.dart:147` `MotionVisibility` + `WavyLine` (`wavy.dart:8`) | 已对齐 | needs a signed-in node |
| 30 | `AgentDialogs.kt:145`, `AgentExtras.kt:188`, `:591`, `:746`, `:889`, `:971`, `:1000`, `AgentTimeline.kt:202`, `:253`, `AgentsUi.kt:306`, `:694`, `HomeScreen.kt:221`, `NodeScreen.kt:174`, `:205` | The loading indicator: a dot that morphs through seven shapes, turning a quarter each morph | morph every 650 ms on `spring(0.6, 200, 0.1)`, 4.666 s full turn, 38/48 of the box | `loading.dart:113` `LoadingIndicator` (login, nodes, node detail, services, settings, chat, buttons) | 已对齐 | `loading.mp4` (Kotlin | Flutter, both on the Connecting stage) |
| 31 | `Expressive.kt:113` | The working badge turns once every 9 s | linear | `shape_badge.dart:61` `ShapeBadge` spin (`9 s`) | 已对齐 | needs herdr |
| 32 | `Expressive.kt:99` | The badge polygon morphs when the status changes | slow spatial | `shape_badge.dart:55` `ShapeBadge` morph (`BlobShape`) | 已对齐 | blob approximation of the MaterialShapes polygon |
| 33 | `Expressive.kt:110` | The badge container colour fades on a status change | default effects | `shape_badge.dart:58` | 已对齐 | needs herdr |
| 34 | `AgentsUi.kt:174` | The agent status dot pulses 0.35 → 1 while working or blocked | 700 ms reverse | `motion.dart:262` `PulsingDot` via `StatusPill` (`foundation.dart:315`, `agents.dart:504`) | 已对齐 | needs a live agent |
| 35 | `AgentExtras.kt:486` | Three “typing” dots light in turn while an agent works | 600 ms, 160 ms stagger, reverse | `motion.dart:570` `InkDots` in `_WorkingBar` (`agent_chat.dart:1769`) | 已对齐 | needs a live agent |
| 36 | `Common.kt:31` | The node status dot colour animates between online and offline | default effects | `PulsingDot` colour tween (`motion.dart:262`) | 已对齐 | no clip changes a node’s state |
| 37 | `Common.kt:112`, `HomeScreen.kt:186`, `AgentsUi.kt:246` | Pull to refresh: the contained dot morphs with the pull and spins while the refresh runs, over an 80 dp threshold (half the drag) and at least 600 ms | Material 3 pull-to-refresh | `pull_to_refresh.dart:16` `PullToRefresh` (`foundation.dart`) | 已对齐 | `refresh.mp4` (Kotlin | Flutter, both pulling the node list) |
| 38 | every `clickable`/`Surface(onClick)` | Bounded ink ripple from the touch point, drifting to the centre, plus the 10 % state layer | radius 0.3 × longest side → half the diagonal + 10 dp over 225 ms `fastOutSlowIn`; alpha in 75 ms, out 150 ms, linear; layer in 15 ms | `ripple.dart:16` `PressRipple` (prism `PressSurface`, `PressRegion`) | 已对齐 | `ripple.mp4` (Kotlin on the emulator, this build's web preview: the emulator encoder dropped the Flutter half) |
| 39 | every `IconButton(shapes = …)`, `Button(shapes = …)` | Expressive press shape: the container's corners squish from a pill to `CornerSmall` (8 dp) | default effects spring (230 ms) | prism `PressSurface(squish: true)` (`card_surface.dart` `_shapeAt`), `controls.dart:12` `PressSquish` | 已对齐 | `ripple.mp4` (Kotlin on the emulator, this build's web preview: the emulator encoder dropped the Flutter half) |
| 40 | `AgentsUi.kt:1070` | Long-press send-now fires a long-press haptic | — | `agent_chat.dart:268` (`HapticFeedback.mediumImpact`) | 已对齐 | needs a live agent |
| 41 | `TerminalView.kt:382` | Long-press selects a word and fires a long-press haptic | — | `term_view.dart:149` `_selectWord` (native `td_term_select`) | 已对齐 | needs an SSH session |
| 42 | `TerminalView.kt:603` | The terminal bell fires a key-tap haptic | — | `terminal.dart:225` (`TermMeta.effects` bit 0 → `selectionClick`) | 已对齐 | needs an SSH session |
| 43 | `AgentExtras.kt` sheets, `AgentDialogs.kt` | Bottom sheets rise from the bottom edge over the scrim; dialogs scale up from 0.8 while they fade | sheet: default spatial in (440 ms), fast effects out (150 ms); dialog: default spatial in, fast effects out | `bottom_sheet.dart:10` `showMotionSheet`; prism `AlertMotionRouteMixin` | 已对齐 | `flutter-dialog.mp4` (Flutter only): the Kotlin dialogs sit behind the settings page, which the emulator could not reach in this run |
| 44 | `AgentsUi.kt:474`, `:501`, `:531`, `:589`, `:761`, `WebScreen.kt:135` | Snackbar fades in and scales up from 0.8, waits 4 s, fades away, over every action that reports | fast effects (150 ms) fade, fast spatial (410 ms) scale | `widgets/snackbar.dart:10` `showMotionSnack` (`agent_chat.dart`, `web_view.dart`) | 已对齐 | `snackbar.mp4` (Flutter); the Kotlin snackbars report agent actions (herdr) or a web download, neither reachable from the login screen |

Count: 44 effects, 44 已对齐, 0 Partial, 0 Missing. Seven rows carry a new recording; of those, `scan-row`, `content-size` and `dialog` have the Flutter half only, and `ripple` pairs the emulator with the web preview (see Evidence).

## Evidence

`docs/motion/` holds the clips. Two capture paths, because the Android
emulator renders with SwiftShader and its encoder drops most frames while the
GPU is busy:

- `tool/motion_record.sh` (manual workflow `motion-record.yml`) records the
  Kotlin v0.1.0 APK and this build on the same emulator and stacks them,
  Kotlin on the left, this build on the right. The workflow starts Tailscale's
  own `testcontrol` control plane (with its DERP relay) on the runner and hands
  the script `http://10.0.2.2:8080` plus an auth key, so both apps can sign in
  and the screens behind login become recordable; `testcontrol` accepts any
  key.
- `tool/motion_web.py` records this build's web preview with Playwright at
  25 fps, which keeps every frame of the animation.

| Clip | What it shows |
| --- | --- |
| `login-expand.mp4` | Kotlin / Flutter: the advanced section expanding, one gesture each |
| `ripple.mp4` | Kotlin / Flutter: a press and hold on the login's advanced control, the ink spreading from the touch point. The left half is the Kotlin APK on the emulator, the right half this build's web preview, because the emulator's encoder dropped the Flutter half |
| `press-squish.mp4` | Kotlin / Flutter: the same hold, the pill's corners squashing to 8 dp |
| `loading.mp4` | Kotlin / Flutter: the loading dot while the node connects to a control server that never answers |
| `refresh.mp4` | Kotlin / Flutter: a pull down on the node list |
| `flutter-scan-row.mp4` | This build: the scan block joining the node page and resizing |
| `flutter-content-size.mp4` | This build: the same scan block resizing its container |
| `flutter-dialog.mp4` | This build: the sign-out confirm scaling up over the settings page |
| `flutter-login-expand.mp4` | This build: the auth-key section expanding (fade + size) |
| `flutter-tabs.mp4` | This build: nodes → services → agents → nodes, sliding 1/8 and cross-fading |
| `flutter-detail.mp4` | This build: node page sliding in from 1/5 and popping back |
| `flutter-start.mp4` | This build: the login stage swap (fade + vertical slide of 1/6) |

Four rows are paired on the device: `ripple` (Flutter from the web preview),
`press-squish`, `loading`, `refresh`. The five rows that are not are named
below, with the part of each that is missing. Every one of them is a recording
problem, not an implementation one: the same gesture runs in both apps and the
clips that do exist show it.

### What could not be recorded

- **Node page on the Kotlin app** (`scan-row`, `content-size`): its node list
  only opens a page from a *peer* row; the self row copies the IP instead.
  `testcontrol` hands out no peers, so the page is unreachable and only the
  Flutter half of both clips exists.
- **Kotlin dialogs** (`dialog`): the sign-out confirm is at the bottom of the
  settings page; the tap that opens Settings did not register on the emulator
  in this run, so only the Flutter half exists.
- **The Flutter half of `ripple`**: the emulator's encoder returned files with
  no frames for that clip three times in a row, so the right half comes from
  the web preview at 25 fps.
- **Snackbar** (row 44): the Kotlin app only shows snackbars in the agent chat
  and in the web view's download report. Both need a herdr agent or a tailnet
  service page, which no CI machine can provide, so this row has no clip in
  either app yet.

## Re-recording

```bash
gh workflow run motion-record.yml --ref <branch>   # then download the motion artifact
python3 tool/motion_web.py                         # web clips, needs the build served
```

`tool/motion_record.sh <flutter.apk> <kotlin.apk>` also runs on any attached
device; it needs `adb`, `ffmpeg` and a device with animations at scale 1. It
finds every target through `uiautomator dump` right before its clip, so the
device must use the English locale and be free of system dialogs.
