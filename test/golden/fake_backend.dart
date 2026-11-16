import 'dart:async';
import 'dart:typed_data';

import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/native/bridge.dart';
import 'package:taildeck_ui/src/native/storage.dart';

class FakeBridge implements NativeBridge {
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

class MemoryStorage implements BackendStorage {
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

TaildeckBackend failedHerdrBackend(FakeBridge bridge) => TaildeckBackend(
  bridge: bridge,
  storage: MemoryStorage()
    ..config = const StoredConfig(signedIn: true, herdrNode: 'bangwu'),
);
