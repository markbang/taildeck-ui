中文 · [English](TESTING.md)

# 界面怎么测

界面改动大部分在这台机器上几秒内就能判断，安卓模拟器是最后一步，只在必须用真机回答的地方才跑。

## 本地顺序

1. **Widget 测试** —— `flutter test --exclude-tags golden`。逻辑、布局数值、无障碍标签和手势，不比较像素。
2. **Golden 帧测试** —— `tool/golden.sh`。按 16 ms 一帧驱动真实的控件和页面，与 `test/golden/goldens/` 里的图逐像素比较。覆盖：设置里的选择器打开与关闭、一级页顶部、标题随滚动的交接、二级页的悬浮栏、Agents 页从旧的失败态切到连接中。不联网、不开模拟器，热跑约 8 秒（同样流程走模拟器要 13–28 分钟）。有意改了界面后跑 `tool/golden.sh --update`，再看 `git diff --stat test/golden/goldens` 并打开变化的图；不是你想要的差异就是回归。
3. **Linux 桌面** —— `flutter run -d linux`。用手机大小的窗口看动效、滚动和间距，Dart 界面和手机上同一份。
4. **CI 模拟器或手机** —— 只测这台机器跑不了的：Go tsnet 节点、SSH、软键盘和输入法、通知、平台启动路径。发版前 `android-smoke` 跑冷启动、返回键、Ping 和崩溃扫描。

加载原生库的 widget 测试：把 `TAILDECK_BRIDGE` 和 `TAILDECK_TERM` 指向 `tool/build_native.sh linux` 与 `tool/build_term.sh linux` 产出的库，再跑一次 `flutter test`。两个原生终端测试会运行，终端页用真实的模拟器绘制。CI 不跑这个模式：`linux` job 会构建两个库，但之后不跑 widget 测试。改动终端页或 SSH 流程前请在本机跑一遍。

## CI 跑什么

PR 只跑 `ci`（analyze、widget 测试、web、Linux、安卓 debug APK）和 `android-smoke`（一次模拟器启动，PR 那组 gate）。所有 `*-record`、`select-metrics` 和 `icon-compare` 只在手动 dispatch 时跑。

用来展示 bug 的 "before" 运行和取证运行，dispatch `android-smoke` 时加 `record=true`：

```sh
gh workflow run android-smoke --ref <branch> -f record=true -f gates="termtap"
```

选中的 gate 照样全部运行，结果、summary 和 artifact 都一样，但失败只记为 warning，job 保持绿色，不会发失败通知。PR 和发版调用无法打开它。

模拟器的软件合成器卡住时，冷启动会 ANR：所有窗口一起冻住，不只是应用。back gate 对失败的冷启动重试一次；第二次 ANR 直接判失败，除非 `tool/compositor_stall.py` 对两次 ANR 都确认：另一个进程同期冻住 3 秒以上，且应用不在 ANR 报告的 CPU 排行里。这时再给第三次启动，每次运行最多两次，并把两个进程的数字写进 summary；第三次仍卡住则按“emulator compositor stall”判失败。ANR 报告里没有 ANR 之前的 CPU 列表时，改用 gate 自己对应用主线程的采样：焦点等待期间 CPU 低于 10%，且没有在等文件，也没有在 ANR trace 里 hwui、EGL、binder 之外的 futex 上等待；采样读不到按 app-only 算。每次启动的 `Displayed` 时间和应用自己的 `taildeck first frame` / `taildeck frames` 日志写进 `smoke-back/timing.txt`。

Golden 用例带 `golden` 标签，CI 不跑：CI 机器的光栅化不够逐像素稳定，不适合卡 PR；同一项检查用本机的 `tool/golden.sh`。

## 发版 gate

`platform-release` 以 ship 模式调用 `android-smoke`，测的是刚签名构建的 x86_64 APK。要对旧构建跑同一组 gate，用 `full-gate=false` dispatch：

```sh
gh workflow run android-smoke --ref main -f full-gate=false \
  -f apk-artifact=android -f apk-run-id=<platform-release run> \
  -f gates="cold-start splash agents stills"
```

| Gate | ship 模式下 |
| --- | --- |
| `cold-start`、`splash`、`agents` | 卡发版 |
| `stills` | 仅记录：照常运行、保存截图，从不让 job 失败 |

截图只记录，是因为 CI 模拟器在设置页有一个与应用无关的已知 qemu 冻结：点设置行后约 0.7 秒内 guest 冻结，logcat 最后一行来自 `EGL_emulation`，约 60 秒后 qemu 退出，没有 OOM 或 segfault，gate 结果末尾是 `emulator: the qemu process is gone`。截图原本防的回归——页面无休止重绘——由必过的 `ci` job 里的 `test/theme_open_test.dart` 把关。

每次 ship 运行写一行结果：`stills: ok 13/13`、`stills: lost emulator 4/13` 或 `stills: failed 9/13`，出现在 job summary、`ship-stills` artifact、release notes 和 release 附件 `ship-stills.txt` 里。上一个已发布版本和本次都没有 `stills: ok` 时，release job 失败：连续两个版本没有视觉证据，是要修的 gate，不能跳过去发版。有这行记录之前的版本，截图还是卡发版的 gate，按绿色计。

某个 gate 结束时模拟器已丢失（qemu 退出或 adb 无响应），不论退出码是否为 0（录屏流程发现 adb 无响应会记 "no recording" 并返回），都会在新启动的模拟器上重跑一次：结果里保留 `LOST <gate>` 和一条 warning，丢失的那次存在 `<out>-lost/`，只按重跑结果计。ship 模式下 stills 重跑后仍是仅记录：重跑通过写 `stills: ok 13/13 (retried after a lost emulator)`，重跑也失败写 `stills: lost emulator …`。

卡发版的 gate 失败、且唯一的错误是 `emulator: the qemu process is gone` 时，重跑一次失败的 job（`gh run rerun <run-id> --failed`），并在发版报告里写明。其他任何红色都停止发版。

## 真机上的后台保活

CI 不跑：模拟器 gate 没法在后台挂几分钟。在已登录节点的手机或模拟器上：

```bash
adb shell input keyevent HOME
sleep 600
adb shell dumpsys activity services top.bangwu.taildeck | grep -A3 TailnetService
adb shell dumpsys activity processes | grep -A2 top.bangwu.taildeck
```

通过：`TailnetService` 在列且 `isForeground=true`、`foregroundServiceType=0x40000000`（specialUse），进程仍在，重新打开 app 后节点列表直接有对端，不用重连。sleep 前加 `adb shell dumpsys deviceidle force-idle` 可同时测 Doze。

## 加一个 golden

放到 `test/golden/`，用 `goldenApp` 包应用、`usePhone` 定视口（414 × 896，状态栏 47，手势区 34），先断言必须成立的几何，再 `matchesGoldenFile('goldens/<name>.png')`。采样区域里不要有动画，或者让它确定：给脉冲骨架截图会因脉冲相位失败，而不是界面有问题。`SkeletonPill` 的静止帧从墙钟起算，所以截图要落在它上方。
