中文 · [English](PARITY.md)

# 与 Kotlin 版的差距

Flutter 客户端对 [markbang/taildeck](https://github.com/markbang/taildeck)（Kotlin + Compose，`0d90f24`）的覆盖程度。
原生边界见 [ARCHITECTURE.zh-CN.md](ARCHITECTURE.zh-CN.md)，本页只谈功能。

| 状态 | 含义 |
|---|---|
| **已完成（Done）** | 已实现，并在这里验证过（界面截图、FFI 冒烟测试或 CI 运行）。 |
| **未验证（Unverified）** | 已实现，但在这台机器上从未端到端跑通过。 |
| **部分（Partial）** | 能用，但还有明确缺口。 |
| **未做（Not yet）** | 尚未实现。 |

构建机器无法访问 Tailscale 控制面，也没有 auth key，所以任何需要真实 tailnet 的功能都记为**未验证**：
真实登录、对端列表、SSH、herdr 和端口扫描。https://markbang.github.io/taildeck-ui/ 的网页预览跑在模拟数据上，
下表不把预览算作验证。

## 功能

| 功能 | Kotlin 版 | Flutter 版 | 状态 | 说明 |
|---|---|---|---|---|
| tsnet 节点 | 通过 SagerNet `tsnet` 在应用内运行，不占 VPN 槽位 | 同一 Go 引擎编译成 c-shared 库，经 `dart:ffi` 加载（`native/bridge`），目前用于 Android 和 Linux | 未验证 | FFI 冒烟测试里启停、状态、日志可用；控制面不可达，真实节点没起来过 |
| 登录 | 浏览器登录、auth key、Headscale 控制服务器 | 同样三种方式，有等待状态和可选的控制服务器地址 | 未验证 | 浏览器 URL 和等待状态已实现；没有控制面，无法完成批准 |
| 节点状态、对端、ping | 在线、系统、地址、标签、路由、直连/中继、延迟 | `td_status` / `td_ping`；最后在线和密钥到期时间已本地化 | 未验证 | 用固定数据渲染并截图；真实对端和 ping 未测 |
| 节点列表与详情 | 分组列表、带操作的详情页 | 本机卡片、按系统徽标、路径徽标、SSH/Web/Ping 操作、信息卡 | 已完成 | 界面完整并截图；真实数值依赖未验证的节点 |
| SSH 会话 | Tailscale SSH、密码、内置密钥、导入密钥、OpenSSH 证书 | `td_ssh_dial` + PTY，Tailscale SSH / 密码 / 密钥认证；离开终端页不结束会话，节点页可继续或断开 | 未验证 | 会话链路和按键映射已落地（M2b）；没有可达主机可连。保活缓冲用假会话做了本地测试 |
| SSH 认证方式 | 含 OpenSSH 证书 | Tailscale SSH、密码、内置 ed25519 密钥，以及可带密码短语的导入 PEM 密钥 | 部分 | ABI 有 `certPath`，但表单里没有证书选择 |
| SSH 身份 | 内置密钥、导入、删除 | 内置 `id_ed25519`，导入 PEM 密钥，密码短语随元数据保存，可删除 | 已完成 | 密钥生成和导入路径本地测过；用它们拨号属于上面未验证的 SSH 行 |
| SSH 登录用户 | 用户名可编辑，随保存的配置记住 | 同样可编辑并校验；依次用该节点/服务上次的登录、节点的 Tailscale 用户、`root` 预填 | 已完成 | 写入 `config.json`，Linux 构建重启后能读回 |
| 主机密钥信任 | TOFU，可清除已信任主机 | 相同，`td_forget_host_keys` | 未验证 | 这里从未信任过任何主机 |
| 服务 | 添加、编辑、删除，按节点分组 | `services.json`，按节点、协议、端口、路径添加/编辑/删除 | 已完成 | 已截图；通过原生存储层持久化 |
| 端口扫描 | 经节点扫描 32 个常用端口 | `td_probe`，同一份端口表 | 未验证 | 已接到节点；网页预览会提示需要原生构建 |
| 打开服务 | 应用内 WebView 或经网关用默认浏览器 | 按设置分流：Android/iOS 用应用内 WebView，其他平台用默认浏览器，两者都经 `127.0.0.1:18680` | 未验证 | 共用 `gatewayUrl` 与分流已接好，回退提示有截图；网关仍未实际跑通 |
| 18680 网关 | 本地回环正向代理，每个服务独立源 | 复用 `bridge/` 里的同一 Go 网关 | 未验证 | 代码原样复用，但需要运行中的节点才能测 |
| 应用内 WebView | 支持代理覆盖的 WebView，tailnet 主机走网关 | `webview_flutter` 加载网关地址，带返回/刷新、进度与重试 | 部分 | 仅 Android 与 iOS；桌面和网页仍用系统浏览器并就地说明。未在真机上跑过；下载、文件选择与 HTTP 认证尚未接入 |
| Agents 列表 | 按工作区的 herdr pane、状态、错误 | 经 SSH 读取真实 `agent.list`，工作区分区、状态胶囊、连接卡片 | 部分 | 已实现，错误状态验证过；真实 pane 未测 |
| Agent 聊天 | 会话记录、输入、重启、模型切换、更多历史 | 会话记录或屏幕文本、输入、重启、`/model` 与 effort 选择、翻页 | 部分 | 同样没有真实 herdr；缺的东西见下面几行 |
| 通知 | 在通知里允许 / 拒绝 / 回复 | `flutter_local_notifications`，应用在后台时 pane 变为 `blocked` 或 `done` 就提醒，点按打开该 pane 的聊天；设置里有中英文开关 | 部分 | 目前只能点按打开，还没有允许 / 拒绝 / 回复按钮。Android 与 iOS 已构建；没有真机，投递与权限弹窗未验证 |
| 消息队列 | 代理忙时排队发送 | 本地排队，代理空闲后逐条发出，可取消或立即发送 | 部分 | 代理工作时入队、`done`/`idle` 后发出；没有真实 herdr 观察代理侧表现 |
| 子代理会话 | 打开子代理的调用记录 | `td_herdr_subagent` 读取 pane 会话里的子代理文件，带类型、描述和完成状态 | 部分 | 只支持 Claude，且只验证了错误路径；没有跑过真实子代理 |
| 图片 | 显示会话里的图片和代理点名的文件 | `td_herdr_image` 取 `img:` 引用，会话里显示缩略图，全屏可缩放，`td_herdr_upload` 上传选中的文件 | 部分 | 渲染和全屏已实现；输入框还没有附件按钮，节点上的文件路径目前显示占位 |
| 斜杠命令 | `/` 命令补全 | 每个 harness 的内置命令，加上从节点读到的 `/` 命令和技能，↑↓/Esc 选择并插入 | 部分 | 内置列表验证过；没有节点，节点命令未验证 |
| 设置与日志 | Tailnet、设备、服务、SSH 密钥、日志 | Tailnet/设备信息、服务打开方式、导航、切页动画、语言、日志页 | 已完成 | 已截图（M3b、无障碍一轮） |
| 退出登录 | 停止并登出节点 | `td_logout`，带确认 | 未验证 | 需要已登录的节点 |
| Android 前台服务 | 退到后台时保持节点存活 | `dataSync` 前台服务加一条低优先级通知，节点进入 `Running` 时启动，停止或退出登录时结束 | 未验证 | 已进合并后的 manifest 和 debug APK；没有真机确认进程退到后台后仍存活 |
| Android 网络钩子 | 基于 ConnectivityManager 的网卡和 DNS | `PlatformBridge.kt` + JNI（`platform_jni.c`），`"platform": "host"` | 已完成 | #16 合入；CI 能构建，尚未在真机运行 |
| Android 系统返回键 | Compose 返回栈；在节点列表按返回会退出应用 | `lib/src/back.dart` 一条策略：先关弹窗/对话框/菜单，再退当前页，再回第一个标签，最后需连按两次才退出 | 已完成 | `android-smoke` 里 `tool/back_android.sh` 在模拟器上发真实返回键，逐步校验、进程和前台 Activity |
| 无障碍 | Compose 语义 | 读屏标签、Esc 关闭、减少动态效果、文字缩放限制在 0.9–1.3 | 已完成 | #15 合入；有减少动态效果和缩放的截图 |
| Linux 桌面 | — | 带两个原生库的产物，CI 在 Xvfb 里运行 | 已完成 | Kotlin 版之外新增 |
| Windows / macOS | — | 打 tag 或手动触发时构建未签名包，DLL/dylib 已接好 | 未验证 | 从未启动 |
| iOS | — | `c-archive` 链进 Runner | 未验证 | 未签名包已能产出；Runner target 强制加载两个归档并引用 `td_start` / `td_term_create`，归档缺失会直接链接失败。还需下一次 macOS CI 构建证明二进制里有这两个符号 |

## 有意不做成对齐的部分

- **Web** 只是预览和调试目标，没有原生后端，继续用固定数据。
- **桌面和 iOS** 超出 Kotlin 版（后者只做 Android），构建配置在 `.github/workflows/platform-release.yml`。
