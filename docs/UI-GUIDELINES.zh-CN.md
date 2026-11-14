# 界面规范

[English](UI-GUIDELINES.md)

Taildeck 各个页面的行为约定：按下是什么样子、请求执行时按钮是什么样子、
什么时候用选择器、什么时候用开关，以及页面怎么动。基于
[prism_ui](../third_party/prism_ui)，下面这些规则用来保证 Flutter 客户端在扩展时保持一致。

## 按钮状态

所有可点击表面都有四个状态：静止、按下、聚焦、禁用；会发起请求的行再多一个加载状态。

- **按下** — 表面叠一层淡色状态层；没有墨水的玻璃表面用轻微缩放（0.97）。
  用 `TapFeedback`（`lib/src/widgets/controls.dart`），不要直接写 `PressRegion`：
  后者默认不画状态层，按下去没有反应。
- **聚焦** — 同一个状态层，来自键盘或遥控；桌面端必须看得见焦点。
- **禁用** — 标签变淡、鼠标指针不变成手型，而不只是回调传 null。
- **涟漪/墨水** — 填充、色调、文字按钮直接用 prism_ui 的实现，不要自己重画。
- **点击区域** — 手机上任何可点行至少 44 dp 高。

```dart
TapFeedback(
  onTap: open,
  scale: true,             // 玻璃胶囊或 chip
  child: /* row */,
)
```

## 异步操作

发起工作的按钮必须在按下的同一帧给出反馈：

1. **立即进入加载** — 在第一个 `await` 之前把 busy 置上；不能出现"点了没反应"。
2. **加载时禁用** — 处理函数先判断（`if (_busy) return;`），同时给
   `LoadingButton` 传 `loading:`，防止重复提交。
3. **不跳布局** — spinner 放在按钮内部、原位替换图标，尺寸固定，标签保留；
   `LoadingButton` 保持按钮高度。
4. **成功或失败** — 结果就地反馈：页面或表单里用 `InlineNotice` 显示错误，
   保存成功给一行确认，然后恢复可点。异常不能吞掉：保留原有行内错误文案，
   下次尝试时清除。
5. **危险操作** — 先确认，再加载；确认框本身不算加载状态。

各操作与反馈位置：

| 操作 | 加载表现 | 结果 |
|---|---|---|
| 登录（Auth Key / 浏览器） | `LoadingButton`、浏览器行 spinner | 失败显示 `InlineNotice`；浏览器登录显示等待卡片 |
| SSH 连接 | 表单内 `LoadingButton` | 失败行内报错，成功关闭表单 |
| Ping / 扫描端口 | `ActionPill` spinner 并禁用 | ping 文案、扫描结果或 `InlineNotice` |
| 服务保存 / 新增 / 编辑 | 表单内 `LoadingButton` | 关闭表单并确认；失败留在表单内报错 |
| 删除服务 | 行内 spinner | 行收起并提示已删除 |
| 导入密钥 | 表单内 `LoadingButton` | 刷新密钥列表；失败行内报错 |
| 忘记已知主机 | 行内 spinner，行禁用 | 成功提示或错误 |
| 退出登录 | 先确认，再由 shell 离开 | 回到登录页 |
| 代理 连接 / 发送 / 重启 / 切模型 | 按钮或图标 spinner，相关控件禁用 | 提示或行内报错 |
| 代理通知 | 开关位置换成 spinner | 保存后恢复开关 |

## 选择器与分段控件

表单里的取值统一用 `SelectRow`（`lib/src/widgets/select_row.dart`）：
SSH 认证方式、端口、身份、服务节点、协议、主题、语言、底栏样式、切换动画、
服务打开方式、代理 harness/workspace/模型。

- 它打开 prism_ui 的 `PopupAnchor` + `PopupMenu`（iOS 风格菜单），当前值带勾，
  读屏时是一个整体："标签，当前值"加"选择"提示。
- 表单提交中用 `enabled: false` 禁用。
- `SegmentedControl` 只用来切换视图或筛选（同一屏内的分段），不能当表单取值：
  分段表示"给我看这个"，选择器表示"保存这个"。

## 动效

| 内容 | 时长 | 曲线 |
|---|---|---|
| 页面推入（桌面） | 200 ms 淡入 | prism_ui `FadePageRoute` |
| 页面推入（手机） | 弹簧卡片 | prism_ui `CardPageRoute`，支持边缘返回 |
| 列表行进入/退出 | 220 ms 尺寸 + 淡入 | `easeInOutCubic`，`AnimatedGroupCard` |
| 页面打开时的分区入场 | 200 ms 淡入 + 8 dp 上移 | `easeOutCubic`，间隔 32 ms，最多 160 ms |
| 选择器 / 表单 | prism_ui 自带路由动效 | — |
| 按下状态层 | 50 ms | — |

- 会在显示期间变化的列表（服务、代理、节点）用 `AnimatedGroupCard`；分隔线属于
  上一行，行退出时一起消失。
- 减少动态效果：`context.disableAnimations`（系统设置或 `?motion=off`）会让入场、
  列表和路由立即完成。新加的动效必须判断这一项；prism_ui 自带组件已经处理。
- 手机上不要同时播放两段动效：页面推入和列表入场的时机不要重叠。

## 无障碍

- 一行一个读屏节点：`RowSemantics(label: ...)`，或给 `TapFeedback`/`SelectRow`
  传语义标签；不要把零散文字逐段读出来。
- 按钮用一个动作名（"连接"、"扫描常用端口"）；选择器读"标签，当前值"并带"选择"
  提示；表单有标题和关闭标签。
- 加载中的按钮会报告忙碌状态，读屏能听到操作正在执行。
- 焦点可见，Esc 可离开页面和表单（prism_ui 处理）。
- 文本跟随系统字号，行变高而不是被裁掉。
- 颜色不是唯一信号：状态一定同时有文字。

## 图标

- 唯一来源：prism_ui 的 `Glyphs` 加上应用的 `Glyphs2`（`lib/src/glyphs.dart`）。
  不用 Material `Icons`、不用 emoji、不用图片当界面图标。
- 尺寸：行内 14–16，按钮 18，页面或卡片徽标 22–28。
- 颜色：次要图标用 `onSurfaceVariant`，身份图标用节点/服务色，只有破坏性操作
  才用 `scheme.error`。
- 状态用图标加文字（`StatusPill`），不能只给图标。

## 文案

- 中英文同时发布；新增文案必须同一次改动里进 `AppLocalizations`。
- 句首大写、不用感叹号、不用"全新 ✨"。动词说清结果：
  "扫描常用端口"，而不是"扫描"。
- 错误说明什么失败了，并保留服务端信息："保存失败：<原因>"，不要怪用户。
- 计数和日期用应用自己的格式（`l10n.lastSeen`、`shortDate`），不引入 `intl` 模板。
