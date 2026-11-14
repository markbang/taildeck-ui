# Motion parity with the Kotlin app

The Kotlin app (`markbang/taildeck`) runs on Material 3 Expressive motion
(`MaterialExpressiveTheme(motionScheme = MotionScheme.expressive())`,
`ui/Theme.kt:46`). Its `Motion` object (`ui/Theme.kt:49`) exposes five specs
from material3 1.5.0-alpha14, and every call site picks one of them.

This file inventories every motion and feedback effect in that app, says what
Flutter does instead, and records what was verified by screen recording.
Chinese version: [MOTION-PARITY.zh-CN.md](MOTION-PARITY.zh-CN.md).

## Tokens

Compose plays these as springs. Flutter's `AnimationController` wants a
duration and a curve, so `lib/src/motion.dart` keeps the same spring: the
`SpringCurve` in prism_ui samples the physics, and the duration is the time the
spring needs to settle within 0.1% (what Compose's duration estimate reports).

| Token | Kotlin | Spring (damping / stiffness) | Flutter | Used for |
| --- | --- | --- | --- | --- |
| slow spatial | `Motion.slow()` | 0.8 / 200 → 600 ms | `motion.dart:33` | page slides, tab slide, size changes |
| fast spatial | `Motion.fast()` | 0.6 / 800 → 360 ms | `motion.dart:36` | short position changes |
| default effects | `Motion.fade()` | 1.0 / 1600 → 230 ms | `motion.dart:39` | fades, colour changes |
| fast effects | `Motion.fadeFast()` | 1.0 / 3800 → 150 ms | `motion.dart:42` | things leaving |
| slow effects | `Motion.fadeSlow()` | 1.0 / 800 → 330 ms | `motion.dart:45` | unused by the Kotlin app so far |
| animateFloatAsState default | `spring()` | 1.0 / 1500 → 240 ms | `motion.dart:49` | chevron rotations |
| animateItem placement | `spring(0.8, 380)` | 0.8 / 380 → 450 ms | `motion.dart:53` | rows joining or leaving a list |

Every Flutter use goes through `context.motionDuration(spec)` (`prism_ui`), so
reduce-motion makes the duration zero; loops (pulse, spin) stay still.

## Inventory

Status: **已对齐** = the effect runs with the Kotlin timing and was checked in a
recording; **Partial** = present but different in a way this table names;
**Missing** = not in the Flutter UI.

| # | Kotlin (file:line) | Effect, trigger | Duration / curve | Flutter counterpart | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | `MainActivity.kt:92` | Push: new page slides in from 1/5 width + fade | slow spatial | `motion.dart:117` `MotionSwitcher` (`shell.dart:510`) | 已对齐 |
| 2 | `MainActivity.kt:93` | Push: old page slides to -1/10 and fades out | slow / fast effects | same | 已对齐 |
| 3 | `MainActivity.kt:94` | Back: page slides in from -1/10 + fade | slow spatial | same, `forward: false` | 已对齐 |
| 4 | `MainActivity.kt:95` | Back: page slides out to 1/5 and fades | slow / fast effects | same | 已对齐 |
| 5 | `MainActivity.kt:99` | Login route fades in and out | slow / fast effects | same, scene `login` | 已对齐 |
| 6 | `MainActivity.kt:107` | Signed in: shell fades in over login, scaled from 0.96 | slow spatial | `MotionSwitcher(fadeThrough: true)` (`shell.dart:513`) | 已对齐 |
| 7 | `HomeScreen.kt:152` | Tab switch: slide 1/8 of the width, cross-fade | slow spatial in, fast spatial out | `shell.dart:169` + `_TabPage` (`shell.dart:624`) | Partial — Kotlin home needs a tailnet, so only this build was recorded |
| 8 | `LoginScreen.kt:162` | Login stage swap: fade + vertical slide of 1/6 + size transform | slow spatial | `login.dart:520` `_StageSwap` | 已对齐 |
| 9 | `LoginScreen.kt:129` | Advanced section expands/shrinks | default specs | `login.dart:436` `ExpandVisibility` | 已对齐 |
| 10 | `NodeScreen.kt:183` | Ping result row expands and fades in | slow spatial + fade | `node_detail.dart:248` | Partial — shown on this build only (no peer to ping) |
| 11 | `NodeScreen.kt:184` | Ping text cross-fades between states | fade / fadeFast | `node_detail.dart:602` `FadeThrough` | Partial — same |
| 12 | `NodeScreen.kt:224` | Scan result joins the list and resizes | animateItem + content size | `node_detail.dart:259` (expand only, no item animation) | Partial |
| 13 | `TerminalScreen.kt:273` | SSH status subtitle cross-fades | fade / fadeFast | `terminal.dart:545` | Partial — session states need a tailnet |
| 14 | `TerminalScreen.kt:279` | Reconnect action appears with fade + scale 0.8 | default fade | — | Missing — the Flutter terminal has no reconnect action |
| 15 | `TerminalScreen.kt:282` | Agents action appears with fade + scale 0.6 | fast effects | — | Missing |
| 16 | `WebScreen.kt:190` | Back arrow fades in when the page can go back | default fade | `web_view.dart:157` | Partial — needs a live page |
| 17 | `WebScreen.kt:216` | Page load progress bar fades in and out | default fade | `web_view.dart:178` | Partial — same |
| 18 | `AgentsUi.kt:199` | Herdr summary card expands on the node page | default expand + fade | — | Missing — no summary card on the Flutter node page |
| 19 | `AgentsUi.kt:259` | New-agent FAB fades and expands when herdr is ready | default specs | — | Missing — the Flutter agents page puts "+" in the header |
| 20 | `AgentsUi.kt:279` | Agent list swaps between herdr states | default AnimatedContent | `agents.dart:98` (rows animate, the state swap is instant) | Partial |
| 21 | `AgentsUi.kt:639` | Header status label cross-fades | default AnimatedContent | `agent_chat.dart:490` | 已对齐 |
| 22 | `AgentsUi.kt:749` | Composer swaps to the blocked-prompt panel with a vertical slide of 1/3 | default specs | — | Missing — the Flutter chat has no blocked panel |
| 23 | `AgentsUi.kt:845` | Scroll-to-bottom button fades and scales | default fade | — | Missing — the Flutter chat always sits at the bottom |
| 24 | `AgentExtras.kt:518` | Subagent count chip fades in above the composer | default fade | — | Missing — no count chip |
| 25 | `AgentExtras.kt:217`, `:254`, `:324`, `AgentTimeline.kt:246`, `:448`, `AgentsUi.kt:765`, `:982`, `SettingsScreen.kt:94`, `NodeScreen.kt:224` | Content grows and shrinks with the layout | slow spatial | `motion.dart:61` `AnimatedContentSize` (`login.dart:528`, `node_detail.dart:248`) | Partial — applied where sections expand; the chat transcript does not resize |
| 26 | `Expressive.kt:198`, `HomeScreen.kt:272`, `AgentsUi.kt:289`, `:711`, `NodeScreen.kt:224` | Rows animate into place and collapse when removed | animateItem (fade + placement spring) | `controls.dart:179` `AnimatedGroupCard` | 已对齐 |
| 27 | `AgentTimeline.kt:244`, `:445` | Tool-group and todo chevrons rotate 180° | `animateFloatAsState` default | — | Missing — the Flutter chat has no collapsible tool groups or todo track |
| 28 | `AgentsUi.kt:977` | Expandable card: chevron rotates, content resizes | default | — | Missing |
| 29 | `HomeScreen.kt:126` | Indeterminate wavy linear progress while the node starts | Material 3 wavy, fade in/out | — | Missing — this build shows status text instead |
| 30 | `AgentDialogs.kt:145`, `AgentExtras.kt:188`, `:591`, `:746`, `:889`, `:971`, `:1000`, `AgentTimeline.kt:202`, `:253`, `AgentsUi.kt:306`, `:694`, `HomeScreen.kt:221`, `NodeScreen.kt:174`, `:205` | Material 3 wavy loading indicator | 1 s loop | prism `ActivityIndicator` (`third_party/prism_ui/lib/loading.dart:28`) | Partial — an arc spinner, not the wavy indicator |
| 31 | `Expressive.kt:113` | Working badge spins once every 9 s | linear | — | Missing — Flutter badges are static |
| 32 | `Expressive.kt:99` | Badge polygon morphs when the status changes | slow spatial | — | Missing — no polygon palette in the Flutter badges |
| 33 | `Expressive.kt:110` | Badge container colour fades on status change | default effects | `motion.dart:264` `PulsingDot` animates the dot colour only | Partial |
| 34 | `AgentsUi.kt:174` | Agent status dot pulses 0.35 → 1 while working or blocked | 700 ms reverse | `foundation.dart:339` (`StatusPill(dot: true, pulse: true)`) | Partial — implemented, not recorded (needs a live agent) |
| 35 | `AgentExtras.kt:486` | Three "typing" dots light in turn while an agent works | 600 ms, 160 ms stagger, reverse | — | Missing — the Flutter chat has no working bar to host them |
| 36 | `Common.kt:31` | Node status dot colour animates between online and offline | default effects | `foundation.dart:339` `PulsingDot` colour tween | 已对齐 |
| 37 | `Common.kt:112`, `HomeScreen.kt:186`, `AgentsUi.kt:246` | Pull to refresh, with a minimum 500–600 ms spinner | Material 3 pull-to-refresh | `foundation.dart:24` + `nodes.dart:33`, `agents.dart:101` | Partial — Material `RefreshIndicator` (circular), not the wavy one |
| 38 | every `clickable`/`Surface(onClick)` | Ripple and state layer on press | Material 3 | prism `PressRegion` tint | Partial — a flat tint, not a ripple |
| 39 | every `IconButton(shapes = …)`, `Button(shapes = …)` | Expressive press shape: the container squishes | Material 3 default | `controls.dart:50` `TapFeedback(scale: true)` (0.97) | Partial |
| 40 | `AgentsUi.kt:1070` | Long-press send-now fires a long-press haptic | — | `agent_chat.dart:234`, `:722` (`HapticFeedback.mediumImpact`) | Partial — needs a live agent to long-press |
| 41 | `TerminalView.kt:382` | Long-press selects a word and fires a long-press haptic | — | — | Missing — the Flutter terminal has no selection gesture |
| 42 | `TerminalView.kt:603` | Terminal bell fires a key-tap haptic | — | — | Missing — the Flutter terminal does not expose bell effects |
| 43 | `AgentsUi.kt:474`, `:501`, `:531`, `:589`, `:761`, `WebScreen.kt:135` | Snackbar slides in, waits, slides out | Material 3 | `InlineNotice` in place | Missing — this build reports in the page, not in a snackbar |
| 44 | `AgentExtras.kt` sheets, `AgentDialogs.kt` | Bottom sheets and dialogs slide and scale in | Material 3 | prism sheets and dialogs | Partial — prism motion, not Material |

Count: 44 effects, 9 已对齐, 18 Partial, 17 Missing.

## Evidence

`docs/motion/` holds the clips from `tool/motion_record.sh` (manual workflow
`motion-record.yml`). Kotlin is on the left, this build on the right; each clip
is 3–8 s at 404 px per side.

| Clip | What it shows |
| --- | --- |
| `login-expand.mp4` | Advanced/control-server section expanding and collapsing |
| `login-start.mp4` | Sign-in moving to the starting state (spinner, stage swap) |
| `press.mp4` | Press and hold on a button |

The Kotlin app cannot leave its login screen without a tailnet (it starts on
login until a control server accepts it), so effects 7, 10–13, 16–17, 20–24,
27–28, 34, 40 were recorded on this build only or not at all; they are marked
Partial or Missing rather than 已对齐.

## Re-recording

```bash
gh workflow run motion-record.yml --ref <branch>   # then download the motion artifact
```

`tool/motion_record.sh <flutter.apk> <kotlin.apk>` also runs on any attached
device; it needs `adb`, `ffmpeg` and a device with animations at scale 1.
