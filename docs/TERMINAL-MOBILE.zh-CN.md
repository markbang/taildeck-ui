# 手机上的终端：按键、手势与键盘

软键盘没有 Esc、Ctrl、Alt、Tab 和方向键，所以每个手机终端都会自带一条扩展键，也都会在网格上放手势。本文记录参考应用的做法、Taildeck 在 libghostty-vt 之上的实现，以及还没做的部分。

来源读取于 2026-11-14 与 2026-11-15。下文里的**键行**指终端与软键盘之间那一条，**页**指键行里的一屏按键。

## 目标：整页终端 sheet（2026-11-16）

手机终端是一张整页 sheet，不再是“导航栏 + 网格 + 输入行 + 快捷命令 + 键行”的堆叠：

- 顶部一条 4 dp 抓取条，下面 42 dp 的窄标题栏：左侧关闭圆点 + 应用图标（点按离开页面，会话仍在后台），中间是会话标题（`用户: 节点`，例如 `bang: documentation`），右侧一枚小 SSH 徽章，带状态点，断开后点它重连。没有大导航栏，也没有 “Connected” 胶囊。
- 网格铺满其余空间，深色（或浅色）背景铺满整屏；等宽字体，CJK 对齐，行高舒适。
- 底部只有一条悬浮的磨砂胶囊工具栏，浮在网格上，网格按工具栏加安全区留出底部内边距：Ctrl、Esc、Tab、方向盘按钮（展开方向键与自定义键页）、片段列表、剪贴板粘贴、编写（Compose），最右是键盘按钮。
- 没有输入行，也没有快捷命令/片段一排 chip。片段收进工具栏的列表按钮；长命令与中文输入走 Compose：多行输入，发送时写入文字并按行各补一次回车（复用 terminal_send 语义；“只插入不回车”的开关保留）。
- 点击终端不聚焦输入、不弹键盘：一次点击只作为鼠标点击（SGR 1006）发给开启了鼠标上报的程序，没开就什么都不做。键盘只由工具栏键盘按钮打开/关闭（系统返回键仍可关闭）。键盘弹出/收起是一个动画的平滑缩放，光标保持可见。
- 0.2.15 的键页自定义、震动、片段增删改、会话条、主题/字体/光标形状都保留。


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
| 工具栏位置 | Termius 把 add-on 贴在系统键盘上方，输入时保留 | 终端 sheet 底部一条悬浮的磨砂胶囊，浮在网格上；网格按胶囊加安全区留内边距。页面统一按 `MediaQuery.viewInsets` 垫高（它上面没有会自行缩放的 `Scaffold`），每次变化用一个 200 ms 的补间做动画，动画期间模拟器不改行数，停下来才 resize，所以一次键盘动作只 resize 一次而不是每帧一次。桌面窗口接的是硬件键盘，工具栏不显示 | 已实现 |
| 按键 | Termius：修饰键、方向键、功能键、符号。Termux：固定的两行默认值 | 第 1 页：Esc、Tab、Ctrl、Alt、←、↑、↓、→。第 2 页：Home、End、PgUp、PgDn、`\|`、`~`、`/`、`-`。第 3 页：`_`、`:`、`*`、`&`、`=`、`?`、`'`、`\` | 已实现 |
| 编码 | — | 所有按键都走 libghostty-vt 的编码器（`td_term_encode_key`），带上已激活的修饰键，Alt 和 Ctrl 发出去的就是程序期望的字节 | 已实现 |
| 发送 | Termius、Blink 直接用键盘自己的回车；JuiceSSH 没有可发送的输入行 | Compose 的发送先写出文字，再逐行各补一个 CR，于是三行命令会隔 20 毫秒依次执行。键页上的 `Ins` 键，或 Compose 里的开关，改为只插入不回车，选择记在应用配置里；片段自己的“发送后回车”仍按片段决定。选区工具条的 bracketed paste 仍是原样粘贴。软键盘输入不再进缓冲区：每个提交的字符就是一次按键 | 已实现 |
| 粘滞修饰键 | Blink：按住修饰键连发组合。Termux：CTRL/ALT 是特殊键 | 单击激活 Ctrl/Alt 并高亮；下一个键（键行按键或键盘输入的字符）带上修饰键，随后自动取消高亮 | 已实现 |
| 修饰键锁定 | JuiceSSH：Alt 可设为一直发 Esc | 双击锁定（高亮更实，保持激活）；再点一次清除 | 已实现 |
| 翻页 | Termux：`extra-keys` 多行，滑到其余。JuiceSSH：弹出键盘左右滑 | 横向滑动翻页，另有可点的页码圆点，方便外接键盘和读屏 | 已实现 |
| 自定义 | Termius：排序与自定义组。Termux：`extra-keys` 配置文件。Blink：`config` → Keyboard | 设置 → 终端 → 扩展键行：逐页勾选显示哪些键（同一个键只属于一页），可恢复默认，写入应用配置持久保存 | 已实现 |
| 震动反馈 | JuiceSSH："Vibrate Device" | 每次按键触发 `HapticFeedback.lightImpact`，开关在 设置 → 终端 → "终端按键震动" | 已实现 |
| 长按连发 | 硬件方向键按住会自动重复 | 按住键行上的 ←、↑、↓、→ 会连发：380 毫秒后开始，之后每 70 毫秒一次；松手不再补发 | 已实现 |
| 点击语义 | Termius：终端输入获得焦点时键盘出现。herdr：点击先聚焦视图，再把点击发出去 | 点网格没有本地动作：不聚焦、不弹键盘，只作为鼠标点击交给开启了鼠标上报的程序（见下一行）。长按与双击仍是本地选区。键盘只由工具栏键盘按钮打开和关闭（唯一入口），系统返回键仍可关闭；IME 的目标是一个 1×1 的隐藏输入框，点击碰不到它 | 已实现 |
| 鼠标上报 | herdr：在跟踪鼠标的程序里，一次点击是先按下再松开，带按键与修饰键；Shift 留给本地；长按是本地选区 | 程序启用鼠标跟踪时，点一下会通过 `td_term_encode_mouse` 发一次左键按下和松开：点击像素与当前单元格尺寸算出单元格，键行上已激活的 Ctrl/Alt 作为 GhosttyMods 位一起发出，点击后清除。协议由模拟器按远端启用的模式选择（vim、htop、tmux 要的是 SGR 1006）；没开鼠标跟踪的终端不会收到任何字节。长按与双击是本地选区，从不发点击 | 已实现 |
| 滚轮与拖动 | herdr：跟踪鼠标时滚轮变成 4/5 号键上报；拖动发移动 | 上下拖动翻看回滚、滚轮也翻回滚，都是本地的。把滚轮上报给跟踪鼠标的程序还没做 | 待做 |
| 网格手势 | Termius 把手势放在网格上；Termux 靠在键行上滑 | 单指滑动发方向键：轴向由第一段位移决定，每 26 dp 一个键，每帧最多 3 个。设置 → 终端 → "滑动发送方向键" 可关闭，关闭后上下拖动改为翻看回滚 | 已实现 |
| 选词 | Kotlin 的 `TerminalView` 长按选词；iOS 终端用双击 | 长按进入选区并选中手指下的词，双击同样（走 `td_term_select`），两端各有一个可拖动的把手；在网格上拖动可移动远端，单击清除选区并保持键盘 | 已实现 |
| 复制、粘贴与链接 | Kotlin 的 action mode 有复制和粘贴；Termius 与 Blink 都放在选区上 | 选区上方的工具条：复制（`td_term_selection_text` → 系统剪贴板）、整段选区是一个 http(s) 链接时打开链接、粘贴（`td_term_encode_paste`，尊重 bracketed paste）。胶囊上也有粘贴按钮 | 已实现 |
| 编写（Compose） | Termius、Blink 都用命令 sheet 输入长文本 | 多行 sheet，使用终端的等宽样式；发送走同一条发送路径（默认每行补回车，可切只插入）。系统的输入法组合（拼音、日文）在 sheet 里提交，中文不必经过单行输入框 | 已实现 |
| 缩放 | Blink：在网格上捏合 | 捏合改变网格字号（8–24 pt）并持久保存；设置 → 终端 显示同一数值，可点 A− / A+ | 已实现 |
| 键盘与旋转 | — | 软键盘弹出/收起、旋转都会改变网格大小，从而同时调整模拟器（`td_term_resize`）和 SSH PTY（`td_ssh_resize`）；行列跟着单元格算。底部内边距是一个补间动画，网格平滑缩放而不是一帧跳动，动画停下后才 resize PTY。调整之后视口回到实时屏幕，光标仍在工具栏上方可见 | 已实现 |
| 硬件键盘 | Blink 接了键盘就隐藏 Smart Keys | Ctrl、Alt、Meta 组合键和方向键、Esc、Tab 都从页面的焦点节点走 `td_term_encode_key`；IME 输入框持焦点时直接敲出的字符走输入框及其变更处理。手机上即使 Android 报告接了物理键盘也保留工具栏，因为键盘按钮是回到 IME 的唯一入口；桌面窗口本来就有硬件键盘，除非设置 → 终端 → “桌面窗口显示工具栏”或 `?keys=1` 要求，否则隐藏。iOS 无法判断，工具栏保留 | 已实现 |
| 片段 | Termius snippets、Blink Snips | 设置 → 终端 → 命令片段，或胶囊里的片段按钮：名称、命令行、每条片段的“发送后回车”（关掉只输入不执行）。在列表里点一下发送，面板里编辑，上下调整顺序；应用配置里最多 40 条 | 已实现 |
| 会话 | Termius 会话标签 | 每个 SSH 会话都留在 store 里，一个节点一个。模拟器属于会话而不是页面，回滚与备用屏幕程序都能保留。两个以上会话时标题栏下面有一条 `user@node` 的条，带在线/断开圆点；点一下切换，网格回到离开时的样子（vim 保留屏幕） | 已实现 |
| 重连 | Termius 重连 | 断开的会话保留自己的页面，SSH 徽章变红，点徽章就用同一个节点、用户、端口和密钥或密码重新拨号；这些只保存在会话内存里，什么都不用重输，密码从不落盘 | 已实现 |
| 主题与字体 | Termius、Blink、JuiceSSH 都有配色；Termius、Blink 有字体选择 | 五套配色（Taildeck 深色、午夜蓝、纸张浅色、Solarized 深色、Solarized 浅色）或“跟随外观”，后者在应用浅色主题下取浅色配色。主题会画整张 sheet——抓取条、标题栏、会话条、胶囊、Compose——并给出网格的默认前景与背景；远端自己设置的颜色保持原样。字体：DejaVu Sans Mono、系统等宽或 Roboto（非等宽）；网格重新量单元格，行列随之变化 | 已实现 |

## 验证

`tool/termtap_record.sh`（工作流 `termtap-record`）是点击与键盘门禁：安装 APK，登录录制机的测试控制面，在对等节点的 sshd 上打开真实会话，然后收起键盘、点网格，IME 一旦弹出就失败（点击只是鼠标点击）；点胶囊上的 `Show keyboard`，`dumpsys input_method` 不是 `mInputShown=true` 就失败；再点同一个按钮，IME 不收起就失败；再点一次网格，IME 回来就失败；通过 IME 输入一条带 Backspace 的命令，确认它真的在 shell 上执行；再展开方向盘，发 Ctrl 与方向键，打开片段列表和 Compose。同一次运行在对等节点上启动一个小 Python 程序，打开鼠标跟踪（1000 + SGR 1006）并记录收到的字节；一次点击必须是 `<0;Cx;CyM` 再 `<0;Cx;Cym` 且单元格相同，按住 Ctrl 的点击必须是 `<16;`，否则失败。录屏：`tap-no-keyboard.mp4`（点击后没有键盘）、`tap-keyboard.mp4`（按钮打开再关闭键盘）、`compose-send.mp4`（Compose 发中文）、`toolbar-controls.mp4`（Ctrl、方向键、片段、粘贴）、`tap-mouse.mp4` 与 `tap-mouse-ctrl.mp4`（探针收到的上报）、`tap-vim.mp4` 与 `tap-vim-before.png` / `tap-vim-after.png`（vim 以 `set mouse=a` 打开十二行文件，点另一处让光标移到另一行，vim 每次移动都把行号写进 `/tmp/tapvim-cursor`，行号没变就算失败）、`tap-htop.mp4` 与 `tap-htop-before.png` / `tap-htop-after.png`（先点一行进程，再点另一行）。静帧：`tap-keyboard.png`、`sheet-dark.png`、`sheet-light.png`。

`tool/terminal_sheet_record.sh`（工作流 `terminal-sheet-record`）录制前后对照：先装已发布的 v0.2.18 APK，录下旧标题栏、输入行与快捷命令条，再装本次构建，录新标题栏、工具栏、点击不弹键盘、键盘按钮、Compose 发中文、方向盘、片段、粘贴与浅色主题。`sheet-structure.png` 把新静帧和“按描述画出的参考结构”放在一起，因为用户的原图不在仓库里。

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
