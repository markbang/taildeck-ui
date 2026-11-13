import 'package:flutter/widgets.dart';

class NodeItem {
  const NodeItem({
    required this.name,
    required this.ip,
    required this.os,
    required this.online,
    this.ips = const [],
    this.lastSeen = '',
    this.direct = false,
    this.relay,
    this.rx = '',
    this.tx = '',
    this.tags = const [],
    this.routes = const [],
    this.isSelf = false,
    this.owner = 'markbang@github',
    this.expiry = '2027-03-02',
    this.dns = '',
  });

  final String name;
  final String ip;
  final String os;
  final bool online;

  /// Every tailnet address; [ip] stays the primary IPv4 for compact rows.
  final List<String> ips;

  /// RFC3339 timestamp from the backend, empty when unknown.
  final String lastSeen;
  final bool direct;
  final String? relay;
  final String rx;
  final String tx;
  final List<String> tags;
  final List<String> routes;
  final bool isSelf;
  final String owner;

  /// RFC3339 timestamp from the backend, empty when the key never expires.
  final String expiry;
  final String dns;

  List<String> get addresses => ips.isEmpty ? [ip] : ips;

  DateTime? get lastSeenAt => DateTime.tryParse(lastSeen);

  DateTime? get expiryAt => DateTime.tryParse(expiry);

  Color get tint => switch (os) {
    'macOS' => const Color(0xFF7C8CFF),
    'Windows' => const Color(0xFF3FC1C9),
    'Android' || 'iOS' => const Color(0xFF9B7CFF),
    _ => const Color(0xFF4FB28A),
  };
}

const tailnet = 'markbang.github';

/// Shown in Settings; keep in step with `version:` in pubspec.yaml.
const appVersion = '0.2.3';
const repoUrl = 'https://github.com/markbang/taildeck-ui';

/// `?ssh=demo`: the canned session that shows the emulator without a tailnet.
const demoNode = NodeItem(name: 'demo', ip: 'local', os: 'Terminal', online: true);

const selfNode = NodeItem(
  name: 'pixel-9',
  ip: '100.101.4.2',
  os: 'Android',
  online: true,
  direct: true,
  rx: '4.08 GB',
  tx: '812 MB',
  isSelf: true,
  dns: 'pixel-9.tail4a2c.ts.net',
);

final peers = <NodeItem>[
  NodeItem(
    name: 'nas',
    ip: '100.88.12.7',
    os: 'Linux',
    online: true,
    direct: true,
    rx: '4.08 GB',
    tx: '2.31 GB',
    tags: ['tag:nas'],
    routes: ['192.168.1.0/24'],
    dns: 'nas.tail4a2c.ts.net',
  ),
  NodeItem(
    name: 'devbox',
    ip: '100.71.200.9',
    os: 'Linux',
    online: true,
    relay: 'tok',
    rx: '93.5 MB',
    tx: '29.6 MB',
    tags: ['tag:dev'],
    dns: 'devbox.tail4a2c.ts.net',
  ),
  NodeItem(
    name: 'pi-k3s',
    ip: '100.64.9.33',
    os: 'Linux',
    online: true,
    direct: true,
    rx: '211 MB',
    tx: '88 MB',
    tags: ['tag:k8s', 'tag:router'],
    dns: 'pi-k3s.tail4a2c.ts.net',
  ),
  NodeItem(
    name: 'macbook-air',
    ip: '100.90.1.14',
    os: 'macOS',
    online: true,
    relay: 'hkg',
    rx: '38 MB',
    tx: '12 MB',
    dns: 'macbook-air.tail4a2c.ts.net',
  ),
  NodeItem(
    name: 'win-gaming',
    ip: '100.77.3.101',
    os: 'Windows',
    online: false,
    lastSeen: _ago(const Duration(hours: 2)),
    rx: '1.2 GB',
    tx: '640 MB',
    dns: 'win-gaming.tail4a2c.ts.net',
  ),
];

enum AgentState { working, idle, done }

/// The demo list's task lines, so the sample data reads in both languages.
enum DemoTask { grafanaAlerts, releaseWorkflow, headscaleBump }

class AgentItem {
  const AgentItem({
    required this.name,
    required this.state,
    required this.task,
    required this.project,
    required this.window,
    this.agent = '',
    this.demoTask,
  });

  final String name;
  final AgentState state;
  final String task;
  final DemoTask? demoTask;
  final String project;
  final String window;
  final String agent;
}

const agents = <({String section, List<AgentItem> items})>[
  (
    section: 'Needs you',
    items: [
      AgentItem(
        name: 'claude',
        state: AgentState.done,
        task: '',
        demoTask: DemoTask.grafanaAlerts,
        project: 'infra',
        window: 'w3:p4',
      ),
    ],
  ),
  (
    section: 'taildeck',
    items: [
      AgentItem(
        name: 'claude',
        state: AgentState.working,
        task: '',
        demoTask: DemoTask.releaseWorkflow,
        project: 'taildeck',
        window: 'w1:p2',
      ),
      AgentItem(
        name: 'codex',
        state: AgentState.idle,
        task: '',
        project: 'taildeck',
        window: 'w1:p3',
      ),
    ],
  ),
  (
    section: 'router',
    items: [
      AgentItem(
        name: 'pi',
        state: AgentState.working,
        task: '',
        demoTask: DemoTask.headscaleBump,
        project: 'router',
        window: 'w2:p1',
      ),
    ],
  ),
];

/// Demo timestamps stay recent so the mock node list reads like a live tailnet.
String _ago(Duration duration) =>
    DateTime.now().toUtc().subtract(duration).toIso8601String();

/// Maps one node from `td_status` (`native/bridge/bridge.go` `nodeJSON`) onto
/// [NodeItem]. Missing fields stay empty rather than guessed.
NodeItem nodeFromJson(Map<String, dynamic> json, {bool isSelf = false}) {
  final ips = [
    for (final ip in (json['ips'] as List? ?? const []))
      if (ip is String && ip.isNotEmpty) ip,
  ];
  ips.sort((a, b) => (a.contains(':') ? 1 : 0) - (b.contains(':') ? 1 : 0));
  final relay = json['relay'] as String? ?? '';
  return NodeItem(
    name: json['name'] as String? ?? '',
    ip: ips.isEmpty ? '' : ips.first,
    ips: ips,
    os: _nodeOs(json['os'] as String? ?? ''),
    online: json['online'] as bool? ?? false,
    direct: (json['curAddr'] as String? ?? '').isNotEmpty,
    relay: relay.isEmpty ? null : relay,
    rx: _bytes((json['rxBytes'] as num?)?.toInt() ?? 0),
    tx: _bytes((json['txBytes'] as num?)?.toInt() ?? 0),
    tags: [
      for (final tag in (json['tags'] as List? ?? const []))
        if (tag is String) tag,
    ],
    routes: [
      for (final route in (json['routes'] as List? ?? const []))
        if (route is String) route,
    ],
    isSelf: isSelf,
    owner: json['user'] as String? ?? '',
    expiry: _stamp(json['keyExpiry'] as String? ?? ''),
    lastSeen: _stamp(json['lastSeen'] as String? ?? ''),
    dns: json['dnsName'] as String? ?? '',
  );
}

String _nodeOs(String os) => switch (os.toLowerCase()) {
  'macos' => 'macOS',
  'windows' => 'Windows',
  'android' => 'Android',
  'ios' => 'iOS',
  'linux' => 'Linux',
  _ => os,
};

/// Drops the zero time (keys that never expire) and malformed values.
String _stamp(String raw) {
  if (raw.length < 10 || raw.startsWith('0001')) return '';
  return raw;
}

String _bytes(int value) {
  if (value <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value.toDouble();
  var unit = 0;
  while (size >= 1000 && unit < units.length - 1) {
    size /= 1000;
    unit++;
  }
  final digits = size >= 100 || unit == 0 ? 0 : (size >= 10 ? 1 : 2);
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}
