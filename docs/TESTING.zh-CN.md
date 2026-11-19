中文 · [English](TESTING.md)

# 界面怎么测

界面改动大部分在这台机器上几秒内就能判断，安卓模拟器是最后一步，只在必须用真机回答的地方才跑。

## 本地顺序

1. **Widget 测试** —— `flutter test --exclude-tags golden`。逻辑、布局数值、无障碍标签和手势，不比较像素。
2. **Golden 帧测试** —— `tool/golden.sh`。按 16 ms 一帧驱动真实的控件和页面，与 `test/golden/goldens/` 里的图逐像素比较。覆盖：设置里的选择器打开与关闭、一级页顶部、标题随滚动的交接、二级页的悬浮栏、Agents 页从旧的失败态切到连接中。不联网、不开模拟器，热跑约 8 秒（同样流程走模拟器要 13–28 分钟）。有意改了界面后跑 `tool/golden.sh --update`，再看 `git diff --stat test/golden/goldens` 并打开变化的图；不是你想要的差异就是回归。
3. **Linux 桌面** —— `flutter run -d linux`。用手机大小的窗口看动效、滚动和间距，Dart 界面和手机上同一份。
4. **CI 模拟器或手机** —— 只测这台机器跑不了的：Go tsnet 节点、SSH、软键盘和输入法、通知、平台启动路径。发版前 `android-smoke` 跑冷启动、返回键、Ping 和崩溃扫描。

## CI 跑什么

PR 只跑 `ci`（analyze、widget 测试、web、Linux、安卓 debug APK）和 `android-smoke`（一次模拟器启动，PR 那组 gate）。所有 `*-record`、`select-metrics` 和 `icon-compare` 只在手动 dispatch 时跑。

用来展示 bug 的 "before" 运行和取证运行，dispatch `android-smoke` 时加 `record=true`：

```sh
gh workflow run android-smoke --ref <branch> -f record=true -f gates="termtap"
```

选中的 gate 照样全部运行，结果、summary 和 artifact 都一样，但失败只记为 warning，job 保持绿色，不会发失败通知。PR 和发版调用无法打开它。

模拟器的软件合成器卡住时，冷启动会 ANR：所有窗口一起冻住，不只是应用。back gate 对失败的冷启动重试一次；第二次 ANR 直接判失败，除非 `tool/compositor_stall.py` 在两次 ANR 期间都找到另一个进程冻住 3 秒以上，这时再给第三次启动，每次运行最多两次。每次启动的 `Displayed` 时间和应用自己的 `taildeck first frame` / `taildeck frames` 日志写进 `smoke-back/timing.txt`。

Golden 用例带 `golden` 标签，CI 不跑：CI 机器的光栅化不够逐像素稳定，不适合卡 PR；同一项检查用本机的 `tool/golden.sh`。

## 加一个 golden

放到 `test/golden/`，用 `goldenApp` 包应用、`usePhone` 定视口（414 × 896，状态栏 47，手势区 34），先断言必须成立的几何，再 `matchesGoldenFile('goldens/<name>.png')`。采样区域里不要有动画，或者让它确定：给脉冲骨架截图会因脉冲相位失败，而不是界面有问题。`SkeletonPill` 的静止帧从墙钟起算，所以截图要落在它上方。
