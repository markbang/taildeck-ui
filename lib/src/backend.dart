import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'data.dart';
import 'herdr.dart';
import 'native/bridge.dart';
import 'native/node_service.dart';
import 'native/platform_hooks.dart';
import 'native/ssh.dart';
import 'native/storage.dart';
import 'notifications.dart';
import 'ssh_identities.dart';

enum BackendState { unavailable, stopped, starting, needsLogin, running, error }

class PingResult {
  const PingResult({this.latencyMs, this.endpoint, this.derp, this.error});

  final double? latencyMs;
  final String? endpoint;
  final String? derp;
  final String? error;

  bool get ok => error == null || error!.isEmpty;
}

/// Owns the Go tsnet node: config, start/stop, status polling and the event
/// stream. Web and missing-library hosts report [available] false and the UI
/// stays on mock data.
class TaildeckBackend extends ChangeNotifier {
  TaildeckBackend({
    NativeBridge? bridge,
    BackendStorage? storage,
    AgentNotifications? notifications,
  }) : this._(
         bridge ?? openNativeBridge(),
         storage ?? openBackendStorage(),
         notifications ?? AgentNotifications(),
       );

  TaildeckBackend._(this._bridge, this._storage, this.notifications)
    : _herdr = _bridge == null ? null : HerdrController(_bridge) {
    _herdr?.onAttention = _onAttention;
  }

  static const defaultHostname = 'taildeck';
  static const defaultGatewayPort = 18680;
  static const _refreshInterval = Duration(seconds: 5);
  static const _logLimit = 200;

  final NativeBridge? _bridge;
  final BackendStorage? _storage;
  final HerdrController? _herdr;
  final NodeService _service = openNodeService();

  /// Agent alerts; the settings page owns the toggle.
  final AgentNotifications notifications;
  StreamSubscription<BridgeEvent>? _events;
  Timer? _refreshTimer;

  BackendState _state = BackendState.stopped;
  String _rawState = '';
  String _authUrl = '';
  String _error = '';
  String _hostname = defaultHostname;
  String _controlURL = '';
  bool _started = false;
  bool _waitingForLogin = false;
  bool _persistedSignIn = false;
  NodeItem? _self;
  List<NodeItem> _peers = const [];
  int _gatewayPort = 0;
  String _tailnet = '';
  final List<String> _logs = [];
  String? _keyPath;
  String _builtinPublicKey = '';
  List<SshIdentity> _identities = const [];
  bool _identitiesLoaded = false;
  bool _openInApp = false;
  String _platform = 'go';
  String _platformWarning = '';
  bool _herdrAutoTried = false;
  String _herdrNode = '';
  String _herdrUser = 'root';
  int _herdrPort = 22;
  String _herdrAuth = 'tailscale';
  String _herdrIdentity = '';
  bool _foreground = true;
  bool _serviceRunning = false;

  bool get available => _bridge != null && _storage != null;
  BackendState get state => _state;
  String get error => _error;
  String get authUrl => _authUrl;
  String get hostname => _hostname;
  String get controlURL => _controlURL;
  NodeItem? get self => _self;
  List<NodeItem> get peers => _peers;
  List<NodeItem> get nodes => [?_self, ..._peers];

  /// `td_start` adapter: `host` when Android's Java hooks are installed,
  /// `go` everywhere else (and as the fallback).
  bool get hostPlatform => _platform == 'host';

  /// Why the Android platform hooks could not be installed; empty when the
  /// node has the adapters it wants. Shown at the top of the log page.
  String get platformWarning => _platformWarning;

  /// Loopback gateway port from `td_start`; 0 while the node is not running.
  int get gatewayPort => _gatewayPort;
  String get tailnet => _tailnet.isEmpty ? _hostname : _tailnet;
  List<String> get logs => List.unmodifiable(_logs);

  /// Services open in the in-app WebView on Android/iOS, the browser elsewhere.
  bool get openInApp => _openInApp;

  /// Whether agents post an attention notification while the app is away.
  bool get agentNotifications => notifications.enabled;

  /// herdr link, agent list and pane calls; null without a native backend.
  HerdrController? get herdr => _herdr;

  /// What the Agents page prefills the connection form with.
  ({String node, String user, int port, String auth, String identity})
  get herdrTarget => (
    node: _herdrNode,
    user: _herdrUser,
    port: _herdrPort,
    auth: _herdrAuth,
    identity: _herdrIdentity,
  );

  /// The node key is accepted; the tunnel is up.
  bool get signedIn => _state == BackendState.running;
  bool get needsLogin => _state == BackendState.needsLogin;

  /// Start was requested and we are waiting for the user (or the control
  /// server) to finish signing in.
  bool get waitingForLogin =>
      _waitingForLogin &&
      (_state == BackendState.starting || _state == BackendState.needsLogin);

  Future<void> init() async {
    await notifications.init();
    final bridge = _bridge;
    final storage = _storage;
    if (bridge == null || storage == null) return;
    _events = bridge.events.listen(_onEvent);
    final mode = await resolvePlatformMode();
    _platform = mode.name;
    _platformWarning = mode.warning ?? '';
    if (_platformWarning.isNotEmpty) debugPrint('taildeck: $_platformWarning');
    try {
      final config = await storage.readConfig();
      _hostname = config.hostname;
      _controlURL = config.controlURL;
      _persistedSignIn = config.signedIn;
      _openInApp = config.openInApp;
      notifications.setEnabled(config.agentNotifications);
      _herdrNode = config.herdrNode;
      _herdrUser = config.herdrUser;
      _herdrPort = config.herdrPort;
      _herdrAuth = config.herdrAuth;
      _herdrIdentity = config.herdrIdentity;
      // The tsnet state dir keeps the node key, so a previous session can
      // reconnect without a new key.
      if (config.signedIn) await _start('');
    } on Object catch (error) {
      _fail(error);
    }
    notifyListeners();
  }

  Future<void> signInWithKey(String authKey, {String? controlURL}) async {
    if (!available) return;
    await _configure(controlURL);
    _waitingForLogin = true;
    _error = '';
    notifyListeners();
    await _start(authKey.trim());
  }

  Future<void> signInInBrowser({String? controlURL}) async {
    if (!available) return;
    await _configure(controlURL);
    _waitingForLogin = true;
    _error = '';
    notifyListeners();
    await _start('');
  }

  Future<void> refresh() async {
    if (_bridge == null || !_started) return;
    try {
      _applyStatus(_bridge.status());
    } on BridgeException catch (error) {
      // Keep the last known state: a status timeout must not sign the user out.
      _error = error.message;
      notifyListeners();
    }
  }

  Future<PingResult> ping(String ip) async {
    if (_bridge == null || !_started) {
      return const PingResult(error: 'node is not running');
    }
    try {
      final reply = _bridge.ping(ip);
      return PingResult(
        latencyMs: (reply['latencyMs'] as num?)?.toDouble(),
        endpoint: reply['endpoint'] as String?,
        derp: reply['derp'] as String?,
        error: reply['error'] as String?,
      );
    } on BridgeException catch (error) {
      return PingResult(error: error.message);
    }
  }

  /// Probes [ports] on [host] through the node; the reply lists the open ones.
  Future<List<int>> probe(String host, List<int> ports) async {
    final bridge = _bridge;
    if (bridge == null || !_started) {
      throw const BridgeException('the tailnet node is not running');
    }
    final open = bridge.probe(host, ports.join(','));
    open.sort();
    return open;
  }

  /// Public half of the built-in ed25519 key; created on first use.
  Future<String> ensureBuiltinKey() async {
    final bridge = _bridge;
    final storage = _storage;
    if (bridge == null || storage == null) {
      throw const BridgeException('native backend is unavailable');
    }
    if (_builtinPublicKey.isNotEmpty) return _builtinPublicKey;
    final dir = await storage.sshDir();
    final path = '$dir/id_ed25519';
    _builtinPublicKey = bridge.ensureKey(path, comment: 'taildeck@$_hostname');
    _keyPath = path;
    return _builtinPublicKey;
  }

  /// Built-in key first, then imported keys. Creates the built-in key so its
  /// public line can be shown and copied.
  Future<List<SshIdentity>> sshIdentities() async {
    if (_bridge == null || _storage == null) return const [];
    await _loadIdentities();
    var publicKey = _builtinPublicKey;
    if (publicKey.isEmpty) {
      try {
        publicKey = await ensureBuiltinKey();
      } on BridgeException {
        // The row stays listed; the settings page reports the failure.
      }
    }
    return [
      SshIdentity(
        id: builtinKeyId,
        name: 'Taildeck',
        publicKey: publicKey,
        builtin: true,
      ),
      ..._identities,
    ];
  }

  /// Writes `ssh/<id>.key` and remembers its passphrase.
  Future<SshIdentity> importSshKey({
    required String name,
    required String pem,
    String passphrase = '',
  }) async {
    final storage = _storage;
    if (_bridge == null || storage == null) {
      throw const SshKeyException(SshKeyError.unavailable);
    }
    final trimmed = name.trim();
    final id = sshKeyId(trimmed);
    if (trimmed.isEmpty || !isUsableKeyId(id)) {
      throw const SshKeyException(SshKeyError.nameInvalid);
    }
    await _loadIdentities();
    if (_identities.any((key) => key.id == id)) {
      throw const SshKeyException(SshKeyError.nameTaken);
    }
    final normalized = normalizePrivateKey(pem) ?? '${pem.trim()}\n';
    final identity = SshIdentity(
      id: id,
      name: trimmed,
      publicKey: sshPublicKeyOf(normalized) ?? '',
      passphrase: passphrase.trim(),
    );
    try {
      await storage.writeSshKey(id, normalized);
      await _saveIdentities([..._identities, identity]);
    } on Object {
      throw const SshKeyException(SshKeyError.io);
    }
    return identity;
  }

  /// Deletes an imported key and its file; the built-in key stays.
  Future<void> deleteSshKey(SshIdentity identity) async {
    if (identity.builtin) return;
    final storage = _storage;
    if (storage == null) {
      throw const SshKeyException(SshKeyError.unavailable);
    }
    try {
      await storage.deleteSshKey(identity.id);
      await _saveIdentities([
        for (final key in _identities)
          if (key.id != identity.id) key,
      ]);
    } on Object {
      throw const SshKeyException(SshKeyError.io);
    }
  }

  /// Path and passphrase to hand to `td_ssh_dial` for [id].
  Future<({String path, String passphrase})> sshKeyFor(String id) async {
    final storage = _storage;
    if (storage == null) {
      throw const BridgeException('native backend is unavailable');
    }
    if (id.isEmpty || id == builtinKeyId) {
      await ensureBuiltinKey();
      return (path: _keyPath ?? '', passphrase: '');
    }
    await _loadIdentities();
    for (final key in _identities) {
      if (key.id == id) {
        return (path: await storage.sshKeyPath(id), passphrase: key.passphrase);
      }
    }
    throw BridgeException('SSH key "$id" not found');
  }

  Future<void> _loadIdentities() async {
    if (_identitiesLoaded) return;
    _identitiesLoaded = true;
    final storage = _storage;
    if (storage == null) return;
    try {
      final raw = await storage.readIdentitiesJson();
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _identities = [
        for (final item in decoded)
          if (item is Map<String, dynamic>) SshIdentity.fromJson(item),
      ];
    } on Object catch (error) {
      debugPrint('taildeck: could not read ssh identities: $error');
    }
  }

  Future<void> _saveIdentities(List<SshIdentity> list) async {
    _identities = list;
    await _storage?.writeIdentitiesJson(
      jsonEncode([for (final key in list) key.toJson()]),
    );
  }

  /// Opens a PTY shell on [host] over the tailnet. Dialing continues in the
  /// background; output and the close reason arrive on [SshSession.output].
  Future<SshSession> openSshSession({
    required String host,
    required String user,
    int port = 22,
    String password = '',
    String identityId = builtinKeyId,
    int cols = 80,
    int rows = 24,
  }) async {
    final bridge = _bridge;
    if (bridge == null) {
      throw const BridgeException('native backend is unavailable');
    }
    final key = await sshKeyFor(identityId);
    final reply = bridge.sshDial(
      host: host,
      port: port,
      user: user,
      password: password,
      keyPath: key.path,
      passphrase: key.passphrase,
      cols: cols,
      rows: rows,
    );
    final id = (reply['id'] as num?)?.toInt();
    if (id == null) throw const BridgeException('ssh_dial returned no id');
    return SshSession(bridge, id);
  }

  /// Attaches to herdr on [node] with the same SSH credentials as [auth]
  /// (`tailscale`, `key` or `password`). The target is kept for the next launch.
  Future<void> connectHerdr({
    required String node,
    required String user,
    int port = 22,
    String auth = 'tailscale',
    String identityId = builtinKeyId,
    String password = '',
  }) async {
    final herdr = _herdr;
    if (herdr == null) {
      throw const BridgeException('native backend is unavailable');
    }
    if (!signedIn) {
      throw const BridgeException('the tailnet node is not running');
    }
    var keyPath = '';
    var passphrase = '';
    if (auth == 'key') {
      final key = await sshKeyFor(identityId);
      keyPath = key.path;
      passphrase = key.passphrase;
    }
    await herdr.connect(
      node: node,
      port: port,
      user: user,
      password: auth == 'password' ? password : '',
      keyPath: keyPath,
      passphrase: passphrase,
    );
    if (herdr.ready) {
      _herdrNode = node;
      _herdrUser = user;
      _herdrPort = port;
      _herdrAuth = auth;
      _herdrIdentity = auth == 'key' ? identityId : '';
      await _persist();
    }
  }

  /// Forgets trusted host keys, so the next connection trusts them again.
  Future<void> forgetSshHostKeys() async {
    final bridge = _bridge;
    final storage = _storage;
    if (bridge == null || storage == null) {
      throw const BridgeException('native backend is unavailable');
    }
    bridge.forgetHostKeys(await storage.stateDir());
  }

  /// `td_logs()` on native; the event buffer when there is no bridge.
  String logsText() {
    final bridge = _bridge;
    final head = _platformWarning.isEmpty ? '' : 'platform: $_platformWarning\n';
    if (bridge == null) return head + _logs.join('\n');
    try {
      return head + bridge.logs();
    } on BridgeException {
      return head + _logs.join('\n');
    }
  }

  /// Turns agent alerts on (asking the OS first) or off; false when the OS
  /// refuses, which the settings page explains.
  Future<bool> setAgentNotifications(bool value) async {
    if (!value) {
      notifications.setEnabled(false);
      await _persist();
      notifyListeners();
      return false;
    }
    final granted = await notifications.requestPermission();
    notifications.setEnabled(granted);
    await _persist();
    notifyListeners();
    return granted;
  }

  /// The app's lifecycle, so alerts only fire while it is away.
  void setForeground(bool value) => _foreground = value;

  /// Language the notification text is written in.
  void setNotificationLanguage(String code) => notifications.setLanguage(code);

  Future<void> setOpenInApp(bool value) async {
    if (value == _openInApp) return;
    _openInApp = value;
    notifyListeners();
    await _persist();
  }

  /// Sign-out drops the node key; the next launch starts at the login screen.
  Future<void> signOut() async {
    if (_bridge != null && _started) {
      try {
        _bridge.logout();
      } on BridgeException catch (error) {
        _error = error.message;
      }
      _stopNode();
    }
    _self = null;
    _peers = const [];
    _tailnet = '';
    _herdrAutoTried = false;
    unawaited(_herdr?.disconnect() ?? Future<void>.value());
    await _persist(signedIn: false);
    notifyListeners();
  }

  /// Cancels a pending sign-in without dropping an existing key.
  Future<void> cancelSignIn() async {
    _stopNode();
    await _persist(signedIn: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _events?.cancel();
    if (_bridge != null && _started) {
      try {
        _bridge.stop();
      } on BridgeException {
        // Shutting down anyway.
      }
    }
    _herdr?.dispose();
    _bridge?.dispose();
    if (_serviceRunning) unawaited(_service.stop());
    _serviceRunning = false;
    super.dispose();
  }

  Future<void> _configure(String? controlURL) async {
    if (controlURL != null) _controlURL = controlURL.trim();
    await _persist(signedIn: _persistedSignIn);
  }

  Future<void> _start(String authKey) async {
    final bridge = _bridge;
    final storage = _storage;
    if (bridge == null || storage == null) return;
    try {
      final dir = await storage.stateDir();
      final reply = bridge.start(
        dir: dir,
        hostname: _hostname,
        controlURL: _controlURL,
        authKey: authKey,
        gatewayPort: defaultGatewayPort,
        platform: _platform,
      );
      _started = true;
      _gatewayPort = (reply['gatewayPort'] as num?)?.toInt() ?? 0;
      _rawState = 'Starting';
      _state = BackendState.starting;
      _error = '';
      debugPrint('taildeck: started, gateway ${reply['gatewayPort']}');
      _scheduleRefresh();
      notifyListeners();
      await refresh();
    } on Object catch (error) {
      _fail(error);
      _waitingForLogin = false;
      notifyListeners();
    }
  }

  void _stopNode() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_bridge != null && _started) {
      try {
        _bridge.stop();
      } on BridgeException catch (error) {
        _error = error.message;
      }
    }
    _started = false;
    _gatewayPort = 0;
    _rawState = '';
    _state = BackendState.stopped;
    _authUrl = '';
    _waitingForLogin = false;
    _syncService();
  }

  void _onEvent(BridgeEvent event) {
    switch (event.kind) {
      case BridgeEventKind.state:
        final state = event.state;
        if (state.isNotEmpty) _setState(state);
        final url = event.data['authUrl'] as String? ?? '';
        if (url.isNotEmpty) _authUrl = url;
        notifyListeners();
        unawaited(refresh());
      case BridgeEventKind.login:
        if (event.url.isNotEmpty) _authUrl = event.url;
        notifyListeners();
      case BridgeEventKind.log:
        final line = event.line;
        if (line.isEmpty) return;
        _logs.add(line);
        if (_logs.length > _logLimit) _logs.removeRange(0, _logs.length - _logLimit);
      case BridgeEventKind.sshData || BridgeEventKind.sshClosed:
        // Session frames reach their own stream, not the backend.
        return;
      case BridgeEventKind.herdr:
        _herdr?.onEvent(event);
        return;
    }
  }

  void _applyStatus(Map<String, dynamic> status) {
    _setState(status['state'] as String? ?? _rawState);
    final url = status['authUrl'] as String? ?? '';
    if (url.isNotEmpty) _authUrl = url;
    _tailnet = status['tailnet'] as String? ?? _tailnet;
    final self = status['self'];
    _self = self is Map<String, dynamic> ? nodeFromJson(self, isSelf: true) : null;
    _peers = [
      for (final peer in status['peers'] as List? ?? const [])
        if (peer is Map<String, dynamic>) nodeFromJson(peer),
    ];
    notifyListeners();
  }

  void _setState(String raw) {
    if (raw.isEmpty) return;
    _rawState = raw;
    _state = switch (raw) {
      'Running' => BackendState.running,
      'NeedsLogin' => BackendState.needsLogin,
      'Stopped' => BackendState.stopped,
      'NoState' || 'Starting' => BackendState.starting,
      _ => BackendState.starting,
    };
    if (_state == BackendState.running) {
      _waitingForLogin = false;
      if (!_persistedSignIn) _persist(signedIn: true);
      _autoConnectHerdr();
    }
    _syncService();
  }

  /// Android keeps the node in a foreground service only while it runs.
  void _syncService() {
    final running = _state == BackendState.running;
    if (running == _serviceRunning) return;
    _serviceRunning = running;
    unawaited(running ? _service.start() : _service.stop());
  }

  /// A pane turned blocked or done while the app is away.
  void _onAttention(HerdrAgent agent) {
    if (_foreground) return;
    unawaited(
      notifications.show(
        agent,
        needsInput: agent.status == HerdrStatus.blocked,
      ),
    );
  }

  /// Reconnects to the herdr target of the last session, once per launch.
  void _autoConnectHerdr() {
    final herdr = _herdr;
    if (herdr == null || _herdrAutoTried || _herdrNode.isEmpty) return;
    if (herdr.ready || herdr.link == HerdrLink.connecting) return;
    _herdrAutoTried = true;
    unawaited(() async {
      try {
        await connectHerdr(
          node: _herdrNode,
          user: _herdrUser,
          port: _herdrPort,
          auth: _herdrAuth,
          identityId: _herdrIdentity.isEmpty ? builtinKeyId : _herdrIdentity,
        );
      } on Object {
        // The Agents page shows the link state and the reason.
      }
    }());
  }

  Future<void> _persist({bool? signedIn}) async {
    if (_storage == null) return;
    final persist = signedIn ?? _persistedSignIn;
    _persistedSignIn = persist;
    try {
      await _storage.writeConfig(
        StoredConfig(
          hostname: _hostname,
          controlURL: _controlURL,
          signedIn: persist,
          openInApp: _openInApp,
          agentNotifications: notifications.enabled,
          herdrNode: _herdrNode,
          herdrUser: _herdrUser,
          herdrPort: _herdrPort,
          herdrAuth: _herdrAuth,
          herdrIdentity: _herdrIdentity,
        ),
      );
    } on Object catch (error) {
      _error = 'Could not save config: $error';
    }
  }

  void _scheduleRefresh() {
    if (_refreshTimer != null || !_started) return;
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => refresh());
  }

  void _fail(Object error) {
    _error = switch (error) {
      BridgeException() => error.message,
      _ => '$error',
    };
    _state = BackendState.error;
    _syncService();
  }
}

/// Makes the backend reachable from the pages; rebuilds on state changes.
class BackendScope extends InheritedNotifier<TaildeckBackend> {
  const BackendScope({
    super.key,
    required TaildeckBackend backend,
    required super.child,
  }) : super(notifier: backend);

  static TaildeckBackend of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BackendScope>();
    assert(scope != null, 'BackendScope missing above this widget');
    return scope!.notifier!;
  }
}
