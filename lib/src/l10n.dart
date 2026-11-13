import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

class AppLocalizations implements UiLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<UiLocalizations>(context, UiLocalizations)!
          as AppLocalizations;

  static const delegate = _AppLocalizationsDelegate();

  bool get _zh => locale.languageCode == 'zh';

  String get tabNodes => _zh ? '节点' : 'Nodes';
  String get tabServices => _zh ? '服务' : 'Services';
  String get tabAgents => _zh ? '代理' : 'Agents';
  String get tabSettings => _zh ? '设置' : 'Settings';

  String get searchNodes => _zh ? '搜索节点' : 'Search nodes';
  String thisDevice(String ip) => _zh ? '本机 · $ip' : 'This device · $ip';
  String get online => _zh ? '在线' : 'Online';
  String get offline => _zh ? '离线' : 'Offline';
  String get onlineLower => _zh ? '在线' : 'Online';
  String get direct => _zh ? '直连' : 'Direct';
  String relay(String? region) {
    if (region == null) return _zh ? '中继' : 'Relay';
    return _zh ? '中继 · $region' : 'Relay · $region';
  }

  String get back => _zh ? '返回' : 'Back';
  String get ssh => 'SSH';
  String get sshUser => _zh ? '用户' : 'User';
  String get sshPort => _zh ? '端口' : 'Port';
  String get sshAuth => _zh ? '认证方式' : 'Authentication';
  String get authTailscale => _zh ? 'Tailscale SSH' : 'Tailscale SSH';
  String get authPassword => _zh ? '密码' : 'Password';
  String get authKey => _zh ? '密钥' : 'Key';
  String get web => _zh ? '网页' : 'Web';
  String get ping => _zh ? '延迟' : 'Ping';
  String get agentsTitle => _zh ? '代理' : 'Agents';
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
  String get servicePortInvalid => _zh ? '端口必须在 1–65535 之间' : 'Port must be 1–65535';
  String get servicePath => _zh ? '路径' : 'Path';
  String get servicePathHint => _zh ? '/ 为可选' : '/ is optional';
  String get save => _zh ? '保存' : 'Save';
  String get edit => _zh ? '编辑' : 'Edit';
  String get delete => _zh ? '删除' : 'Delete';
  String get noServicesAll => _zh ? '还没有服务，点右上角 + 添加。' : 'No services yet — add one with +.';
  String get serviceNeedsGateway => _zh
      ? '网关未运行，无法在浏览器中打开。先登录 tailnet。'
      : 'The gateway is not running, so this cannot open in a browser. Sign in to the tailnet first.';
  String get serviceOpenFailed => _zh ? '无法打开浏览器' : 'Could not open the browser';
  String get scanPorts => _zh ? '扫描常用端口' : 'Scan common ports';
  String get scanning => _zh ? '正在扫描…' : 'Scanning…';
  String scanFound(int count) => _zh ? '发现 $count 个开放端口' : '$count open ports found';
  String get scanNone => _zh ? '没有发现开放的常用端口' : 'No common ports responded';
  String get scanOffline => _zh ? '节点离线，无法扫描。' : 'The node is offline, so it cannot be scanned.';
  String get scanNeedsBackend => _zh
      ? '扫描需要桌面或 Android 构建，网页预览没有原生后端。'
      : 'Scanning needs the desktop or Android build; the web preview has no native backend.';
  String get nodeNotRunning => _zh ? '节点未运行，先登录 tailnet。' : 'The node is not running; sign in to the tailnet first.';
  String scanFailed(String error) => _zh ? '扫描失败：$error' : 'Scan failed: $error';

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

  String get appearance => _zh ? '外观' : 'Appearance';
  String get theme => _zh ? '主题' : 'Theme';
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
  String get floatingHint => _zh ? '悬浮在内容之上的玻璃 Dock' : 'Floating dock over the content';
  String get dockedHint => _zh ? '固定在内容下方的底栏' : 'Docked bar under the content';
  String get tabAnimation => _zh ? '切换动画' : 'Tab animation';
  String get slide => _zh ? '滑动' : 'Slide';
  String get fade => _zh ? '淡入' : 'Fade';
  String get slideHint => _zh ? '页面左右滑动' : 'Slide between pages';
  String get fadeHint => _zh ? '原地交叉淡入' : 'Cross-fade in place';
  String get session => _zh ? '会话' : 'Session';
  String get signOut => _zh ? '退出登录' : 'Sign out of the tailnet';
  String get about => _zh ? '关于' : 'About';

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
  String get cancel => _zh ? '取消' : 'Cancel';
  String get startingNode => _zh ? '正在启动节点…' : 'Starting the node…';
  String get backendUnavailable => _zh
      ? '原生后端不可用：未找到 libtaildeck_bridge.so，正在显示演示数据。'
      : 'Native backend unavailable: libtaildeck_bridge.so not found, showing demo data.';
  String get signInFailed => _zh ? '登录失败' : 'Sign-in failed';
  String get pinging => _zh ? '正在 Ping…' : 'Pinging…';
  String pingFailed(String error) => _zh ? 'Ping 失败：$error' : 'Ping failed: $error';
  String get worksWith => _zh
      ? '支持 Tailscale 与 Headscale 控制服务器。'
      : 'Works with Tailscale and Headscale control servers.';

  String connectedTo(String node) =>
      _zh ? '已连接到 $node · Tailscale SSH · 18 ms' : 'Connected to $node · Tailscale SSH · 18 ms';
  String get typeCommand => _zh ? '输入命令' : 'Type a command';
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
  String get sshKeyTitle => _zh ? '内置密钥' : 'Built-in key';
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
  bool isSupported(Locale locale) => const {'en', 'zh'}.contains(locale.languageCode);

  @override
  Future<UiLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
