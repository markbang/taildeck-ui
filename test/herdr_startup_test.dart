import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/agents_phase.dart';
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/herdr.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/bridge.dart';
import 'package:taildeck_ui/src/native/storage.dart';
import 'package:taildeck_ui/src/pages/agents.dart';
import 'package:taildeck_ui/src/pages/nodes.dart';

class _FakeBridge implements NativeBridge {
  /// A status from a cold start before the first netmap: the OS hostname, no
  /// address and no peer table (what the node reports while it is coming up).
  static const preNetmapStatus = {
    'state': 'Running',
    'netmap': false,
    'self': {'name': 'localhost', 'ips': <String>[], 'os': 'android'},
    'peers': <Object>[],
  };

  static const readyStatus = {
    'state': 'Running',
    'netmap': true,
    'self': {
      'name': 'taildeck',
      'ips': ['100.64.0.1'],
      'online': true,
      'os': 'linux',
    },
    'peers': [
      {
        'name': 'bangwu',
        'ips': ['100.64.0.2'],
        'online': true,
        'os': 'linux',
      },
    ],
  };

  Map<String, dynamic> statusReply = readyStatus;
  final _events = StreamController<BridgeEvent>.broadcast();
  int herdrDials = 0;
  String herdrError = '';

  /// Holds a dial open so a test can see the loading state.
  Completer<void>? herdrGate;

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> start({
    required String dir,
    String hostname = 'taildeck',
    String controlURL = '',
    String authKey = '',
    int gatewayPort = 0,
    String platform = 'go',
  }) async => {'gatewayPort': 19000};

  @override
  Future<Map<String, dynamic>> status() async => statusReply;

  @override
  Future<Map<String, dynamic>> herdrConnect({
    required String host,
    int port = 22,
    String user = 'root',
    String password = '',
    String keyPath = '',
    String passphrase = '',
    String certPath = '',
  }) async {
    herdrDials++;
    await herdrGate?.future;
    if (herdrError.isNotEmpty) throw BridgeException(herdrError);
    return {'id': 1};
  }

  @override
  Future<String> herdrCall(String method, [String paramsJSON = '{}']) async {
    if (method == 'agent.list') {
      return '{"agents":[{"pane_id":"w1:p1","agent":"claude","name":"one",'
          '"agent_status":"idle","workspace_id":"w1"}]}';
    }
    return '{"workspaces":[{"workspace_id":"w1","label":"deck"}]}';
  }

  @override
  Future<void> herdrClose() async {}

  @override
  Future<void> stop() async {}
  @override
  Future<void> logout() async {}
  @override
  void networkChanged() {}
  @override
  String logs() => '';
  @override
  int gatewayPort() => 0;
  @override
  Future<Map<String, dynamic>> ping(String ip) async => const {};
  @override
  void pingCancel(String ip) {}
  @override
  Future<List<int>> probe(String host, String ports) async => const [];
  @override
  Future<Map<String, dynamic>> favicon({
    required String host,
    required int port,
    required String scheme,
  }) async => const {};
  @override
  void dispose() {}
  @override
  Future<Map<String, dynamic>> sshDial({
    required String host,
    int port = 22,
    String user = 'root',
    String password = '',
    String keyPath = '',
    String passphrase = '',
    String certPath = '',
    int cols = 80,
    int rows = 24,
  }) async => const {};
  @override
  void sshWrite(int id, Uint8List data) {}
  @override
  void sshResize(int id, int cols, int rows) {}
  @override
  void sshClose(int id) {}
  @override
  Stream<SshOutput> sshOutput(int id) => const Stream.empty();
  @override
  String ensureKey(String path, {String comment = 'taildeck'}) => '';
  @override
  void forgetHostKeys(String dir) {}
  @override
  Future<String> herdrTranscript(String pane) async => '{}';
  @override
  Future<bool> herdrTranscriptMore(String pane) async => false;
  @override
  Future<String> herdrRestart(String pane, {String thenPrompt = ''}) async =>
      '';
  @override
  Future<String> herdrModels(String kind, String pane) async => '{}';
  @override
  Future<String> herdrCommands(String kind, String cwd) async => '[]';
  @override
  Future<Uint8List> herdrImage(String ref) async => Uint8List(0);
  @override
  Future<String> herdrUpload(String name, Uint8List data) async => '';
  @override
  Future<String> herdrSubagent(String pane, String callId) async => '{}';
}

class _MemoryStorage implements BackendStorage {
  StoredConfig config = const StoredConfig();
  final Map<String, String> keys = {};

  @override
  Future<String> stateDir() async => '/tmp/state';
  @override
  Future<String> sshDir() async => '/tmp/ssh';
  @override
  Future<bool> hasSavedLogin() async => false;
  @override
  Future<StoredConfig> readConfig() async => config;
  @override
  Future<void> writeConfig(StoredConfig value) async => config = value;
  @override
  Future<String?> readServicesJson() async => null;
  @override
  Future<void> writeServicesJson(String json) async {}
  @override
  Future<String?> readIdentitiesJson() async => null;
  @override
  Future<void> writeIdentitiesJson(String json) async {}
  @override
  Future<String> sshKeyPath(String name) async => '/tmp/ssh/$name.key';
  @override
  Future<void> writeSshKey(String name, String contents) async =>
      keys[name] = contents;
  @override
  Future<void> deleteSshKey(String name) async => keys.remove(name);
}

Widget _nodesApp(TaildeckBackend backend) => MediaQuery(
  data: const MediaQueryData(size: Size(414, 896)),
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: const [Locale('en'), Locale('zh')],
    home: BackendScope(
      backend: backend,
      child: Scaffold(
        body: NodesPage(onOpenNode: (_) {}, onToggleTheme: () {}),
      ),
    ),
  ),
);

Widget _app(TaildeckBackend backend) => MediaQuery(
  data: const MediaQueryData(size: Size(414, 896)),
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: const [Locale('en'), Locale('zh')],
    home: BackendScope(
      backend: backend,
      child: const Scaffold(body: AgentsPage()),
    ),
  ),
);

void main() {
  group('agentsPhaseOf', () {
    AgentsPhase phase({
      bool ready = false,
      bool waking = false,
      HerdrLink link = HerdrLink.idle,
      bool tailnet = false,
      bool target = false,
    }) => agentsPhaseOf(
      herdrReady: ready,
      waking: waking,
      link: link,
      tailnetReady: tailnet,
      hasTarget: target,
    );

    test('waits for the tailnet before any herdr state matters', () {
      expect(phase(), AgentsPhase.tailnet);
      expect(phase(link: HerdrLink.failed, target: true), AgentsPhase.tailnet);
      // A wake cannot start before the tailnet is up; if one is running, say so.
      expect(phase(waking: true), AgentsPhase.connecting);
    });

    test('a saved target connects instead of showing the form', () {
      expect(phase(tailnet: true, target: true), AgentsPhase.idle);
      expect(
        phase(tailnet: true, target: true, waking: true),
        AgentsPhase.connecting,
      );
      expect(
        phase(tailnet: true, ready: true, target: true),
        AgentsPhase.ready,
      );
    });

    test('no target is first setup, not an error', () {
      expect(phase(tailnet: true), AgentsPhase.setup);
    });

    test('only a finished dial shows a failure', () {
      expect(
        phase(tailnet: true, target: true, link: HerdrLink.failed),
        AgentsPhase.failed,
      );
      expect(
        phase(tailnet: true, target: true, link: HerdrLink.notInstalled),
        AgentsPhase.failed,
      );
    });
  });

  group('HerdrFailure', () {
    test('maps the Go messages people actually hit', () {
      expect(
        HerdrFailure.of('connect bangwu:22: lookup bangwu: no such host'),
        HerdrFailure.unknownHost,
      );
      expect(
        HerdrFailure.of('connect 100.64.0.2:22: i/o timeout'),
        HerdrFailure.timeout,
      );
      expect(
        HerdrFailure.of('connect 100.64.0.2:22: connection refused'),
        HerdrFailure.unreachable,
      );
      expect(
        HerdrFailure.of('ssh: handshake failed: unable to authenticate'),
        HerdrFailure.auth,
      );
      expect(
        HerdrFailure.of('HERDR_NOT_RUNNING: no server is running'),
        HerdrFailure.notRunning,
      );
      expect(
        HerdrFailure.of('HERDR_NOT_INSTALLED: herdr was not found'),
        HerdrFailure.notInstalled,
      );
    });

    test('the UI sentence never repeats the Go error', () {
      for (final locale in const [Locale('en'), Locale('zh')]) {
        final l10n = AppLocalizations(locale);
        final text = l10n.herdrFailure('bangwu', HerdrFailure.unknownHost);
        expect(text, isNot(contains('no such host')));
        expect(text, contains('bangwu'));
      }
    });
  });

  group('HerdrController', () {
    testWidgets('one dial, then the human failure', (tester) async {
      final bridge = _FakeBridge()
        ..herdrError = 'connect bangwu:22: lookup bangwu: no such host';
      final herdr = HerdrController(bridge);
      final done = herdr.connect(node: 'bangwu');
      expect(herdr.link, HerdrLink.connecting);
      expect(herdr.waking, isTrue);
      await done;
      expect(bridge.herdrDials, 1);
      expect(herdr.link, HerdrLink.failed);
      expect(herdr.failure, HerdrFailure.unknownHost);
      expect(herdr.waking, isFalse);
      expect(herdr.detail, contains('no such host'));
    });

    testWidgets('a manual retry dials once more and can land', (tester) async {
      final bridge = _FakeBridge()
        ..herdrError = 'connect bangwu:22: lookup bangwu: no such host';
      final herdr = HerdrController(bridge);
      await herdr.connect(node: 'bangwu');
      expect(bridge.herdrDials, 1);
      bridge.herdrError = '';
      final retry = herdr.connect(node: 'bangwu');
      await tester.pump();
      await retry;
      expect(bridge.herdrDials, 2);
      expect(herdr.link, HerdrLink.ready);
      expect(herdr.agents, hasLength(1));
      expect(herdr.failure, HerdrFailure.none);
    });
  });

  group('tailnet readiness', () {
    TaildeckBackend signedIn(_FakeBridge bridge) => TaildeckBackend(
      bridge: bridge,
      storage: _MemoryStorage()
        ..config = const StoredConfig(signedIn: true, herdrNode: 'bangwu'),
    );

    test('a Running status without a netmap is not ready', () async {
      final bridge = _FakeBridge()..statusReply = _FakeBridge.preNetmapStatus;
      final backend = signedIn(bridge);
      await backend.init();

      expect(backend.tailnetSignals, (
        running: true,
        netmap: false,
        selfIp: false,
      ));
      expect(backend.tailnetReady, isFalse);
      expect(backend.tailnetStarting, isTrue);
      // The OS hostname and an empty peer table are not a tailnet.
      expect(backend.self, isNull);
      expect(backend.peers, isEmpty);
      expect(bridge.herdrDials, 0);
      backend.dispose();
    });

    test('the first netmap makes it ready and dials herdr once', () async {
      final bridge = _FakeBridge();
      final backend = signedIn(bridge);
      await backend.init();

      expect(backend.tailnetReady, isTrue);
      expect(backend.self?.ip, '100.64.0.1');
      expect(backend.peers.map((peer) => peer.name), ['bangwu']);
      expect(backend.tailnetStarting, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.herdrDials, 1);
      backend.dispose();
    });

    testWidgets('the node page waits instead of drawing localhost', (
      tester,
    ) async {
      final backend = signedIn(
        _FakeBridge()..statusReply = _FakeBridge.preNetmapStatus,
      );
      await backend.init();
      await tester.pumpWidget(_nodesApp(backend));
      await tester.pump();

      expect(find.text('Connecting to the tailnet…'), findsOneWidget);
      expect(find.textContaining('localhost'), findsNothing);
      expect(find.text('No nodes yet.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      backend.dispose();
      await tester.pump();
    });
  });

  testWidgets('cold start: tailnet loading, no error and no form', (
    tester,
  ) async {
    final backend = TaildeckBackend(
      bridge: _FakeBridge(),
      storage: _MemoryStorage(),
    );
    await backend.init(); // signed out: the node never starts
    await tester.pumpWidget(_app(backend));
    await tester.pump();

    expect(find.text('Connecting to the tailnet…'), findsOneWidget);
    expect(find.text('Connect herdr'), findsNothing);
    expect(find.textContaining('no such host'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a saved target auto-connects once and reports a human error', (
    tester,
  ) async {
    final bridge = _FakeBridge()
      ..herdrError = 'connect bangwu:22: lookup bangwu: no such host';
    final storage = _MemoryStorage()
      ..config = const StoredConfig(signedIn: true, herdrNode: 'bangwu');
    final backend = TaildeckBackend(bridge: bridge, storage: storage);
    await backend.init();
    await tester.pumpWidget(_app(backend));
    await tester.pump();
    await tester.pump();

    expect(bridge.herdrDials, 1);
    expect(
      find.text("Can't find node bangwu — is it online and is MagicDNS on?"),
      findsOneWidget,
    );
    expect(find.textContaining('no such host'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    // The form is behind the settings row, not on the page.
    expect(find.text('Connect herdr'), findsNothing);
    await tester.tap(find.text('Connection settings'));
    await tester.pump();
    expect(find.text('Connect herdr'), findsOneWidget);

    // Drop the backend so its status poll does not outlive the test.
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
    await tester.pump();
  });

  testWidgets('Retry makes one manual dial with the same loading and error', (
    tester,
  ) async {
    final bridge = _FakeBridge()
      ..herdrError = 'connect bangwu:22: lookup bangwu: no such host';
    final storage = _MemoryStorage()
      ..config = const StoredConfig(signedIn: true, herdrNode: 'bangwu');
    final backend = TaildeckBackend(bridge: bridge, storage: storage);
    await backend.init();
    await tester.pumpWidget(_app(backend));
    await tester.pump();
    await tester.pump();
    expect(bridge.herdrDials, 1);
    expect(find.text('Retry'), findsOneWidget);

    bridge.herdrGate = Completer<void>();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    // Let the swap animation finish so only the new phase is on screen.
    await tester.pump(const Duration(milliseconds: 400));
    expect(bridge.herdrDials, 2);
    expect(find.text('Connecting to herdr · bangwu'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);

    bridge.herdrGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(bridge.herdrDials, 2);
    expect(
      find.text("Can't find node bangwu — is it online and is MagicDNS on?"),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    backend.dispose();
    await tester.pump();
  });
}
