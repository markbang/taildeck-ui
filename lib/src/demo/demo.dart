import 'package:flutter/foundation.dart' show kIsWeb;

import '../data.dart';
import '../services.dart';

/// Whether the demo dataset is compiled in: the web preview and debug builds
/// have it, a release build on a phone or desktop does not.
///
/// `--dart-define=TAILDECK_DEMO=true` brings it back for debugging on a device.
/// The flag is `const`, so the compiler drops every demo reference and its
/// strings from a release snapshot (see `tool/check_demo_free.sh`).
const bool demoData = bool.fromEnvironment(
  'TAILDECK_DEMO',
  defaultValue: kIsWeb,
);

/// The preview tailnet and its nodes, so a build without a backend still has
/// something to draw.
const demoNode = NodeItem(
  name: 'demo',
  ip: 'local',
  os: 'Terminal',
  online: true,
);

const demoSelfNode = NodeItem(
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

final demoPeers = <NodeItem>[
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

/// Demo timestamps stay recent so the mock node list reads like a live tailnet.
String _ago(Duration duration) =>
    DateTime.now().toUtc().subtract(duration).toIso8601String();

const demoTailnet = 'markbang.github';

enum DemoAgentState { working, idle, done }

/// The demo cards' task lines, so the sample data reads in both languages.
enum DemoTask { grafanaAlerts, releaseWorkflow, headscaleBump }

class DemoAgent {
  const DemoAgent({
    required this.name,
    required this.state,
    required this.project,
    required this.window,
    this.task = '',
    this.demoTask,
  });

  final String name;
  final DemoAgentState state;
  final String task;
  final DemoTask? demoTask;
  final String project;
  final String window;
}

const demoAgents = <({String section, List<DemoAgent> items})>[
  (
    section: 'Needs you',
    items: [
      DemoAgent(
        name: 'claude',
        state: DemoAgentState.done,
        demoTask: DemoTask.grafanaAlerts,
        project: 'infra',
        window: 'w3:p4',
      ),
    ],
  ),
  (
    section: 'taildeck',
    items: [
      DemoAgent(
        name: 'claude',
        state: DemoAgentState.working,
        demoTask: DemoTask.releaseWorkflow,
        project: 'taildeck',
        window: 'w1:p2',
      ),
      DemoAgent(
        name: 'codex',
        state: DemoAgentState.idle,
        project: 'taildeck',
        window: 'w1:p3',
      ),
    ],
  ),
  (
    section: 'router',
    items: [
      DemoAgent(
        name: 'pi',
        state: DemoAgentState.working,
        demoTask: DemoTask.headscaleBump,
        project: 'router',
        window: 'w2:p1',
      ),
    ],
  ),
];

/// The demo list's task line in the app's language.
String demoTaskText(DemoTask? task, {required bool zh}) => switch (task) {
  DemoTask.grafanaAlerts => zh ? '调整 Grafana 告警' : 'Tune Grafana alerts',
  DemoTask.releaseWorkflow => zh ? '添加发布流程' : 'Add release workflow',
  DemoTask.headscaleBump =>
    zh ? '升级 headscale 到 0.27' : 'Bump headscale to 0.27',
  null => '',
};

/// Shown in the web preview, which has no persistence.
const demoServices = <Service>[
  Service(
    id: 'demo-grafana',
    node: 'devbox',
    name: 'Grafana',
    url: 'http://devbox:3000/',
  ),
  Service(
    id: 'demo-code',
    node: 'devbox',
    name: 'code-server',
    url: 'http://devbox:8080/',
  ),
  Service(
    id: 'demo-dsm',
    node: 'nas',
    name: 'Synology DSM',
    url: 'https://nas:5001/',
  ),
  Service(
    id: 'demo-jellyfin',
    node: 'nas',
    name: 'Jellyfin',
    url: 'http://nas:8096/',
  ),
  Service(
    id: 'demo-hass',
    node: 'pi-k3s',
    name: 'Home Assistant',
    url: 'http://pi-k3s:8123/',
  ),
];

/// Lines the preview's Logs page shows instead of the bridge's ring, stamped
/// the way the bridge stamps them so the row summary reads true.
List<String> demoLogs() {
  final start = DateTime.now().subtract(const Duration(minutes: 5));
  String at(int seconds) {
    final t = start.add(Duration(seconds: seconds));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  return [
    '${at(0)} magicsock: home is now derp-12 (fra)',
    '${at(8)} control: netmap updated',
    '${at(74)} tailscale: state=running, backend=Running',
    '${at(141)} gateway: devbox:3000 → :4444',
    '${at(208)} herdr: 4 agents on devbox',
    '${at(285)} netcheck: udp=true portmap=UPnP',
  ];
}
