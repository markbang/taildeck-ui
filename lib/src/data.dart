import 'package:flutter/widgets.dart';

class NodeItem {
  const NodeItem({
    required this.name,
    required this.ip,
    required this.os,
    required this.online,
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
  final bool direct;
  final String? relay;
  final String rx;
  final String tx;
  final List<String> tags;
  final List<String> routes;
  final bool isSelf;
  final String owner;
  final String expiry;
  final String dns;

  Color get tint => switch (os) {
    'macOS' => const Color(0xFF7C8CFF),
    'Windows' => const Color(0xFF3FC1C9),
    'Android' || 'iOS' => const Color(0xFF9B7CFF),
    _ => const Color(0xFF4FB28A),
  };
}

const tailnet = 'markbang.github';

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

const peers = <NodeItem>[
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
    rx: '1.2 GB',
    tx: '640 MB',
    dns: 'win-gaming.tail4a2c.ts.net',
  ),
];

class ServiceItem {
  const ServiceItem({
    required this.name,
    required this.node,
    required this.port,
    required this.tint,
    this.glyph,
  });

  final String name;
  final String node;
  final int port;
  final Color tint;
  final String? glyph;
}

const services = <ServiceItem>[
  ServiceItem(name: 'Grafana', node: 'devbox', port: 3000, tint: Color(0xFFF08C2E), glyph: 'G'),
  ServiceItem(name: 'code-server', node: 'devbox', port: 8080, tint: Color(0xFF4E8CFF), glyph: 'C'),
  ServiceItem(name: 'Synology DSM', node: 'nas', port: 5001, tint: Color(0xFF5C6BC0), glyph: 'S'),
  ServiceItem(name: 'Jellyfin', node: 'nas', port: 8096, tint: Color(0xFFA855F7), glyph: 'J'),
  ServiceItem(name: 'Home Assistant', node: 'pi-k3s', port: 8123, tint: Color(0xFF38BDF8), glyph: 'H'),
  ServiceItem(name: 'Sunshine', node: 'win-gaming', port: 47990, tint: Color(0xFF64748B), glyph: 'S'),
];

enum AgentState { working, idle, done }

class AgentItem {
  const AgentItem({
    required this.name,
    required this.state,
    required this.task,
    required this.project,
    required this.window,
    this.agent = '',
  });

  final String name;
  final AgentState state;
  final String task;
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
        task: 'Tune Grafana alerts',
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
        task: 'Add release workflow',
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
        task: 'Bump headscale to 0.27',
        project: 'router',
        window: 'w2:p1',
      ),
    ],
  ),
];
