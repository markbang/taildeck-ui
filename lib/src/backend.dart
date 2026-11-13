import 'dart:async';

import 'package:flutter/widgets.dart';

import 'data.dart';
import 'native/bridge.dart';
import 'native/storage.dart';

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
  TaildeckBackend({NativeBridge? bridge, BackendStorage? storage})
    : _bridge = bridge ?? openNativeBridge(),
      _storage = storage ?? openBackendStorage();

  static const defaultHostname = 'taildeck';
  static const gatewayPort = 18680;
  static const _refreshInterval = Duration(seconds: 5);
  static const _logLimit = 200;

  final NativeBridge? _bridge;
  final BackendStorage? _storage;
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
  String _tailnet = '';
  final List<String> _logs = [];

  bool get available => _bridge != null && _storage != null;
  BackendState get state => _state;
  String get error => _error;
  String get authUrl => _authUrl;
  String get hostname => _hostname;
  String get controlURL => _controlURL;
  NodeItem? get self => _self;
  List<NodeItem> get peers => _peers;
  String get tailnet => _tailnet.isEmpty ? _hostname : _tailnet;
  List<String> get logs => List.unmodifiable(_logs);

  /// The node key is accepted; the tunnel is up.
  bool get signedIn => _state == BackendState.running;
  bool get needsLogin => _state == BackendState.needsLogin;

  /// Start was requested and we are waiting for the user (or the control
  /// server) to finish signing in.
  bool get waitingForLogin =>
      _waitingForLogin &&
      (_state == BackendState.starting || _state == BackendState.needsLogin);

  Future<void> init() async {
    final bridge = _bridge;
    final storage = _storage;
    if (bridge == null || storage == null) return;
    _events = bridge.events.listen(_onEvent);
    try {
      final config = await storage.readConfig();
      _hostname = config.hostname;
      _controlURL = config.controlURL;
      _persistedSignIn = config.signedIn;
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
    _bridge?.dispose();
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
        gatewayPort: gatewayPort,
      );
      _started = true;
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
    _rawState = '';
    _state = BackendState.stopped;
    _authUrl = '';
    _waitingForLogin = false;
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
    }
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
