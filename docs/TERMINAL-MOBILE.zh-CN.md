# 手机上的终端：扩展键行

软键盘没有 Esc、Ctrl、Alt、Tab 和方向键，所以每个手机终端都会自带一条扩展键。本文记录参考应用的做法、Taildeck 在 libghostty-vt 之上的实现，以及还没做的部分。

来源读取于 2026-11-14。下文里的**键行**指终端与软键盘之间那一条，**页**指键行里的一屏按键。

## 参考应用的做法

| 应用 | 扩展键 | 粘滞修饰键 | 翻页 / 更多键 | 自定义 |
| --- | --- | --- | --- | --- |
| Termius（iOS、Android） | Keyboard add-on 贴着系统键盘上方，输入时常驻；显示扩展键盘的前三组 | 扩展键盘里提供 Ctrl、Esc、Tab 等修饰键 | 扩展键盘（侧栏）里有完整列表：方向键、功能键、符号、导航键 | 每四个键一组：可拖动排序、可新建自定义组、可去掉隐藏键盘按钮 |
| Blink Shell（iOS） | Smart Keys，只在软键盘弹出时显示，接硬件键盘时隐藏 | Ctrl、Alt、Esc；按住修饰键可以连续组合（C-x C-c） | 键行中间是滚动区域，放更多键 | `config` → Keyboard：左右修饰键可分别重映射，单击也可改成序列 |
| JuiceSSH（Android，已停止维护） | 覆盖在终端上的弹出键盘：Ctrl、Alt、Tab、方向键和难打的字符 | Ctrl、Alt 是开关；Alt 可以改成发 Esc | 向右滑打开自动补全，向左滑返回；"Popup keyboard position" 可挪位置 | 按键震动、弹出位置、Alt 模式 |
| Termux（Android） | Extra keys view，从抽屉或音量上+Q/K 打开；默认两行 | CTRL、ALT、FN、SHIFT 作为特殊键；音量下相当于 Ctrl | `extra-keys` 是一组行；长按/上滑某个键出弹出键（如 `{key: LEFT, popup: HOME}`）；键行左滑进入文本输入视图 | `~/.termux/termux.properties`：`extra-keys`、`extra-keys-style`，`termux-reload-settings` 生效 |

## Taildeck 现在的实现

| 功能 | 参考 | 计划 / 实现 | 状态 |
| --- | --- | --- | --- |
| 键行位置 | Termius 把 add-on 贴在系统键盘上方，输入时保留 | 固定在终端页底部，输入行之下、软键盘之上。Android 的 `adjustResize` 已经压缩视图；iOS 用 `viewInsets` 垫高。终端网格随键行一起缩小，光标不会被挡住。桌面窗口接的是硬件键盘，键行不显示 | 已实现 |
| 按键 | Termius：修饰键、方向键、功能键、符号。Termux：固定的两行默认值 | 第 1 页：Esc、Tab、Ctrl、Alt、←、↑、↓、→。第 2 页：Home、End、PgUp、PgDn、`\|`、`~`、`/`、`-`。第 3 页：`_`、`:`、`*`、`&`、`=`、`?`、`'`、`\` | 已实现 |
| 编码 | — | 所有按键都走 libghostty-vt 的编码器（`td_term_encode_key`），带上已激活的修饰键，Alt 和 Ctrl 发出去的就是程序期望的字节 | 已实现 |
| 粘滞修饰键 | Blink：按住修饰键连发组合。Termux：CTRL/ALT 是特殊键 | 单击激活 Ctrl/Alt 并高亮；下一个键（键行按键或键盘输入的字符）带上修饰键，随后自动取消高亮 | 已实现 |
| 修饰键锁定 | JuiceSSH：Alt 可设为一直发 Esc | 双击锁定（高亮更实，保持激活）；再点一次清除 | 已实现 |
| 翻页 | Termux：`extra-keys` 多行，滑到其余。JuiceSSH：弹出键盘左右滑 | 横向滑动翻页，另有可点的页码圆点，方便外接键盘和读屏 | 已实现 |
| 自定义 | Termius：排序与自定义组。Termux：`extra-keys` 配置文件。Blink：`config` → Keyboard | 设置 → 终端 → 扩展键行：逐页勾选显示哪些键（同一个键只属于一页），可恢复默认，写入应用配置持久保存 | 已实现 |
| 震动反馈 | JuiceSSH："Vibrate Device" | 每次按键触发 `HapticFeedback.lightImpact`，开关在 设置 → 终端 → "终端按键震动" | 已实现 |
| 复制粘贴、选择 | Termius 与 Blink 都放在手势上 | 不在本次改动 | 后续 |
| 手势快捷键（长按拖动当方向键、双击当 Tab） | Termius | 不在本次改动 | 后续 |
| 片段、会话、自定义按键序列 | Termius snippets、Blink Snips | 不在本次改动 | 后续 |

## 来源

- Termius，*Mobile terminal* — keyboard add-on、扩展键盘、按键分组、音量键、手势：<https://docs.termius.com/terminal/mobile-terminal>
- Blink Shell，*Quick Start*（文档首页）— Smart Keys、修饰键连发、中间滚动区：<https://docs.blink.sh/>
- Blink Shell，*Customizing Blink Shell* — 修饰键、custom presses、键盘设置：<https://docs.blink.sh/basics/customize>
- JuiceSSH 英文文案（弹出键盘含 Ctrl/Alt/Tab、右滑自动补全、按键震动、Alt 发 Esc）：<https://github.com/Sonelli/juicessh-translations/blob/master/en_GB/strings.xml> — 应用已停止维护，`juicessh.com` 现在是停放域名，其字符串资源是仅存的一手材料
- Termux，*Touch Keyboard* — 扩展键行、`extra-keys` 多页、弹出键、`extra-keys-style`：<https://wiki.termux.com/wiki/Touch_Keyboard>
- Flutter `HapticFeedback.lightImpact`：<https://api.flutter.dev/flutter/services/HapticFeedback/lightImpact.html>
