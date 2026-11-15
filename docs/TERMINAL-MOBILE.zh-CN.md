# 手机上的终端：按键、手势与键盘

软键盘没有 Esc、Ctrl、Alt、Tab 和方向键，所以每个手机终端都会自带一条扩展键，也都会在网格上放手势。本文记录参考应用的做法、Taildeck 在 libghostty-vt 之上的实现，以及还没做的部分。

来源读取于 2026-11-14 与 2026-11-15。下文里的**键行**指终端与软键盘之间那一条，**页**指键行里的一屏按键。

## 参考应用的做法

| 应用 | 扩展键 | 粘滞修饰键 | 翻页 / 更多键 | 自定义 |
| --- | --- | --- | --- | --- |
| Termius（iOS、Android） | Keyboard add-on 贴着系统键盘上方，输入时常驻；显示扩展键盘的前三组 | 扩展键盘里提供 Ctrl、Esc、Tab 等修饰键 | 扩展键盘（侧栏）里有完整列表：方向键、功能键、符号、导航键 | 每四个键一组：可拖动排序、可新建自定义组、可去掉隐藏键盘按钮 |
| Blink Shell（iOS） | Smart Keys，只在软键盘弹出时显示，接硬件键盘时隐藏 | Ctrl、Alt、Esc；按住修饰键可以连续组合（C-x C-c） | 键行中间是滚动区域，放更多键 | `config` → Keyboard：左右修饰键可分别重映射，单击也可改成序列 |
| JuiceSSH（Android，已停止维护） | 覆盖在终端上的弹出键盘：Ctrl、Alt、Tab、方向键和难打的字符 | Ctrl、Alt 是开关；Alt 可以改成发 Esc | 向右滑打开自动补全，向左滑返回；"Popup keyboard position" 可挪位置 | 按键震动、弹出位置、Alt 模式 |
| Termux（Android） | Extra keys view，从抽屉或音量上+Q/K 打开；默认两行 | CTRL、ALT、FN、SHIFT 作为特殊键；音量下相当于 Ctrl | `extra-keys` 是一组行；长按/上滑某个键出弹出键（如 `{key: LEFT, popup: HOME}`）；键行左滑进入文本输入视图 | `~/.termux/termux.properties`：`extra-keys`、`extra-keys-style`，`termux-reload-settings` 生效 |

### herdr：焦点、点击与鼠标上报

herdr 是桌面终端复用器，没有触摸层：`herdrdev/herdr-core` 与 `herdrdev/herdr-app` 里都没有“点一下聚焦/弹出软键盘”的规则。它的指针路径仍是“一次点击该发什么”的参考，键盘规则则来自 Termius 与 Blink。

- `herdr-app` 的终端视图在鼠标左键按下时先给自己聚焦，然后才把核心调整到即将绘制的网格大小。
- 同一次点击再交给程序：模拟器报告鼠标跟踪（且没有按 Shift，按 Shift 时鼠标留给应用）就带上按键与修饰键发一次按下，并清掉本地选区；程序不跟踪鼠标就开始本地选区（按下、拖动、松开、选中即复制）。
- 只有按着键时才发移动；松开只发给记录为按下的键，整个拖动期间 `any_button_pressed` 为真。滚轮一格是屏幕中央的 4/5 号键，程序不跟踪鼠标时返回空。
- `herdr-core` 的编码器是 `ghostty_mouse_encoder_setopt_from_terminal`，所以格式完全取决于远端请求的是哪一种——X10、UTF-8、SGR 1006、URxvt 或 SGR-Pixels；坐标是界面像素加单元格尺寸，由编码器换算成从 1 开始的单元格。
- 获得焦点的终端也是系统输入法（拼音、日文、死键）的输入去处，和我们的输入行拥有 IME 是同一种关系。

手机上的键盘规则改看参考应用：Termius 写的是“终端输入获得焦点时软键盘出现”，接硬件键盘时隐藏，隐藏键盘的按钮在键盘 add-on 上而不是靠点一下终端；Blink 的 Smart Keys 只在软键盘弹出时显示。所以这里点一下总是把键盘叫出来，从不把它收起来。

## Taildeck 现在的实现

| 功能 | 参考 | 计划 / 实现 | 状态 |
| --- | --- | --- | --- |
| 键行位置 | Termius 把 add-on 贴在系统键盘上方，输入时保留 | 固定在终端页底部，输入行之下、软键盘之上。页面统一按 `MediaQuery.viewInsets` 垫高（它上面没有会自行缩放的 `Scaffold`），终端网格随键行一起缩小，光标不会被挡住。桌面窗口接的是硬件键盘，键行不显示 | 已实现 |
| 按键 | Termius：修饰键、方向键、功能键、符号。Termux：固定的两行默认值 | 第 1 页：Esc、Tab、Ctrl、Alt、←、↑、↓、→。第 2 页：Home、End、PgUp、PgDn、`\|`、`~`、`/`、`-`。第 3 页：`_`、`:`、`*`、`&`、`=`、`?`、`'`、`\` | 已实现 |
| 编码 | — | 所有按键都走 libghostty-vt 的编码器（`td_term_encode_key`），带上已激活的修饰键，Alt 和 Ctrl 发出去的就是程序期望的字节 | 已实现 |
| 发送 | Termius、Blink 直接用键盘自己的回车；JuiceSSH 没有可发送的输入行 | 输入行就是缓冲区：点发送，或按软键盘的发送/完成键，先写出文字，再逐行各补一个 CR，于是三行粘贴会隔 20 毫秒依次执行三条命令。长按发送，或键行上的 `Ins` 键，改为只插入不回车，选择记在应用配置里。选区工具条的 bracketed paste 仍是原样粘贴 | 已实现 |
| 粘滞修饰键 | Blink：按住修饰键连发组合。Termux：CTRL/ALT 是特殊键 | 单击激活 Ctrl/Alt 并高亮；下一个键（键行按键或键盘输入的字符）带上修饰键，随后自动取消高亮 | 已实现 |
| 修饰键锁定 | JuiceSSH：Alt 可设为一直发 Esc | 双击锁定（高亮更实，保持激活）；再点一次清除 | 已实现 |
| 翻页 | Termux：`extra-keys` 多行，滑到其余。JuiceSSH：弹出键盘左右滑 | 横向滑动翻页，另有可点的页码圆点，方便外接键盘和读屏 | 已实现 |
| 自定义 | Termius：排序与自定义组。Termux：`extra-keys` 配置文件。Blink：`config` → Keyboard | 设置 → 终端 → 扩展键行：逐页勾选显示哪些键（同一个键只属于一页），可恢复默认，写入应用配置持久保存 | 已实现 |
| 震动反馈 | JuiceSSH："Vibrate Device" | 每次按键触发 `HapticFeedback.lightImpact`，开关在 设置 → 终端 → "终端按键震动" | 已实现 |
| 长按连发 | 硬件方向键按住会自动重复 | 按住键行上的 ←、↑、↓、→ 会连发：380 毫秒后开始，之后每 70 毫秒一次；松手不再补发 | 已实现 |
| 点击聚焦 | Termius：终端输入获得焦点时键盘出现，只有 add-on 的隐藏键盘按钮或系统能收起它。herdr：点击先聚焦视图，再把点击发出去 | 每次点网格都会让输入行获得焦点并弹出软键盘，绝不收起。再点一次、点空白处、长按、双击都保持键盘。Android 已收起 IME 但输入框仍保有焦点时，点一下会重新走一次聚焦（一帧失焦、下一帧聚焦），因为焦点没变时 `TextInput.show` 会被忽略。只有键行上的键盘按钮和系统返回键能收起；按钮调 `TextInput.hide` 并保留焦点，硬件键盘仍能输入 | 已实现 |
| 鼠标上报 | herdr：在跟踪鼠标的程序里，一次点击是先按下再松开，带按键与修饰键；Shift 留给本地；长按是本地选区 | 程序启用鼠标跟踪时，点一下会通过 `td_term_encode_mouse` 发一次左键按下和松开：点击像素与当前单元格尺寸算出单元格，键行上已激活的 Ctrl/Alt 作为 GhosttyMods 位一起发出，点击后清除。协议由模拟器按远端启用的模式选择（vim、htop、tmux 要的是 SGR 1006）；没开鼠标跟踪的终端不会收到任何字节。长按与双击是本地选区，从不发点击 | 已实现 |
| 滚轮与拖动 | herdr：跟踪鼠标时滚轮变成 4/5 号键上报；拖动发移动 | 上下拖动翻看回滚、滚轮也翻回滚，都是本地的。把滚轮上报给跟踪鼠标的程序还没做 | 待做 |
| 网格手势 | Termius 把手势放在网格上；Termux 靠在键行上滑 | 单指滑动发方向键：轴向由第一段位移决定，每 26 dp 一个键，每帧最多 3 个。设置 → 终端 → "滑动发送方向键" 可关闭，关闭后上下拖动改为翻看回滚 | 已实现 |
| 选词 | Kotlin 的 `TerminalView` 长按选词；iOS 终端用双击 | 长按进入选区并选中手指下的词，双击同样（走 `td_term_select`），两端各有一个可拖动的把手；在网格上拖动可移动远端，单击清除选区并保持键盘 | 已实现 |
| 复制、粘贴与链接 | Kotlin 的 action mode 有复制和粘贴；Termius 与 Blink 都放在选区上 | 选区上方的工具条：复制（`td_term_selection_text` → 系统剪贴板）、整段选区是一个 http(s) 链接时出现"打开链接"、粘贴（`td_term_encode_paste`，尊重 bracketed paste）。输入行右侧另有粘贴按钮 | 已实现 |
| 缩放 | Blink：在网格上捏合 | 捏合改变网格字号（8–24 pt）并持久保存；设置 → 终端 显示同一数值，可点 A− / A+ | 已实现 |
| 键盘与旋转 | — | 软键盘弹出/收起、旋转都会改变网格大小，从而同时调整模拟器（`td_term_resize`）和 SSH PTY（`td_ssh_resize`）；行列跟着单元格算。调整之后视口回到实时屏幕，即使用户正在翻回滚，光标也仍在键行之上。高度不足 420 dp 的横屏会收起快捷命令条 | 已实现 |
| 硬件键盘 | Blink 接了键盘就隐藏 Smart Keys | Ctrl、Alt、Meta 组合键和方向键、Esc、Tab 都从输入行的焦点节点走 `td_term_encode_key`。Android 报告接了物理键盘（`Configuration.keyboard`）时键行隐藏，除非在 设置 → 终端 里强制保留，或软键盘正在弹出。iOS 与桌面维持现状：桌面一直隐藏，iOS 无法探测 | 已实现 |
| 片段、会话、自定义按键序列 | Termius snippets、Blink Snips | 不在本次改动 | 后续 |

## 验证

`tool/termtap_record.sh`（工作流 `termtap-record`）就是点击门禁：安装 APK，登录录制机的测试控制面，在对等节点的 sshd 上打开真实会话，收起键盘后点网格——只要 `dumpsys input_method` 不是 `mInputShown=true`、终端窗口不是当前焦点、再点一次或点空白处把 IME 收起来了、点击之后输入的命令没有在 shell 上执行、键行键盘按钮没有收起 IME、或者收起后点一下没有重新弹出，这次运行就失败。同一次运行还在对等节点上启动一个小 Python 程序，打开鼠标跟踪（1000 + SGR 1006）并记录收到的字节；一次点击必须是 `<0;Cx;CyM` 再 `<0;Cx;Cym` 且两次单元格相同，按住 Ctrl 的点击必须是 `<16;`，否则失败。录屏：`tap-focus.mp4`（收起键盘、点击、键盘弹出、再点一次）、`tap-mouse.mp4` 与 `tap-mouse-ctrl.mp4`（探针收到的上报）、`tap-vim.mp4` 与 `tap-vim-before.png` / `tap-vim-after.png`（vim 以 `set mouse=a` 启动，键盘已弹出时再点另一格，光标移到那里）、`tap-htop.mp4` 与 `tap-htop-before.png` / `tap-htop-after.png`（先点一行进程，再点另一行）。静帧：`tap-keyboard.png`。


`tool/termgestures_record.sh`（工作流 `termgestures-record`）在 Android 模拟器上录下手势层：两个方向的滑动方向键、按住方向键连发、选词与两端把手、复制（工具条显示已复制，`term-copy.png`）、打开选区里的链接（Chrome 切到前台，`term-open-link.png`）、横屏（`term-landscape.png`，网格重排成 105×12）、软键盘压缩网格而光标仍在键行之上（`term-keyboard.png`，以及 `-keyboard-hidden.png`）、在设置里加字号并重启后保持（`term-font.png`）。

`term-hardware.png`（Esc、Tab、Ctrl+C、方向键分别编码成 `^[`、`^I`、`^C`、`^[[D`、`^[[A`）和 `term-paste.png` 来自 Linux 桌面版，因为模拟器把注入的按键事件交给了 Gboard。旁边的录屏是 `docs/screenshots/term-*.mp4`。

`tool/termsend_record.sh`（工作流 `termsend-record`）录制发送写出的字节。演示会话把每个字节按插入符记法回显，所以 CR 在网格上显示成 `^M`：`term-send-button.png` 是输入行的发送（`echo send^M`），`term-send-ime.png` 是软键盘的回车（`echo enter^M`），`term-send-ime-action.png` 是 Gboard 自己的发送键（`echo action^M`，键盘不把按键放进无障碍树，所以按颜色找触点），`term-send-insert.png` 与 `-insert-cr.png` 是长按发送改成只插入：先插入 `echo ins` 不回车，再单独发一个 CR。旁边的录屏是同名的 `term-send-*.mp4`。模拟器连不上 tailnet，这些命令没有真实 shell 执行，因此 `echo` 的实际输出、历史调用与补全未实机验证。

`tool/termsessions_record.sh`（工作流 `termsessions-record`）在模拟器上跑同一批流程，对面是真 shell：录制机起一个测试控制面加两个对等节点，`motion_peer` 现在也在 22 端口提供 SSH（任意密钥或密码，pty 上跑 bash），应用因此能拨到真实会话。

桌面版在这台机器上对同一张 tailnet 跑过这些流程，`docs/screenshots/term-*` 里的静帧就来自那里：真实提示符、备用屏上的 `htop`（`term-htop.png`）、插入模式下的 vim 与中文（`term-vim.png`）、一条在远端执行 `df -h /autodl-fs` 的命令片段（`term-snippet-sent.png`）、会话条里的两条会话切换后第一条回滚仍在（`term-sessions.png`）、红色“已断开”与“重连”（`term-reconnect.png`）以及一点之后恢复的同一会话（`term-reconnect-restored.png`）。主题、字体、光标的静帧同样出自原生渲染器（`term-theme-*.png`、`term-font-sans.png`、`term-cursor-*.png`），设置页的截图是 `term-settings-appearance.png` 与 `term-settings-applied.png`。

Android 的静帧和片段来自 `termsessions-record` 那次运行：跑在对等节点真实会话上的画面（`term-android-session.png`）、一条在远端执行 `df -h /` 的命令片段（`term-android-snippet.png`、`term-snippets.mp4`）、会话条里的两条会话（`term-android-sessions.png`、`term-sessions-switch.mp4`），以及经设置切换的主题（`term-theme.mp4`、`term-android-settings.png`）。

有两项没有在这里验证：Android 构建、前台服务以及屏幕缺口——桌面窗口没有刘海、没有手势条，也没有 `dataSync` 服务，所以安全区域和“后台保持”还没验到；模拟器那次录制也漏掉了光标与字体两行（落点压在了浮动导航条上），这两张静帧仍是桌面渲染器的。另外桌面版在输入行快速打字时偶尔会重复一个字符（GTK 在缓冲区被清空的同一刻把同一次按键送了两遍），问题在输入行而不在会话，按每 400 ms 一个字符输入则不会出现。

模拟器无法验证的：捏合本身。它的触摸输入是一组 `virtio_input_multi_touch_*` 设备，没有 `INPUT_PROP_DIRECT`，注入的双指触点会被当成鼠标拖动；`adb shell input` 也没有多点命令。缩放的计算（步长、上下限）由 `test/terminal_gestures_test.dart` 覆盖，设置里的 A± 走的是同一个 setter、同样会触发网格重排。另外这里连不上任何 tailnet，所以没有对真实 shell（vim、htop、tmux）验证过。

## 来源

- Herdr，`herdrdev/herdr-core` — ghostty-vt 的鼠标编码器、滚轮上报与输入闸门：<https://github.com/herdrdev/herdr-core>（2026-11-15 读取，`crates/ghostty-vt/src/lib.rs`、`crates/herdr-core/src/input.rs`）
- Herdr，`herdrdev/herdr-app` — 终端视图的聚焦、点击、选区与移动路径：<https://github.com/herdrdev/herdr-app>（2026-11-15 读取，`src/terminal.rs`）
- Termius，*Mobile terminal* — keyboard add-on、扩展键盘、按键分组、音量键、手势：<https://docs.termius.com/terminal/mobile-terminal>
- Blink Shell，*Quick Start*（文档首页）— Smart Keys、修饰键连发、中间滚动区：<https://docs.blink.sh/>
- Blink Shell，*Customizing Blink Shell* — 修饰键、custom presses、键盘设置：<https://docs.blink.sh/basics/customize>
- JuiceSSH 英文文案（弹出键盘含 Ctrl/Alt/Tab、右滑自动补全、按键震动、Alt 发 Esc）：<https://github.com/Sonelli/juicessh-translations/blob/master/en_GB/strings.xml> — 应用已停止维护，`juicessh.com` 现在是停放域名，其字符串资源是仅存的一手材料
- Termux，*Touch Keyboard* — 扩展键行、`extra-keys` 多页、弹出键、`extra-keys-style`：<https://wiki.termux.com/wiki/Touch_Keyboard>
- Flutter `HapticFeedback.lightImpact`：<https://api.flutter.dev/flutter/services/HapticFeedback/lightImpact.html>
- Termius，*Gestures* — 网格上的双击、长按与滑动：<https://docs.termius.com/terminal/mobile-terminal>
- Flutter `ScaleGestureRecognizer`（捏合与单指滑动都走它）：<https://api.flutter.dev/flutter/gestures/ScaleGestureRecognizer-class.html>
- Android `Configuration.keyboard` — 键行读取的物理键盘位：<https://developer.android.com/reference/android/content/res/Configuration#keyboard>
