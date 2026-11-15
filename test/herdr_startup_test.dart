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

class _FakeBridge implements NativeBridge {
  static const statusReply = {'state': 'Running'};
  final _events = StreamController<BridgeEvent>.broadcast();
  int herdrDials = 0;
  String herdrError = '';

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

    test('only transient failures are retried', () {
      expect(HerdrFailure.unknownHost.retryable, isTrue);
      expect(HerdrFailure.timeout.retryable, isTrue);
      expect(HerdrFailure.auth.retryable, isFalse);
      expect(HerdrFailure.notInstalled.retryable, isFalse);
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
    testWidgets('three tries with backoff, then one human failure', (
      tester,
    ) async {
      final bridge = _FakeBridge()
        ..herdrError = 'connect bangwu:22: lookup bangwu: no such host';
      final herdr = HerdrController(bridge);
      HerdrLink? midLink;
      unawaited(
        herdr.connect(node: 'bangwu', attempts: herdrStartupAttempts).then((_) {
          midLink = herdr.link;
        }),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(bridge.herdrDials, herdrStartupAttempts);
      expect(herdr.link, HerdrLink.failed);
      expect(herdr.failure, HerdrFailure.unknownHost);
      expect(herdr.waking, isFalse);
      expect(midLink, HerdrLink.failed);
      expect(herdr.detail, contains('no such host'));
    });

    testWidgets('a retry that lands leaves the list ready', (tester) async {
      final bridge = _FakeBridge()
        ..herdrError = 'connect bangwu:22: lookup bangwu: no such host';
      final herdr = HerdrController(bridge);
      final done = herdr.connect(node: 'bangwu', attempts: 2);
      await tester.pump();
      bridge.herdrError = '';
      await tester.pump(const Duration(seconds: 1));
      await done;
      expect(herdr.link, HerdrLink.ready);
      expect(herdr.agents, hasLength(1));
      expect(herdr.failure, HerdrFailure.none);
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

  testWidgets('a saved target auto-connects and reports a human error', (
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

    // Still retrying: the page says so instead of showing the failure.
    expect(find.text('Connecting to herdr · bangwu'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(bridge.herdrDials, herdrStartupAttempts);
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
}
