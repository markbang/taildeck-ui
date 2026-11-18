import 'package:flutter/widgets.dart';

/// What a login may look like: letters, digits and `.` `_` `-`, up to 32.
final sshUserPattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]{0,31}$');

bool isValidSshUser(String user) => sshUserPattern.hasMatch(user.trim());

class NodeItem {
  const NodeItem({
    required this.name,
    this.id = '',
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

  /// The tailnet's stable node id; empty for demo nodes.
  final String id;
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

  /// What Tailscale SSH would log in as: the tailnet login name for a
  /// user-owned node, empty for tagged nodes (no SSH user there).
  String get suggestedSshUser {
    if (tags.isNotEmpty) return '';
    final login = owner.split('@').first;
    return sshUserPattern.hasMatch(login) ? login : '';
  }

  Color get tint => switch (os) {
    'macOS' => const Color(0xFF7C8CFF),
    'Windows' => const Color(0xFF3FC1C9),
    'Android' || 'iOS' => const Color(0xFF9B7CFF),
    _ => const Color(0xFF4FB28A),
  };
}

const repoUrl = 'https://github.com/markbang/taildeck-ui';

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
    id: json['id'] as String? ?? '',
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
