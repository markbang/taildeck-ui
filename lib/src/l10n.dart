import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'herdr.dart';

class AppLocalizations implements UiLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<UiLocalizations>(context, UiLocalizations)!
          as AppLocalizations;

  static const delegate = _AppLocalizationsDelegate();

  bool get _zh => locale.languageCode == 'zh';

  /// Whether the app is drawing Chinese copy.
  bool get isZh => _zh;

  String get tabNodes => _zh ? '节点' : 'Nodes';
  String get tabServices => _zh ? '服务' : 'Services';
  String get tabAgents => _zh ? '代理' : 'Agents';
  String get tabSettings => _zh ? '设置' : 'Settings';

  String get searchNodes => _zh ? '搜索节点' : 'Search nodes';
  String get nodesEmpty => _zh ? '还没有节点。' : 'No nodes yet.';
  String thisDevice(String ip) => _zh ? '本机 · $ip' : 'This device · $ip';
  String get thisDeviceSection => _zh ? '本机' : 'This device';
  String get online => _zh ? '在线' : 'Online';
  String get offline => _zh ? '离线' : 'Offline';
  String get onlineLower => _zh ? '在线' : 'Online';
  String get direct => _zh ? '直连' : 'Direct';
  String relay(String? region) {
    if (region == null) return _zh ? '中继' : 'Relay';
    return _zh ? '中继 · $region' : 'Relay · $region';
  }

  String get onlineSpoken => _zh ? '在线' : 'online';
  String get offlineSpoken => _zh ? '离线' : 'offline';
  String get directSpoken => _zh ? '直连' : 'direct';
  String relaySpoken(String? region) =>
      _zh ? relay(region) : (region == null ? 'relay' : 'relay · $region');

  /// Relative within a day, a short date beyond it. Both locales, no `intl`
  /// dependency: the only patterns are "5 min ago" and "Nov 5, 2026".
  String lastSeen(DateTime value, DateTime now) =>
      _lastSeen(value, now, spoken: false);

  /// The same value written out for screen readers.
  String lastSeenSpoken(DateTime value, DateTime now) =>
      _lastSeen(value, now, spoken: true);

  String lastSeenSemantics(String ip, DateTime value, DateTime now) => _zh
      ? '$ip，上次在线 ${lastSeenSpoken(value, now)}'
      : '$ip, last seen ${lastSeenSpoken(value, now)}';

  /// A node row read out as one item: name, reachability, address, path.
  String nodeSemantics(
    String name, {
    required bool online,
    required String ip,
    required bool direct,
    String? relay,
    String? lastSeen,
  }) {
    final parts = [
      name,
      online ? onlineSpoken : offlineSpoken,
      ip,
      if (online) direct ? directSpoken : relaySpoken(relay),
      if (lastSeen != null && lastSeen.isNotEmpty)
        _zh ? '上次在线 $lastSeen' : 'last seen $lastSeen',
    ];
    return parts.join(_zh ? '，' : ', ');
  }

  String serviceSemantics(String name, String node, int port) =>
      _zh ? '$name，$node，端口 $port' : '$name, $node, port $port';

  String agentSemantics(String project, String harness, String state) =>
      _zh ? '$project，$harness，$state' : '$project, $harness, $state';

  String get a11yTailnetConnected => _zh ? 'tailnet 已连接' : 'Tailnet connected';
  String get a11yTailnetOffline => _zh ? 'tailnet 已断开' : 'Tailnet disconnected';
  String get a11yTailnetStarting => _zh ? '正在启动节点' : 'Node starting';
  String a11yNodeOnline(String name) => _zh ? '$name 已上线' : '$name is online';
  String a11yNodeOffline(String name) => _zh ? '$name 已离线' : '$name is offline';

  String shortDate(DateTime value) => _zh
      ? '${value.year}年${value.month}月${value.day}日'
      : '${_months[value.month - 1]} ${value.day}, ${value.year}';

  String _lastSeen(DateTime value, DateTime now, {required bool spoken}) {
    final at = value.toLocal();
    final minutes = now.difference(at).inMinutes;
    if (minutes < 1) return _zh ? '刚刚' : 'just now';
    if (minutes < 60) {
      if (_zh) return '$minutes 分钟前';
      return spoken
          ? '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago'
          : '$minutes min ago';
    }
    final hours = minutes ~/ 60;
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    if (hours < 24) {
      if (_zh) return '$hours 小时前';
      return spoken
          ? '$hours ${hours == 1 ? 'hour' : 'hours'} ago'
          : '$hours h ago';
    }
    if (days == 1) return _zh ? '昨天' : 'Yesterday';
    return shortDate(at);
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  String get back => _zh ? '返回' : 'Back';
  String get backAgainToExit => _zh ? '再按一次返回键退出' : 'Press back again to exit';
  String get ssh => 'SSH';
  String get sshUser => _zh ? '用户' : 'User';
  String get sshPort => _zh ? '端口' : 'Port';
  String get sshAuth => _zh ? '认证方式' : 'Authentication';
  String get sshUserRequired => _zh ? '请输入用户名' : 'Enter a username';
  String get sshUserInvalid => _zh
      ? '只能包含字母、数字和 . _ -，最多 32 个字符'
      : 'Letters, digits and . _ - only, up to 32 characters';
  String get authTailscale => _zh ? 'Tailscale SSH' : 'Tailscale SSH';
  String get authPassword => _zh ? '密码' : 'Password';
  String get authKey => _zh ? '密钥' : 'Key';
  String get editConnection => _zh ? '编辑连接' : 'Edit connection';
  String get nodeActionsHint => _zh ? '长按打开操作菜单' : 'Long press for actions';
  String sshFailed(String reason) =>
      _zh ? '连接失败：$reason' : 'Could not connect: $reason';
  String get web => _zh ? '网页' : 'Web';
  String get ping => _zh ? '延迟' : 'Ping';
  String get agentsTitle => _zh ? '代理' : 'Agents';
  String agentsCount(int count) => _zh ? '$count 个代理' : '$count agents';
  String agentsWorkingCount(int count) =>
      _zh ? '$count 个在工作' : '$count working';
  String agentsBlockedCount(int count) =>
      _zh ? '$count 个在等输入' : '$count blocked';
  String agentsSummary(int total, int working) =>
      _zh ? '$total 个代理 · $working 个运行中' : '$total agents · $working working';
  String get details => _zh ? '详情' : 'Details';
  String get addresses => _zh ? '地址' : 'Addresses';
  String get owner => _zh ? '所有者' : 'Owner';
  String get connection => _zh ? '连接' : 'Connection';
  String get tags => _zh ? '标签' : 'Tags';
  String get keyExpiry => _zh ? '密钥到期' : 'Key expiry';
  String get traffic => _zh ? '流量' : 'Traffic';

  String get addService => _zh ? '添加服务' : 'Add service';
  String get editService => _zh ? '编辑服务' : 'Edit service';
  String get deleteService => _zh ? '删除服务' : 'Delete service';
  String deleteServiceBody(String name) =>
      _zh ? '将删除「$name」，此操作不可撤销。' : 'Delete “$name”? This cannot be undone.';
  String get serviceNode => _zh ? '节点' : 'Node';
  String get serviceName => _zh ? '名称' : 'Name';
  String get serviceNameHint => _zh ? '默认使用端口号' : 'Defaults to the port';
  String get serviceScheme => _zh ? '协议' : 'Scheme';
  String get servicePort => _zh ? '端口' : 'Port';
  String get portInvalid => _zh ? '端口必须在 1–65535 之间' : 'Port must be 1–65535';
  String get suggestions => _zh ? '可选值' : 'Suggestions';
  String get servicePath => _zh ? '路径' : 'Path';
  String get servicePathHint => _zh ? '/ 为可选' : '/ is optional';
  String get save => _zh ? '保存' : 'Save';
  String get edit => _zh ? '编辑' : 'Edit';
  String get delete => _zh ? '删除' : 'Delete';
  String get noServicesAll =>
      _zh ? '还没有服务，点右上角 + 添加。' : 'No services yet — add one with +.';
  String get serviceNeedsGateway => _zh
      ? '网关未运行，无法在浏览器中打开。先登录 tailnet。'
      : 'The gateway is not running, so this cannot open in a browser. Sign in to the tailnet first.';
  String get serviceOpenFailed =>
      _zh ? '无法打开浏览器' : 'Could not open the browser';
  String get scanPorts => _zh ? '扫描常用端口' : 'Scan common ports';
  String get scanning => _zh ? '正在扫描…' : 'Scanning…';
  String scanFound(int count) =>
      _zh ? '发现 $count 个开放端口' : '$count open ports found';
  String get scanNone => _zh ? '没有发现开放的常用端口' : 'No common ports responded';
  String get scanOffline =>
      _zh ? '节点离线，无法扫描。' : 'The node is offline, so it cannot be scanned.';
  String get scanNeedsBackend => _zh
      ? '扫描需要桌面或 Android 构建，网页预览没有原生后端。'
      : 'Scanning needs the desktop or Android build; the web preview has no native backend.';
  String get nodeNotRunning => _zh
      ? '节点未运行，先登录 tailnet。'
      : 'The node is not running; sign in to the tailnet first.';
  String scanFailed(String error) =>
      _zh ? '扫描失败：$error' : 'Scan failed: $error';

  String get needsYou => _zh ? '待你处理' : 'Needs you';
  String get working => _zh ? '运行中' : 'Working';
  String get idle => _zh ? '空闲' : 'Idle';
  String get done => _zh ? '已完成' : 'Done';
  String get newAgent => _zh ? '新建代理' : 'New agent';
  String get harness => _zh ? '运行器' : 'Harness';
  String get project => _zh ? '项目' : 'Project';
  String get task => _zh ? '任务' : 'Task';
  String get taskHint => _zh ? '可选，一句话描述' : 'Optional, one line';
  String get create => _zh ? '创建' : 'Create';

  String get blocked => _zh ? '待确认' : 'Blocked';
  String get herdrConnectTitle => _zh ? '连接 herdr' : 'Connect herdr';
  String get herdrConnectBody => _zh
      ? 'herdr 在节点上通过 SSH 提供代理列表、会话记录和发送消息。'
      : 'herdr serves agents, transcripts and prompts over SSH on the node.';
  String get herdrNotInstalled =>
      _zh ? '这个节点上没有安装 herdr。' : 'herdr is not installed on this node.';
  String get herdrNotRunning => _zh
      ? '节点上已安装 herdr，但没有服务在运行。'
      : 'herdr is installed on the node, but no server is running.';
  String get herdrNotConnected =>
      _zh ? '尚未连接 herdr。' : 'Not connected to herdr.';
  String get herdrDropped =>
      _zh ? 'herdr 连接已断开。' : 'The herdr connection closed.';
  String get herdrNoAgents => _zh
      ? '这个节点上还没有代理，点右上角 + 启动一个。'
      : 'No agents on this node yet — start one with +.';
  String get herdrNeedsBackend => _zh
      ? 'herdr 需要桌面或 Android 构建；网页预览显示的是演示数据。'
      : 'herdr needs the desktop or Android build; the web preview shows demo data.';
  String get herdrNeedsNode => _zh
      ? '节点未运行，先登录 tailnet 再连接 herdr。'
      : 'The node is not running; sign in to the tailnet before connecting to herdr.';
  String get reconnect => _zh ? '重新连接' : 'Reconnect';
  String get disconnect => _zh ? '断开连接' : 'Disconnect';

  // Startup: the node comes up first, then herdr, and only a real failure is
  // reported.
  String get tailnetWaiting => _zh ? '正在连接 tailnet…' : 'Connecting to the tailnet…';
  String get tailnetWaitingBody => _zh
      ? '节点启动后会自动读取节点与应用。'
      : 'The node and its apps load as soon as it is up.';
  String herdrConnecting(String node) =>
      _zh ? '正在连接 herdr · $node' : 'Connecting to herdr · $node';
  String get herdrRetry => _zh ? '重试' : 'Retry';
  String get herdrConnectionSettings =>
      _zh ? '连接设置' : 'Connection settings';
  String get herdrHideConnectionSettings =>
      _zh ? '收起连接设置' : 'Hide connection settings';
  String get herdrIdle => _zh ? '未连接 herdr。' : 'Not connected to herdr.';
  String herdrErrorNoHost(String node) => _zh
      ? '找不到节点 $node —— 它在线吗？MagicDNS 开了吗？'
      : "Can't find node $node — is it online and is MagicDNS on?";
  String get herdrErrorTimeout => _zh
      ? '节点没有响应，检查它是否在线。'
      : 'The node did not answer; check that it is online.';
  String get herdrErrorUnreachable => _zh
      ? '连不上节点的 SSH，检查它是否在线。'
      : 'Could not reach the node over SSH; check that it is online.';
  String get herdrErrorAuth => _zh
      ? 'SSH 登录被拒绝，检查用户名、密钥或密码。'
      : 'The SSH login was refused; check the user, key or password.';
  String get herdrErrorPassphrase =>
      _zh ? '这把密钥需要口令。' : 'That key needs its passphrase.';
  String get herdrErrorGeneric =>
      _zh ? '连接 herdr 失败。' : 'Could not connect to herdr.';

  /// One herdr failure in words a person can act on; the Go message stays out
  /// of the UI.
  String herdrFailure(String node, HerdrFailure failure) => switch (failure) {
    HerdrFailure.unknownHost => herdrErrorNoHost(node),
    HerdrFailure.timeout => herdrErrorTimeout,
    HerdrFailure.unreachable => herdrErrorUnreachable,
    HerdrFailure.auth => herdrErrorAuth,
    HerdrFailure.passphrase => herdrErrorPassphrase,
    HerdrFailure.notInstalled => herdrNotInstalled,
    HerdrFailure.notRunning => herdrNotRunning,
    _ => herdrErrorGeneric,
  };
  String get herdrSignInFirst =>
      _zh ? '先登录 tailnet，再连接 herdr。' : 'Sign in to the tailnet to use herdr.';
  String get logsWaitingNode => _zh
      ? '节点启动后这里显示日志。'
      : 'Logs appear here once the node is running.';

  String get agentAddress => _zh ? '会话' : 'Session';
  String get agentDir => _zh ? '目录' : 'Directory';
  String get agentDirHint => _zh ? '可选，默认 home' : 'Optional, home by default';
  String get agentWorkspace => _zh ? '工作区' : 'Workspace';
  String get agentNewWorkspace => _zh ? '新工作区' : 'New workspace';
  String get agentName => _zh ? '名称' : 'Name';
  String get agentNameInvalid => _zh
      ? '名称需以小写字母开头，仅含 a-z 0-9 _ -'
      : 'Start with a lowercase letter; a-z 0-9 _ - only';
  String get agentNameTaken => _zh ? '这个名称已被占用' : 'That name is taken';
  String get agentScreenMode => _zh
      ? '这个代理没有可读的会话记录，下面是当前屏幕。'
      : 'This agent keeps no readable transcript — showing its screen.';
  String get agentTruncated => _zh
      ? '只显示最近的消息，可以读取更早的记录。'
      : 'Only recent messages are shown; earlier ones can be loaded.';
  String get agentLoadEarlier => _zh ? '读取更早记录' : 'Load earlier';
  String get agentNoMessages => _zh ? '还没有消息。' : 'No messages yet.';
  String get agentPromptHint => _zh ? '发消息给代理…' : 'Message the agent…';
  String get agentSend => _zh ? '发送' : 'Send';
  String get agentRestart => _zh ? '重启代理' : 'Restart agent';
  String get agentRestartBody => _zh
      ? '退出当前进程并按同一会话重新启动，参数会保留。'
      : 'Quits the agent and reopens the same session with its flags.';
  String get agentRestarting => _zh ? '正在重启…' : 'Restarting…';
  String get agentRestarted => _zh ? '已重启' : 'Restarted';
  String agentRestartFailed(String error) =>
      _zh ? '重启失败：$error' : 'Restart failed: $error';
  String get agentModel => _zh ? '模型' : 'Model';
  String get agentModelEmpty =>
      _zh ? '这个代理没有报告可切换的模型。' : 'This agent reports no models to switch to.';
  String get agentModelPanel => _zh ? '模型与思考强度' : 'Model and thinking';
  String get agentEffort => _zh ? '思考强度' : 'Thinking level';
  String get agentModelSession => _zh ? '代理' : 'Agent';
  String get agentModelNextTurn =>
      _zh ? '从代理的下一轮开始生效。' : 'Applies from the agent’s next turn.';
  String get agentModelFixed => _zh
      ? 'herdr 不能切换这个代理的模型。'
      : 'herdr can’t switch this agent’s model.';
  String get agentModelBusy =>
      _zh ? '等代理做完这一轮再切换。' : 'Switch once the agent has finished this turn.';
  String agentModelCapsule(String model, String effort) => effort.isEmpty
      ? (_zh ? '模型：$model' : 'Model: $model')
      : (_zh ? '模型：$model，思考强度 $effort' : 'Model: $model, thinking $effort');
  String agentModelDefault(String effort) =>
      _zh ? '默认 $effort' : 'default $effort';
  String agentModelSwitching(String target) =>
      _zh ? '切换到 $target…' : 'To $target…';
  String agentModelSwitched(String target) =>
      _zh ? '下一轮起使用 $target' : 'Next turn uses $target';
  String agentModelSwitchFailed(String error) =>
      _zh ? '切换失败：$error' : 'Couldn’t switch: $error';
  String get agentModelSwitchFailedShort => _zh ? '切换失败' : 'Switch failed';
  String get agentModelDetails => _zh ? '本会话的模型' : 'This session’s model';
  String get agentModelUnknown => _zh ? '尚未记录' : 'Not recorded yet';
  String agentModelPending(String target) => _zh
      ? '已切换到 $target，代理下一轮起生效。'
      : 'Switched to $target; the agent uses it from its next turn.';
  String get agentContext => _zh ? '已用上下文' : 'Context used';
  String get agentKind => _zh ? '代理类型' : 'Agent';
  String get effortOff => _zh ? '关闭' : 'off';
  String get effortMinimal => _zh ? '极低' : 'minimal';
  String get effortLow => _zh ? '低' : 'low';
  String get effortMedium => _zh ? '中' : 'medium';
  String get effortHigh => _zh ? '高' : 'high';
  String get effortXhigh => _zh ? '超高' : 'extra high';
  String get effortMax => _zh ? '最大' : 'max';
  String get effortUltra => _zh ? '极限' : 'ultra';
  String get effortAuto => _zh ? '自动' : 'auto';
  String agentCreated(String name) => _zh ? '已创建 $name' : 'Created $name';
  String agentPromptFailed(String error) => _zh
      ? '代理已启动，但首条消息发送失败：$error'
      : 'Agent started, but the first prompt failed: $error';
  String agentActionFailed(String error) =>
      _zh ? '操作失败：$error' : 'Failed: $error';
  String get agentTool => _zh ? '工具' : 'tool';
  String get agentThinking => _zh ? '思考' : 'Thinking';
  String agentToolSteps(int count) => _zh ? '$count 步' : '$count steps';
  String agentTodoProgress(int done, int total) =>
      _zh ? '$done/$total 已完成' : '$done/$total done';
  String get agentScrollBottom => _zh ? '回到底部' : 'Jump to bottom';
  String get agentStop => _zh ? '停止' : 'Stop';
  String get agentWorking => _zh ? '正在工作…' : 'Working…';
  String get agentBlocked => _zh ? '代理在等你的输入' : 'The agent needs your input';
  String get agentReadScreen => _zh ? '读取屏幕' : 'Read screen';
  String get keyEnter => _zh ? '回车' : 'Enter';
  String get keyEscape => _zh ? 'Esc' : 'Esc';
  String get agentSubagentsRunning => _zh ? '正在运行的子代理' : 'Subagents running';

  String get agentCommands => _zh ? '命令' : 'Commands';
  String get agentCommandsEmpty => _zh ? '没有匹配的命令' : 'No matching commands';
  String get agentCommandsHint => _zh
      ? '输入 / 查看命令，↑↓ 选择，回车插入'
      : 'Type / for commands; ↑↓ to pick, Enter to insert';
  String agentCommandLabel(String name, String description) =>
      description.isEmpty ? '/$name' : '/$name, $description';
  String get agentCommandSkill => _zh ? '技能' : 'skill';
  String agentQueuedCount(int count) => _zh ? '$count 条排队中' : '$count queued';
  String get agentQueueHint => _zh
      ? '完成后发送 · 可取消或立即发送'
      : 'Queued until it finishes · cancel or send now';
  String get agentQueued => _zh ? '排队' : 'Queued';
  String get agentQueueCancel => _zh ? '取消排队' : 'Cancel queued prompt';
  String get agentQueueSendNow => _zh ? '立即发送' : 'Send queued prompt now';
  String get agentSentWhileWorking => _zh ? '工作时发送' : 'Sent while working';
  String get agentSubagent => _zh ? '子代理' : 'Subagent';
  String get agentSubagentLoading =>
      _zh ? '正在读取子代理记录…' : 'Reading the subagent transcript…';
  String agentSubagentFailed(String error) =>
      _zh ? '读不到子代理记录：$error' : 'Cannot read the subagent transcript: $error';
  String get agentSubagentFinished => _zh ? '已完成' : 'Finished';
  String get agentSubagentRunning => _zh ? '运行中' : 'Running';
  String get agentImageUnavailable => _zh ? '图片无法加载' : 'Image unavailable';
  String get agentImageOpen => _zh ? '查看图片' : 'Open image';
  String get agentImageClose => _zh ? '关闭图片' : 'Close image';
  String get agentImageLoading => _zh ? '正在读取图片' : 'Loading image';

  /// What a harness's built-in `/<name>` does on [kind]; empty when unknown.
  String agentBuiltinHelp(String kind, String name) =>
      (_zh ? _helpZh : _helpEn)['$kind:$name'] ?? '';

  static const _helpEn = {
    'claude:compact': 'Compact the conversation',
    'claude:clear': 'Start a new conversation',
    'claude:context': 'Show context usage',
    'claude:cost': 'Show usage and cost',
    'claude:model': 'Switch model',
    'claude:effort': 'Set thinking effort',
    'claude:review': 'Review a pull request',
    'claude:security-review': 'Review pending changes for security issues',
    'claude:pr-comments': 'Fetch pull request comments',
    'claude:init': 'Write CLAUDE.md for this project',
    'codex:compact': 'Summarize the conversation to free context',
    'codex:recap': 'Summarize the conversation now',
    'codex:review': 'Review current changes and find issues',
    'codex:new': 'Start a new chat',
    'codex:init': 'Create an AGENTS.md file',
    'codex:diff': 'Show git diff, including untracked files',
    'codex:status': 'Show session configuration and token usage',
    'codex:model': 'Choose model and reasoning effort',
    'codex:plan': 'Switch to Plan mode',
    'codex:goal': 'Set or view the goal of a long task',
    'codex:fork': 'Fork the current chat',
    'codex:side': 'Start a side conversation',
    'codex:rename': 'Rename the thread',
    'codex:export': 'Export the conversation as Markdown',
    'codex:ps': 'List background terminals',
    'codex:stop': 'Stop all background terminals',
    'codex:usage': 'View account usage',
    'codex:mcp': 'List MCP tools',
    'pi:compact': 'Compact the session context',
    'pi:new': 'Start a new session',
    'pi:model': 'Switch model (provider/model)',
    'pi:thinking': 'Set thinking level',
    'pi:name': 'Set session display name',
    'pi:session': 'Show session info and stats',
    'pi:export': 'Export the session',
    'pi:clone': 'Duplicate the session at this point',
    'pi:reload': 'Reload extensions, skills and prompts',
    'omp:compact': 'Compact the session context',
    'omp:new': 'Start a new session',
    'omp:model': 'Switch model (provider/model)',
    'omp:thinking': 'Set thinking level',
    'omp:name': 'Set session display name',
    'omp:session': 'Show session info and stats',
    'omp:export': 'Export the session',
    'omp:clone': 'Duplicate the session at this point',
    'omp:reload': 'Reload extensions, skills and prompts',
  };

  static const _helpZh = {
    'claude:compact': '压缩会话',
    'claude:clear': '开一段新对话',
    'claude:context': '查看上下文占用',
    'claude:cost': '查看用量与花费',
    'claude:model': '切换模型',
    'claude:effort': '设置思考力度',
    'claude:review': '审查一个 PR',
    'claude:security-review': '检查待提交改动的安全问题',
    'claude:pr-comments': '拉取 PR 评论',
    'claude:init': '为本项目写 CLAUDE.md',
    'codex:compact': '总结对话以释放上下文',
    'codex:recap': '立刻总结对话',
    'codex:review': '审查当前改动并找问题',
    'codex:new': '开一段新对话',
    'codex:init': '创建 AGENTS.md',
    'codex:diff': '查看 git diff，含未跟踪文件',
    'codex:status': '查看会话配置与 token 用量',
    'codex:model': '选择模型与推理力度',
    'codex:plan': '切到计划模式',
    'codex:goal': '设置或查看长任务目标',
    'codex:fork': '分叉当前对话',
    'codex:side': '开一个旁支对话',
    'codex:rename': '重命名会话',
    'codex:export': '把对话导出为 Markdown',
    'codex:ps': '列出后台终端',
    'codex:stop': '停掉所有后台终端',
    'codex:usage': '查看账号用量',
    'codex:mcp': '列出 MCP 工具',
    'pi:compact': '压缩会话上下文',
    'pi:new': '开一个新会话',
    'pi:model': '切换模型（provider/model）',
    'pi:thinking': '设置思考级别',
    'pi:name': '设置会话显示名',
    'pi:session': '查看会话信息与统计',
    'pi:export': '导出会话',
    'pi:clone': '从此处复制会话',
    'pi:reload': '重新加载扩展、技能和提示词',
    'omp:compact': '压缩会话上下文',
    'omp:new': '开一个新会话',
    'omp:model': '切换模型（provider/model）',
    'omp:thinking': '设置思考级别',
    'omp:name': '设置会话显示名',
    'omp:session': '查看会话信息与统计',
    'omp:export': '导出会话',
    'omp:clone': '从此处复制会话',
    'omp:reload': '重新加载扩展、技能和提示词',
  };
  String get terminalOutput => _zh ? '终端输出' : 'Terminal output';
  String get terminalReadOnly => _zh
      ? '终端输出；点击只作为鼠标事件发给程序，输入走工具栏。'
      : 'Terminal output; taps only reach a mouse-aware program, input goes through the toolbar.';

  String get terminalSection => _zh ? '终端' : 'Terminal';
  String get terminalKeyHaptics => _zh ? '终端按键震动' : 'Terminal key haptics';
  String get terminalKeyHapticsOn => _zh
      ? '按下扩展键时轻震一下。'
      : 'A light tap when a key on the extra row is pressed.';
  String get terminalKeyHapticsOff =>
      _zh ? '已关闭，按键不再震动。' : 'Off. Keys send without haptics.';
  String a11yTerminalKeyHaptics(bool on) => _zh
      ? '终端按键震动，${on ? '已开启' : '已关闭'}'
      : 'Terminal key haptics, ${on ? 'on' : 'off'}';
  String get terminalKeyRow => _zh ? '扩展键行' : 'Extra key row';
  String terminalKeyRowHint(int keys, int pages) => _zh
      ? '$pages 页，共 $keys 个键'
      : '$keys keys on $pages ${pages == 1 ? 'page' : 'pages'}';
  String get terminalKeysIntro => _zh
      ? '选择每页显示哪些键，左右滑动键行可翻页。同一个键只属于一页。'
      : 'Choose which keys each page shows. Swipe the row to change pages; a key belongs to one page.';
  String terminalKeyPage(int page) => _zh ? '第 $page 页' : 'Page $page';
  String get terminalKeysReset => _zh ? '恢复默认' : 'Reset';
  String get terminalKeysEmptyPage =>
      _zh ? '这一页没有键，键行会跳过它。' : 'No keys on this page; the row skips it.';
  String get terminalKeysPageFull =>
      _zh ? '一页最多 8 个键。' : 'A page holds up to 8 keys.';
  String a11yTerminalKeyRow(int pages) => _zh
      ? '扩展键行，$pages 页'
      : 'Extra key row, $pages ${pages == 1 ? 'page' : 'pages'}';
  String a11yTerminalKeyPage(int page, int total) =>
      _zh ? '第 $page 页，共 $total 页' : 'Key row page $page of $total';
  String get a11yTerminalKeyPageNext => _zh ? '切到下一页' : 'Show the next page';
  String get terminalKeyArmed => _zh ? '已激活，作用于下一个键' : 'armed';
  String get terminalKeyOn => _zh ? '已开启' : 'on';
  String get terminalKeyLocked => _zh ? '已锁定' : 'locked';

  // Gestures, zoom and the keyboard-aware layout.
  String get terminalInput => _zh ? '命令输入' : 'Command input';
  String get terminalPasteButton => _zh ? '从剪贴板插入' : 'Insert from clipboard';
  String get terminalHideKeyboard => _zh ? '收起键盘' : 'Hide keyboard';
  String get terminalShowKeyboard => _zh ? '打开键盘' : 'Show keyboard';
  String get terminalArrowKeys => _zh ? '方向键与其他键' : 'Arrow keys and more';
  String get terminalCompose => _zh ? '编写' : 'Compose';
  String get terminalComposeHint => _zh
      ? '可多行；发送时每行回车一次。'
      : 'Several lines are fine; each line gets its Enter.';
  String get terminalSend => _zh ? '发送' : 'Send';
  String get terminalSendHint => _zh
      ? '发送这一行并回车；长按改成只插入'
      : 'Sends the line and presses Enter; long-press to insert only';
  String get terminalSendInsertOnly => _zh
      ? '只插入文本，不回车'
      : 'Send inserts the text without Enter';
  String get terminalSendEnterOn => _zh ? '发送会回车' : 'Send presses Enter';
  String get terminalSelection => _zh ? '选区操作' : 'Selection actions';
  String get terminalOpenLink => _zh ? '打开链接' : 'Open link';
  String get terminalCopied => _zh ? '已复制' : 'Copied';
  String get terminalOpenFailed => _zh ? '打不开这个链接' : 'Could not open the link';
  String get terminalFontSize => _zh ? '终端字号' : 'Terminal font size';
  String terminalFontSizeHint(double size) => _zh
      ? '${size.toStringAsFixed(1)} pt，双指捏合可缩放'
      : '${size.toStringAsFixed(1)} pt; pinch the grid to zoom';
  String get terminalFontSmaller => _zh ? '缩小字号' : 'Smaller font';
  String get terminalFontLarger => _zh ? '放大字号' : 'Larger font';
  String a11ySwitch(String label, bool on) =>
      _zh ? '$label，${on ? '已开启' : '已关闭'}' : '$label, ${on ? 'on' : 'off'}';
  String get terminalKeyRowWithKeyboard =>
      _zh ? '桌面窗口显示工具栏' : 'Toolbar on a desktop window';
  String get terminalKeyRowWithKeyboardOn => _zh
      ? '手机上始终显示悬浮工具栏；打开后桌面窗口也显示。'
      : 'Phones always show the floating toolbar; this adds it to desktop windows.';
  String get terminalKeyRowWithKeyboardOff => _zh
      ? '桌面窗口隐藏工具栏，硬件键盘就够了。'
      : 'Desktop windows hide the toolbar; the hardware keyboard has the keys.';

  // Appearance, snippets and sessions.
  String get terminalColors => _zh ? '颜色主题' : 'Color theme';
  String get terminalThemeFollow => _zh ? '跟随外观' : 'Match appearance';
  String get terminalThemeTaildeck => _zh ? 'Taildeck 深色' : 'Taildeck dark';
  String get terminalThemeMidnight => _zh ? '午夜蓝' : 'Midnight';
  String get terminalThemePaper => _zh ? '纸张浅色' : 'Paper light';
  String get terminalThemeSolarizedDark => _zh ? 'Solarized 深色' : 'Solarized dark';
  String get terminalThemeSolarizedLight =>
      _zh ? 'Solarized 浅色' : 'Solarized light';
  String get terminalFontFamily => _zh ? '字体' : 'Font family';
  String get terminalFontDejavu => 'DejaVu Sans Mono';
  String get terminalFontSystem => _zh ? '系统等宽' : 'System monospace';
  String get terminalFontSans => _zh ? '无衬线（非等宽）' : 'Sans (not monospace)';
  String get terminalCursorLabel => _zh ? '光标样式' : 'Cursor';
  String get terminalCursorFollow => _zh ? '跟随程序' : 'From the program';
  String get terminalCursorBlock => _zh ? '方块' : 'Block';
  String get terminalCursorBar => _zh ? '竖线' : 'Bar';
  String get terminalCursorUnderline => _zh ? '下划线' : 'Underline';
  String get terminalCursorBlink => _zh ? '光标闪烁' : 'Blinking cursor';
  String get terminalCursorBlinkOn =>
      _zh ? '光标按 530 ms 亮暗交替。' : 'The cursor blinks every 530 ms.';
  String get terminalCursorBlinkOff =>
      _zh ? '光标常亮。' : 'The cursor stays solid.';
  String get terminalKeepAlive => _zh ? '后台保持会话' : 'Keep sessions in background';
  String get terminalKeepAliveOn => _zh
      ? '切到后台后 SSH 会话继续运行，由前台服务维持进程。'
      : 'SSH sessions keep running while the app is away, held by the foreground service.';
  String get terminalKeepAliveOff => _zh
      ? '离开前台即断开会话，前台服务也随之停止。'
      : 'Sessions end when the app leaves the foreground, and the foreground service stops.';
  String get terminalKeepAliveLimits => _zh
      ? '系统仍可能回收进程：Android 的 dataSync 前台服务有 6 小时上限，Doze 和省电模式会限制网络；iOS 没有等效的前台服务。'
      : 'The OS can still reclaim the process: Android caps a dataSync foreground service at 6 hours, Doze and battery saver throttle the network, and iOS has no equivalent foreground service.';

  String get terminalSnippets => _zh ? '命令片段' : 'Snippets';
  String terminalSnippetsHint(int count) => _zh
      ? '$count 条已保存的命令'
      : '$count saved ${count == 1 ? 'command' : 'commands'}';
  String get terminalSnippetsEmpty => _zh
      ? '还没有命令片段。保存常用命令，在终端里一点就发。'
      : 'No snippets yet. Save a command and send it from the terminal with one tap.';
  String get snippetNew => _zh ? '新建片段' : 'New snippet';
  String get snippetName => _zh ? '名称' : 'Name';
  String get snippetNameHint => _zh ? '例如：查看磁盘' : 'e.g. Disk usage';
  String get snippetCommand => _zh ? '命令' : 'Command';
  String get snippetCommandHint => _zh ? '例如：df -h' : 'e.g. df -h';
  String get snippetAppendEnter => _zh ? '发送后回车' : 'Append Enter';
  String get onLabel => _zh ? '开' : 'On';
  String get offLabel => _zh ? '关' : 'Off';
  String get snippetAppendEnterOn =>
      _zh ? '发完命令直接执行。' : 'The command runs as soon as it is sent.';
  String get snippetAppendEnterOff =>
      _zh ? '只输入命令，由你按回车。' : 'Types the command only; you press Return.';
  String get snippetSave => _zh ? '保存' : 'Save';
  String get snippetDeleted => _zh ? '已删除片段' : 'Snippet deleted';
  String get snippetCommandRequired => _zh ? '命令不能为空' : 'A command is needed';
  String snippetLimit(int max) =>
      _zh ? '最多 $max 条片段' : 'Up to $max snippets';
  String snippetDeleteConfirm(String name) =>
      _zh ? '删除“$name”？' : 'Delete “$name”?';
  String get snippetMoveUp => _zh ? '上移' : 'Move up';
  String get snippetMoveDown => _zh ? '下移' : 'Move down';
  String get snippetUntitled => _zh ? '未命名' : 'Untitled';
  String get snippetNoSession =>
      _zh ? '这条会话没有连到远端，片段没有发出。' : 'This session has no remote; nothing was sent.';

  String get terminalSessions => _zh ? '会话' : 'Sessions';
  String get terminalSessionDropped => _zh ? '已断开' : 'Dropped';
  String get terminalSessionReconnecting => _zh ? '正在重连' : 'Reconnecting';
  String get terminalSessionSwitchHint =>
      _zh ? '点击切换会话' : 'Tap to switch sessions';
  String get terminalReconnectFailed => _zh ? '重连失败' : 'Reconnect failed';
  String a11yTerminalSession(String target, String state) =>
      _zh ? '$target，$state' : '$target, $state';
  String a11yTerminalSnippet(String name) =>
      _zh ? '发送片段：$name' : 'Send snippet: $name';
  String a11yTerminalSessions(int count) =>
      _zh ? '$count 个会话' : '$count sessions';

  String terminalKeyName(String id) => switch (id) {
    'esc' => _zh ? 'Esc 键' : 'Escape',
    'tab' => 'Tab',
    'ctrl' => _zh ? 'Ctrl 键' : 'Control',
    'alt' => 'Alt',
    'left' => _zh ? '左方向键' : 'Left arrow',
    'up' => _zh ? '上方向键' : 'Up arrow',
    'down' => _zh ? '下方向键' : 'Down arrow',
    'right' => _zh ? '右方向键' : 'Right arrow',
    'pgup' => _zh ? '向上翻页' : 'Page up',
    'pgdn' => _zh ? '向下翻页' : 'Page down',
    'pipe' => _zh ? '竖线' : 'Vertical bar',
    'tilde' => _zh ? '波浪号' : 'Tilde',
    'slash' => _zh ? '斜杠' : 'Slash',
    'dash' => _zh ? '连字符' : 'Hyphen',
    'underscore' => _zh ? '下划线' : 'Underscore',
    'colon' => _zh ? '冒号' : 'Colon',
    'star' => _zh ? '星号' : 'Asterisk',
    'amp' => _zh ? '和号' : 'Ampersand',
    'equals' => _zh ? '等号' : 'Equals sign',
    'question' => _zh ? '问号' : 'Question mark',
    'quote' => _zh ? '单引号' : 'Apostrophe',
    'backslash' => _zh ? '反斜杠' : 'Backslash',
    'insert' => _zh ? '只插入不回车' : 'Insert without Enter',
    _ => id,
  };

  String get tailnetAndDevice => _zh ? 'Tailnet 与设备' : 'Tailnet & device';
  String get opensSection => _zh ? '打开设置页' : 'Opens its settings';
  String get on => _zh ? '开' : 'On';
  String get unavailable => _zh ? '不可用' : 'Unavailable';
  String get off => _zh ? '关' : 'Off';
  String keyCount(int count) =>
      _zh ? '$count 个密钥' : '$count ${count == 1 ? 'key' : 'keys'}';
  String terminalFontSizeValue(double size) =>
      '${size.toStringAsFixed(0)} pt';

  String get appearance => _zh ? '外观' : 'Appearance';
  String get theme => _zh ? '主题' : 'Theme';
  String get themeMode => _zh ? '主题模式' : 'Theme mode';
  String get auto => _zh ? '自动' : 'Auto';
  String get themePreview => _zh ? '主题预览' : 'Theme preview';
  String get system => _zh ? '跟随系统' : 'System';
  String get light => _zh ? '浅色' : 'Light';
  String get dark => _zh ? '深色' : 'Dark';
  String get language => _zh ? '语言' : 'Language';
  String get english => 'English';
  String get chinese => '中文';
  String get navigation => _zh ? '导航' : 'Navigation';
  String get bottomBar => _zh ? '底部栏' : 'Bottom bar';
  String get floating => _zh ? '悬浮' : 'Floating';
  String get docked => _zh ? '贴底' : 'Docked';
  String get floatingHint =>
      _zh ? '悬浮在内容之上的玻璃底栏' : 'Floating dock over the content';
  String get dockedHint => _zh ? '固定在内容下方的底栏' : 'Docked bar under the content';
  String get tabAnimation => _zh ? '切换动画' : 'Tab animation';
  String get slide => _zh ? '滑动' : 'Slide';
  String get fade => _zh ? '淡入' : 'Fade';
  String get slideHint => _zh ? '页面左右滑动' : 'Slide between pages';
  String get fadeHint => _zh ? '旧页面淡出后新页面淡入' : 'Fade the old page out, then the new one in';
  String get motionHint => _zh
      ? '系统开启「减少动态效果」时，切换与弹层会即时完成。'
      : 'With the system reduce-motion setting on, switches and sheets complete at once.';
  String get session => _zh ? '会话' : 'Session';
  String get signOut => _zh ? '退出登录' : 'Sign out of the tailnet';
  String get about => _zh ? '关于' : 'About';

  String get tailnetSection => 'Tailnet';
  String get account => _zh ? '账号' : 'Account';
  String get tailnetName => _zh ? '网络' : 'Tailnet';
  String get hostname => _zh ? '主机名' : 'Hostname';
  String get status => _zh ? '状态' : 'Status';
  String get notSignedIn => _zh ? '未登录' : 'Not signed in';
  String get sshIdentities => _zh ? 'SSH 身份' : 'SSH identities';
  String get builtinKey => _zh ? '内置密钥' : 'Built-in key';
  String get copyPublicKey => _zh ? '复制公钥' : 'Copy public key';
  String get publicKeyCopied => _zh ? '公钥已复制' : 'Public key copied';
  String get importKey => _zh ? '导入密钥' : 'Import key';
  String get keyName => _zh ? '名称' : 'Name';
  String get keyNameHint => _zh ? '例如 work、github' : 'e.g. work, github';
  String get privateKey => _zh ? '私钥' : 'Private key';
  String get privateKeyHint => _zh
      ? '粘贴 -----BEGIN OPENSSH PRIVATE KEY----- 内容'
      : 'Paste the -----BEGIN OPENSSH PRIVATE KEY----- block';
  String get privateKeyRequired => _zh ? '请粘贴私钥' : 'Paste a private key';
  String get passphrase => _zh ? '口令' : 'Passphrase';
  String get passphraseOptional =>
      _zh ? '可选，只在本地用于解密' : 'Optional; used locally to decrypt the key';
  String get keyNameTaken => _zh ? '这个名称已经用过' : 'That name is already used';
  String get keyImportInvalid => _zh ? '名称不能为空' : 'Name cannot be empty';
  String get keyImportFailed => _zh ? '无法保存密钥' : 'Could not save the key';
  String get keyImported => _zh ? '密钥已导入' : 'Key imported';
  String get keyDeleted => _zh ? '密钥已删除' : 'Key deleted';
  String deleteKeyConfirm(String name) => _zh
      ? '删除「$name」？私钥文件也会一并删除。'
      : 'Delete “$name”? Its private key file is removed too.';
  String get publicKeyUnavailable => _zh
      ? '无法读取公钥，连接时由服务器验证'
      : 'Public key unreadable; the server checks it on connect';
  String get sshKeysHint => _zh
      ? '密钥存放在应用的本机目录，只用于 SSH 身份验证。'
      : 'Keys live in the app directory on this device and are used for SSH only.';
  String get forgetHostKeys => _zh ? '忘记已知主机' : 'Forget known hosts';
  String get forgetHostKeysHint =>
      _zh ? '下次连接会重新信任主机密钥。' : 'The next connection trusts host keys again.';
  String get hostKeysCleared => _zh ? '已清除已知主机密钥' : 'Known host keys cleared';
  String get servicesOpen => _zh ? '服务打开方式' : 'Open services in';
  String get inBrowser => _zh ? '浏览器' : 'Browser';
  String get inApp => _zh ? '应用内' : 'In app';
  String get inAppHint =>
      _zh ? '服务会在应用内的网页中打开。' : 'Services open in an in-app page.';
  String get inAppDesktopOnly => _zh
      ? '应用内网页仅支持 Android 和 iOS，这里会用系统浏览器打开。'
      : 'In-app pages are Android and iOS only, so this opens in your browser.';
  String get inAppDesktopOnlyNoGateway => _zh
      ? '应用内网页仅支持 Android 和 iOS；这里会用浏览器打开，但网关未运行。'
      : 'In-app pages are Android and iOS only; this would open in your browser, but the gateway is not running.';
  String get serviceIcons => _zh ? '服务图标' : 'Service icons';
  String get serviceIconsOn => _zh
      ? '通过 tailnet 从各服务本身获取图标，只缓存在本机。'
      : 'Fetched from each service over the tailnet and cached on this device.';
  String get serviceIconsOff => _zh
      ? '已关闭，服务行只显示首字母。'
      : 'Off. Service rows show the first letter instead.';
  String get refreshIcons => _zh ? '刷新图标' : 'Refresh icons';
  String get refreshIconsHint =>
      _zh ? '清空图标缓存并重新获取。' : 'Clear the icon cache and fetch them again.';
  String get iconsRefreshed => _zh ? '图标已刷新' : 'Icons refreshed';
  String a11yServiceIcons(bool on) => _zh
      ? '服务图标，${on ? '已开启' : '已关闭'}'
      : 'Service icons, ${on ? 'on' : 'off'}';
  String get notificationsSection => _zh ? '通知' : 'Notifications';
  String get agentNotifications => _zh ? '代理通知' : 'Agent notifications';
  String get agentNotificationsOn => _zh
      ? '代理需要你或完成任务时提醒，仅应用在后台时发送。'
      : 'Alerts when an agent needs you or finishes; only while the app is away.';
  String get agentNotificationsOff => _zh
      ? '已关闭。开启后代理需要你时提醒。'
      : 'Off. Turn on to be told when an agent needs you.';
  String get notificationsUnsupported => _zh
      ? '通知需要 Android 或 iOS 构建，这里只保留预览。'
      : 'Notifications need the Android or iOS build.';
  String get notificationsDenied => _zh
      ? '系统已阻止通知，请在系统设置里允许 Taildeck 的通知。'
      : 'Blocked in system settings. Allow notifications for Taildeck.';
  String get nodeNotificationHint => _zh
      ? '节点运行时，Taildeck 会常驻一条低优先级通知让 Android 保持进程存活，它无法关闭。'
      : 'While the node runs, Taildeck keeps a low-priority notification so Android leaves it alive; it cannot be turned off.';
  String a11yAgentNotifications(bool enabled, bool denied) => _zh
      ? '代理通知，${denied ? '被系统阻止' : (enabled ? '已开启' : '已关闭')}'
      : 'Agent notifications, ${denied ? 'blocked by the system' : (enabled ? 'on' : 'off')}';
  String get reload => _zh ? '重新加载' : 'Reload';
  String get openInBrowser => _zh ? '在浏览器中打开' : 'Open in browser';
  String get retry => _zh ? '重试' : 'Retry';
  String get webPageFailed => _zh ? '页面无法加载' : 'Page could not load';
  String get webPageFailedBody => _zh
      ? '检查节点和网关是否在线，然后重试。'
      : 'Check that the node and gateway are online, then retry.';
  String get logs => _zh ? '日志' : 'Logs';
  String get logsEmpty => _zh ? '还没有日志。' : 'No logs yet.';
  String get logsNoEntries => _zh ? '暂无记录' : 'No entries';
  String logsLines(int count) =>
      _zh ? '$count 行' : '$count ${count == 1 ? 'line' : 'lines'}';
  String logsSummary(int count, String? lastTime) =>
      lastTime == null ? logsLines(count) : '${logsLines(count)} · $lastTime';
  String get logsCopied => _zh ? '日志已复制' : 'Logs copied';
  String get refresh => _zh ? '刷新' : 'Refresh';
  String get signOutTitle => _zh ? '退出登录？' : 'Sign out?';
  String get signOutBody => _zh
      ? '会删除本机的节点密钥，下次打开需要重新登录。'
      : 'The node key on this device is removed; the next launch starts at the login screen.';
  String get signOutAction => _zh ? '退出登录' : 'Sign out';
  String version(String value) => _zh ? '版本 $value' : 'Version $value';
  String get repository => _zh ? '项目主页' : 'Repository';

  String get pleaseWait => _zh ? '处理中…' : 'Working…';
  String get serviceSaved => _zh ? '服务已保存' : 'Service saved';
  String get serviceDeleted => _zh ? '服务已删除' : 'Service deleted';
  String serviceSaveFailed(String error) =>
      _zh ? '保存失败：$error' : 'Save failed: $error';

  String get tagline =>
      _zh ? '你的 tailnet，不占 VPN 通道。' : 'Your tailnet, without the VPN slot.';
  String get continueInBrowser => _zh ? '在浏览器中继续' : 'Continue in browser';
  String get signInToControlServer =>
      _zh ? '登录你的控制服务器' : 'Sign in to your control server';
  String get useAuthKey => _zh ? '使用 Auth Key' : 'Use an auth key';
  String get pasteKey => _zh ? '粘贴 tskey-… 密钥' : 'Paste a tskey-… key';
  String get connect => _zh ? '连接' : 'Connect';
  String get controlServer => _zh ? '控制服务器' : 'Control server';
  String get waitingTitle => _zh ? '等待授权' : 'Waiting for approval';
  String get waitingForUrl => _zh
      ? '等待控制服务器返回登录地址…'
      : 'Waiting for the login URL from the control server…';
  String get waitingBody => _zh
      ? '浏览器标签页应该已经打开。完成登录后回到这里，本页会自动更新。'
      : 'A browser tab should have opened. Sign in, then come back — this screen updates on its own.';
  @override
  String get cancel => _zh ? '取消' : 'Cancel';
  String get startingNode => _zh ? '正在启动节点…' : 'Starting the node…';
  String get backendUnavailable => _zh
      ? '原生后端不可用：未找到 libtaildeck_bridge.so，正在显示演示数据。'
      : 'Native backend unavailable: libtaildeck_bridge.so not found, showing demo data.';
  String get signInFailed => _zh ? '登录失败' : 'Sign-in failed';
  String get pinging => _zh ? '正在 Ping…' : 'Pinging…';
  String pingFailed(String error) =>
      _zh ? 'Ping 失败：$error' : 'Ping failed: $error';
  String get pingDirect => _zh ? '直连' : 'direct';
  String pingRelay(String region) => 'DERP $region';
  String get worksWith => _zh
      ? '支持 Tailscale 与 Headscale 控制服务器。'
      : 'Works with Tailscale and Headscale control servers.';

  String connectedTo(String node) => _zh
      ? '已连接到 $node · Tailscale SSH · 18 ms'
      : 'Connected to $node · Tailscale SSH · 18 ms';
  String get typeCommand => _zh ? '输入命令' : 'Type a command';
  @override
  String get close => _zh ? '关闭' : 'Close';
  String get connected => _zh ? '已连接' : 'Connected';
  String get notConnected => _zh ? '未连接' : 'Not connected';
  String get demo => _zh ? '演示' : 'Demo';
  String get sshPending => _zh
      ? '此平台没有 SSH 后端，这里是 libghostty-vt 演示终端。'
      : 'No SSH backend on this platform — this is a libghostty-vt demo terminal.';
  String get connecting => _zh ? '连接中…' : 'Connecting…';
  String get disconnected => _zh ? '已断开' : 'Disconnected';
  String disconnectedReason(String reason) =>
      _zh ? '连接已断开：$reason' : 'Disconnected: $reason';
  String get sshPasswordHint => _zh ? '服务器密码' : 'Server password';
  String get sshKeyTitle => _zh ? '公钥' : 'Public key';
  String get sshIdentity => _zh ? '身份' : 'Identity';
  String get sshSessionRunning => _zh ? 'SSH 会话仍在运行' : 'SSH session running';
  String get resume => _zh ? '继续' : 'Resume';
  String get sshKeyHint => _zh
      ? '把这段公钥加到服务器的 ~/.ssh/authorized_keys。'
      : 'Add this public key to ~/.ssh/authorized_keys on the server.';
  String get sshNoBackend => _zh
      ? '原生后端不可用，SSH 需要桌面或 Android 构建。'
      : 'SSH needs the desktop or Android build; the native backend is missing.';

  @override
  String get clearSearch => _zh ? '清除搜索' : 'Clear search';
  @override
  String get copy => _zh ? '复制' : 'Copy';
  @override
  String get cut => _zh ? '剪切' : 'Cut';
  @override
  String get dialog => _zh ? '对话框' : 'Dialog';
  @override
  String get hidePassword => _zh ? '隐藏密码' : 'Hide password';
  @override
  String get more => _zh ? '更多' : 'More';
  @override
  String get noSearchResults => _zh ? '没有搜索结果' : 'No results';
  @override
  String get paste => _zh ? '粘贴' : 'Paste';
  @override
  String get reset => _zh ? '重置' : 'Reset';
  @override
  String get search => _zh ? '搜索' : 'Search';
  @override
  String get select => _zh ? '选择' : 'Select';
  @override
  String get selectAll => _zh ? '全选' : 'Select all';
  @override
  String get showLess => _zh ? '收起' : 'Show less';
  @override
  String get showMore => _zh ? '展开' : 'Show more';
  @override
  String get showPassword => _zh ? '显示密码' : 'Show password';
  @override
  String get sort => _zh ? '排序' : 'Sort';
  @override
  String get submit => _zh ? '确定' : 'Done';
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<UiLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const {'en', 'zh'}.contains(locale.languageCode);

  @override
  Future<UiLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
