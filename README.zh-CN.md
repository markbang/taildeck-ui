中文 · [English](README.md)

# Taildeck · Flutter + prism_ui 重设计

[![pages](https://github.com/markbang/taildeck-ui/actions/workflows/pages.yml/badge.svg)](https://github.com/markbang/taildeck-ui/actions/workflows/pages.yml)
[![license: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

**在线预览：** https://markbang.github.io/taildeck-ui/

用 Flutter 重做 [Taildeck](https://github.com/markbang/taildeck) 的 Android（Jetpack Compose）界面，基于
[prism_ui](https://github.com/chen08209/prism_ui) —— FlClash 使用的 iOS 风格设计系统。

![节点](docs/screenshots/nodes.png)

| | |
|---|---|
| ![节点详情](docs/screenshots/node.png) | ![服务](docs/screenshots/services.png) |
| ![Agents](docs/screenshots/agents.png) | ![桌面端](docs/screenshots/nodes-desktop.png) |
| ![登录](docs/screenshots/login.png) | ![SSH 终端](docs/screenshots/terminal.png) |

## 平台

https://markbang.github.io/taildeck-ui/ 上的 Web 版**只是界面预览**：它跑在模拟数据上，没有原生后端，
不能加入 tailnet、打开 SSH 会话或运行真实的 agent。

原生客户端 —— Android、Linux、Windows、macOS 和 iOS —— 正在开发中，Android 和 Linux 先行。各平台共用一套
Flutter 界面；原生边界（tsnet 节点、终端、网关）的方案见
[docs/ARCHITECTURE.zh-CN.md](docs/ARCHITECTURE.zh-CN.md)，目前仍是计划，尚未实现。

## 改动内容

原版是一个单强调色的深色 Compose 应用。这一版保留深色、紧凑的观感，但改用 prism_ui 的表面和描边图标体系重新搭建：

- **按系统区分的设备徽标** —— 手机 / 笔记本 / 显示器 / 服务器字形，按平台着色，离线时变暗
- **本机卡片** —— 本机与活跃对端连成一条折线
- **路径徽标** —— `Direct`（闪电）与 `Relay · tok` 合成一个紧凑标签，取代原来的小圆点
- **节点详情** —— 操作胶囊（SSH / Web / Ping）、Agents 摘要卡片，然后是一张分组信息卡
- **服务** —— 按节点分组，分区标题里带该节点自己的路径状态
- **Agents（herdr）** —— Android/Linux 上代理列表、状态和会话记录来自节点上的真实 herdr 服务，走与终端相同的
  SSH 连接：按工作区分区，状态胶囊（运行中 / 待确认 / 空闲 / 已完成），显示 pane 标题和 `kind · pane`；
  连接卡片会说明 `HERDR_NOT_INSTALLED` / `HERDR_NOT_RUNNING`；聊天页显示会话记录、输入框、重启和 `/model` 切换。
  网页预览仍用演示列表；连接后 “新建代理” 会真正启动代理（`workspace.create` + `agent.start`）
- **导航与 FlClash 一致** —— 同一套 prism_ui 外壳：`PageView` + `KeepScope`（切页时保留滚动位置并滑动切换），
  侧边栏放在带分隔线的 chrome 表面上的 `AnimatedVisibility.sidebar` 里，浮动 `NavigationDock` 使用
  `BarItemPresence.held` + `AnimatedVisibility.bottomNavigation`，另可在设置里切换到停靠式 `NavigationBar`；
  标签切换支持滑动 / 淡入（Fade）两种动画，淡入会取消滑动并原地交叉淡化，使用 prism_ui 的
  `fadeTabDuration` / `fadeTabCurve`
- **登录** —— 浏览器登录及等待状态、auth key 输入、可选的控制服务器地址
- **SSH 表单** —— 用户 / 端口 / 认证方式选择器基于 prism_ui 的 `PopupAnchor` + `PopupMenu`（勾选样式），
  以表单弹层呈现；选择结果带入终端标题栏
- **SSH 终端** —— 通栏等宽会话，输入行可用（`ls`、`uname`、`tailscale`、`docker ps` 等为模拟输出），
  内置 DejaVu Sans Mono
- **中英双语** —— 英文和中文，可在设置（或 `?lang=zh`）切换；所有界面文案，以及 prism_ui 自己的字符串
  （通过 `UiLocalizations`）都已覆盖
- **字体自带** —— Roboto、DejaVu Sans Mono 和一份 Noto Sans CJK 子集（SC/TC/JP/KR）随应用打包，构建使用
  `--no-web-resources-cdn`，运行时不从 `fonts.gstatic.com` / `www.gstatic.com` 取任何资源（该 CDN 在
  中国大陆不稳定）
- **自适应** —— 720 dp 以上用侧边栏，以下用玻璃质感底栏，均来自 prism_ui

## 结构

```
lib/src/
  app.dart       PrismApp，主题 + 视图作用域
  shell.dart     侧边栏 ↔ 底栏、节点详情 / agents 叠层、?tab= 与 ?node= 预览参数
  theme.dart     种子色，深色优先，支持浅色
  glyphs.dart    描边图标（节点、agents、终端、中继、太阳……）
  data.dart      示例 tailnet：本机、对端、服务、agents
  l10n.dart      覆盖 prism_ui 自身字符串的 UiLocalizations
  pages/         login · nodes · node_detail · services · agents · settings · logs · terminal
  widgets/       PageBody、GroupCard、NodeBadge、PathBadge、StatusPill、Connector、ServiceTile、ActionPill
```

预览参数：`/?tab=1`（服务）、`/?tab=2`（agents）、`/?tab=3`（设置）、`/?node=devbox`（节点详情）、
`/?theme=light`、`/?nav=docked`（停靠式底栏替代浮动底栏）、`/?anim=fade`、
`/?login=1`（登录）、`/?login=waiting`（等待设备批准）、`/?preview=1`（无节点也能看已登录界面）、
`/?ssh=devbox`（终端）、`/?lang=zh`、
`/?ssh=demo`（原生 libghostty-vt 演示会话）、`/?chat=w1:p1`（原生构建下某个 pane 的聊天页；没有 herdr 连接时
显示真实的错误状态）、`/?motion=off`（预览系统的「减少动态效果」）、`/?scale=1.3`（预览文字缩放，应用会限制在
0.9–1.3）。桌面版没有 URL，用 `TAILDECK_QUERY=ssh=demo` 传同样的参数。

## 运行

```bash
source tool/env.sh          # 国内镜像 + Flutter 3.47.9
flutter pub get
flutter run -d web-server --web-port 8099
```

## herdr 代理

Agents 标签页连接节点上的 [herdr](https://github.com/markbang/herdr)：用节点的 SSH 凭据（Tailscale SSH、设置里的
密钥或密码）登录，接入 herdr socket，并在 herdr 报告变化时重新读取 `agent.list`。连接目标保存在 `config.json`，
密码不会写入。

```bash
tool/build_native.sh          # Go ABI：td_herdr_connect / _call / _transcript / _restart / _models / _close
dart run tool/ffi_smoke.dart  # 导出符号与错误信封，不需要网络
```

与 Kotlin 版相比尚未实现：按节点保存的 SSH 配置（这里只有一个 herdr 目标）、通知里的允许/拒绝与回复、代理忙时的
消息队列、子代理会话、图片附件、斜杠命令补全。这里没有可用的 tailnet 和运行中的 herdr，真实的 pane 列表和流式
更新未经验证。

## 原生终端

```bash
tool/build_term.sh              # libghostty-vt + C shim：linux/lib/ 与 Android jniLibs/
dart run tool/term_smoke.dart   # 对真实 80x24 终端跑 FFI 冒烟测试
flutter build linux --release   # 把 linux/lib/libtaildeck_term.so 装进可执行文件旁的 lib/
```

## 字体

`assets/fonts` 存放界面字体（Roboto）、终端字体（DejaVu Sans Mono）和
`NotoSansCJK-subset.otf`（6 MB：CJK 汉字、假名、谚文、CJK 标点、全角字符）。
确定文案后可以再裁剪：

```bash
pyftsubset /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc --font-number=2 \
  --unicodes="U+3000-303F,U+3040-30FF,U+4E00-9FFF,U+AC00-D7A3,U+FF00-FFEF" \
  --output-file=assets/fonts/NotoSansCJK-subset.otf --layout-features='' --no-hinting
```

不需要韩文时去掉 `U+AC00-D7A3` 可省约 1.1 MB。

## 状态

这是一个**界面层**，还不是 Android 应用的移植版。数据全部是 `data.dart` 里的示例；终端只回显几条模拟命令，
没有 tsnet、WebView 网关或 keystore。用来取代 `data.dart` 的原生边界方案见
[docs/ARCHITECTURE.zh-CN.md](docs/ARCHITECTURE.zh-CN.md)：Go `bridge/` 模块置于 C ABI 之后，
`libghostty-vt` 终端，一套 Flutter 界面覆盖所有平台。

## 许可

prism_ui 与 Taildeck 均为 GPL-3.0，本重设计沿用该许可。`third_party/prism_ui` 是 vendored 的 0.1.2，附带
两处本地修改：一处 Web 修复（`SceneBuilder.pushClipRSuperellipse` 需要显式 `clipBehavior`），以及「减少动态效果」支持
（侧边栏、Dock、弹层和菜单在 `MediaQuery.disableAnimations` 下即时到位）。
