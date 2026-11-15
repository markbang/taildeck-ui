import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'data.dart';
import 'demo/demo.dart';
import 'favicons.dart';
import 'herdr.dart';
import 'native/bridge.dart';
import 'native/node_service.dart';
import 'native/platform_hooks.dart';
import 'native/ssh.dart';
import 'preview_env.dart';
import 'native/storage.dart';
import 'services.dart';
import 'notifications.dart';
import 'ssh_identities.dart';
import 'terminal_appearance.dart';
import 'terminal_gestures.dart';
import 'terminal_keys.dart';
import 'terminal_snippets.dart';

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
    _applyPreviewAppearance();
  }

  /// `?term=paper&font=systemMono&cursor=bar&blink=0` previews the terminal's
  /// look without a Settings round trip; it beats the stored config.
  void _applyPreviewAppearance() {
    final theme = previewParam('term');
    final font = previewParam('font');
    final cursor = previewParam('cursor');
    if (theme != null) _terminalTheme = parseTerminalThemeId(theme);
    if (font != null) _terminalFont = parseTerminalFontId(font);
    if (cursor != null) _terminalCursor = parseTerminalCursorId(cursor);
    if (previewParam('blink') == '0') _terminalCursorBlink = false;
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
  bool _sessionKnown = false;
  bool _hasPersistedLogin = false;
  final Completer<void> _session = Completer<void>();
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
  bool _serviceIcons = true;
  bool _terminalKeyHaptics = true;
  List<List<String>>? _terminalKeyPages;
  double _terminalFontSize = terminalFontDefault;
  bool _terminalSwipeArrows = true;
  bool _terminalKeyRowWithKeyboard = false;
  bool _terminalSendEnter = true;
  TerminalThemeId _terminalTheme = TerminalThemeId.follow;
  TerminalFontId _terminalFont = TerminalFontId.dejavu;
  TerminalCursorId _terminalCursor = TerminalCursorId.follow;
  bool _terminalCursorBlink = true;
  bool _terminalKeepAlive = true;
  List<TerminalSnippet> _terminalSnippets = const [];
  String _platform = 'go';
  String _platformWarning = '';
  bool _herdrAutoTried = false;
  String _herdrNode = '';
  String _herdrUser = 'root';
  int _herdrPort = 22;
  String _herdrAuth = 'tailscale';
  String _herdrIdentity = '';
  Map<String, String> _sshUsers = const {};
  Map<String, int> _sshPorts = const {};
  bool _foreground = true;
  bool _refreshing = false;
  bool _statusApplied = false;
  bool _herdrWaking = false;
  bool _cancelStart = false;
  String _pingIp = '';
  bool _serviceRunning = false;

  bool get available => _bridge != null && _storage != null;
  BackendState get state => _state;

  /// The node is still coming up: pages show progress, not an error or an
  /// empty list. `?tailnet=starting` previews that state on the web build.
  bool get tailnetStarting =>
      previewParam('tailnet') == 'starting' ||
      (available &&
          !_statusApplied &&
          _state != BackendState.error &&
          _state != BackendState.needsLogin);

  /// The node is Running and its first status (self and peers) has been read,
  /// so peer names can resolve.
  bool get tailnetReady =>
      _state == BackendState.running && _statusApplied;
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

  /// Whether service rows show the site's own favicon.
  bool get serviceIcons => _serviceIcons;

  /// Whether agents post an attention notification while the app is away.
  bool get agentNotifications => notifications.enabled;

  /// Whether a press on the extra key row vibrates.
  bool get terminalKeyHaptics => _terminalKeyHaptics;

  /// Keys per page of the extra key row, defaults included.
  List<List<String>> get terminalKeyPages =>
      _terminalKeyPages ?? defaultTerminalKeyPages;

  /// Grid font size in points, set by the pinch or Settings.
  double get terminalFontSize => _terminalFontSize;

  /// Whether a one-finger swipe on the grid sends arrow keys.
  bool get terminalSwipeArrows => _terminalSwipeArrows;

  /// Whether the extra key row stays while a hardware keyboard is attached.
  bool get terminalKeyRowWithKeyboard => _terminalKeyRowWithKeyboard;

  /// Whether Send presses Enter after the line; off inserts the text only.
  bool get terminalSendEnter => _terminalSendEnter;
  /// Appearance of the terminal page and grid.
  TerminalThemeId get terminalTheme => _terminalTheme;
  TerminalFontId get terminalFont => _terminalFont;
  TerminalCursorId get terminalCursor => _terminalCursor;
  bool get terminalCursorBlink => _terminalCursorBlink;

  /// Whether SSH sessions stay up while the app is in the background.
  bool get terminalKeepAlive => _terminalKeepAlive;

  /// Named commands for the terminal drawer.
  List<TerminalSnippet> get terminalSnippets => _terminalSnippets;

  /// herdr link, agent list and pane calls; null without a native backend.
  HerdrController? get herdr => _herdr;

  /// An automatic herdr connect (with its retries) is in flight.
  bool get herdrWaking => _herdrWaking;

  /// Last SSH user dialed for [target] (`sshLoginKey`), or '' when none was
  /// saved yet.
  String sshUserFor(String target) => _sshUsers[target] ?? '';

  /// Last SSH port dialed for [target], 22 when none was saved yet.
  int sshPortFor(String target) => _sshPorts[target] ?? 22;

  /// What a free login field offers for [target]: its last login, the node's
  /// tailnet login, then root.
  List<String> sshUserSuggestions(String target, {String login = ''}) => [
    for (final value in {sshUserFor(target), login, 'root'})
      if (value.isNotEmpty) value,
  ];

  /// Remembers the login for [target]; the password stays in memory only.
  Future<void> rememberSshLogin(
    String target, {
    required String user,
    required int port,
  }) async {
    final trimmed = user.trim();
    if (target.isEmpty ||
        trimmed.isEmpty ||
        port < 1 ||
        port > 65535 ||
        (_sshUsers[target] == trimmed && _sshPorts[target] == port)) {
      return;
    }
    _sshUsers = {..._sshUsers, target: trimmed};
    _sshPorts = {..._sshPorts, target: port};
    await _persist();
  }

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

  /// The saved login has been read, so the first route is known; the splash
  /// waits for this and never for the node.
  bool get sessionKnown => _sessionKnown;
  Future<void> get sessionReady => _session.future;

  /// A login is on disk: the config flag or an authenticated profile in the
  /// tsnet state dir.
  bool get hasPersistedLogin => _hasPersistedLogin;

  /// The shell is the right route: a saved login the node has not rejected.
  /// Pages keep their loading states until the node is Running.
  bool get showShell =>
      hasPersistedLogin && _state != BackendState.needsLogin;

  /// Start was requested and we are waiting for the user (or the control
  /// server) to finish signing in.
  bool get waitingForLogin =>
      _waitingForLogin &&
      (_state == BackendState.starting || _state == BackendState.needsLogin);

  Future<void> init() async {
    final bridge = _bridge;
    final storage = _storage;
    if (bridge == null || storage == null) {
      _sessionKnown = true;
      if (!_session.isCompleted) _session.complete();
      return;
    }
    _events = bridge.events.listen(_onEvent);
    // Only the saved login stands between the splash and the first route;
    // platform hooks, notifications and tsnet come after it.
    await _readSavedSession(storage);
    _sessionKnown = true;
    if (!_session.isCompleted) _session.complete();
    notifyListeners();
    await notifications.init();
    final mode = await resolvePlatformMode();
    _platform = mode.name;
    _platformWarning = mode.warning ?? '';
    if (_platformWarning.isNotEmpty) debugPrint('taildeck: $_platformWarning');
    // The tsnet state dir keeps the node key, so a saved login reconnects
    // without a new one.
    if (_hasPersistedLogin) await _start('');
    notifyListeners();
  }

  Future<void> _readSavedSession(BackendStorage storage) async {
    try {
      final config = await storage.readConfig();
      _hostname = config.hostname;
      _controlURL = config.controlURL;
      _persistedSignIn = config.signedIn;
      _openInApp = config.openInApp;
      _serviceIcons = config.serviceIcons;
      _terminalKeyHaptics = config.terminalKeyHaptics;
      _terminalKeyPages = config.terminalKeyPages;
      _terminalFontSize = config.terminalFontSize;
      _terminalSwipeArrows = config.terminalSwipeArrows;
      _terminalKeyRowWithKeyboard = config.terminalKeyRowWithKeyboard;
      _terminalSendEnter = config.terminalSendEnter;
      _terminalTheme = config.terminalTheme;
      _terminalFont = config.terminalFont;
      _terminalCursor = config.terminalCursor;
      _terminalCursorBlink = config.terminalCursorBlink;
      _terminalKeepAlive = config.terminalKeepAlive;
      _terminalSnippets = config.terminalSnippets;
      notifications.setEnabled(config.agentNotifications);
      _herdrNode = config.herdrNode;
      _herdrUser = config.herdrUser;
      _herdrPort = config.herdrPort;
      _herdrAuth = config.herdrAuth;
      _herdrIdentity = config.herdrIdentity;
      _sshUsers = config.sshUsers;
      _sshPorts = config.sshPorts;
    } on Object catch (error) {
      _fail(error);
    }
    // A config that cannot be read must not hide a node key that still works.
    _hasPersistedLogin = _persistedSignIn || await storage.hasSavedLogin();
  }

  Future<void> signInWithKey(String authKey, {String? controlURL}) async {
    if (!available) return;
    await _configure(controlURL);
    _waitingForLogin = true;
    _cancelStart = false;
    _error = '';
    notifyListeners();
    await _start(authKey.trim());
  }

  Future<void> signInInBrowser({String? controlURL}) async {
    if (!available) return;
    await _configure(controlURL);
    _waitingForLogin = true;
    _cancelStart = false;
    _error = '';
    notifyListeners();
    await _start('');
  }

  Future<void> refresh() async {
    final bridge = _bridge;
    if (bridge == null || !_started) return;
    if (_refreshing) return;
    _refreshing = true;
    try {
      final status = await bridge.status();
      if (!_started) return;
      _applyStatus(status);
    } on BridgeException catch (error) {
      // Keep the last known state: a status timeout must not sign the user out.
      _error = error.message;
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  /// Pings [ip]. Go gives up after 5 s; the 6 s guard here still answers when
  /// the library never returns, so the button cannot spin forever.
  Future<PingResult> ping(String ip) async {
    if (_bridge == null || !_started) {
      return const PingResult(error: 'node is not running');
    }
    return _pingThrough(ip);
  }

  /// The `?ping=1` preview calls the library even before the node is signed in,
  /// so the Android smoke test reaches the FFI path without a tailnet.
  Future<PingResult> previewPing(String ip) => _pingThrough(ip);

  Future<PingResult> _pingThrough(String ip) async {
    final bridge = _bridge;
    if (bridge == null) return const PingResult(error: 'node is not running');
    if (_pingIp.isNotEmpty && _pingIp != ip) pingCancel(_pingIp);
    _pingIp = ip;
    try {
      final reply = await bridge.ping(ip).timeout(const Duration(seconds: 6));
      return PingResult(
        latencyMs: (reply['latencyMs'] as num?)?.toDouble(),
        endpoint: reply['endpoint'] as String?,
        derp: reply['derp'] as String?,
        error: reply['error'] as String?,
      );
    } on TimeoutException {
      bridge.pingCancel(ip);
      return const PingResult(error: 'ping timed out after 6 s');
    } on BridgeException catch (error) {
      return PingResult(error: error.message);
    } finally {
      if (_pingIp == ip) _pingIp = '';
    }
  }

  /// Stops the ping in flight to [ip], so leaving the page frees the node.
  void pingCancel(String ip) {
    _bridge?.pingCancel(ip);
    if (_pingIp == ip) _pingIp = '';
  }

  /// Probes [ports] on [host] through the node; the reply lists the open ones.
  Future<List<int>> probe(String host, List<int> ports) async {
    final bridge = _bridge;
    if (bridge == null || !_started) {
      throw const BridgeException('the tailnet node is not running');
    }
    final open = await bridge.probe(host, ports.join(','));
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
    final reply = await bridge.sshDial(
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
    int attempts = 1,
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
      attempts: attempts,
    );
    if (herdr.ready) {
      _herdrNode = node;
      _herdrUser = user;
      _herdrPort = port;
      _herdrAuth = auth;
      _herdrIdentity = auth == 'key' ? identityId : '';
      _sshUsers = {..._sshUsers, node: user};
      _sshPorts = {..._sshPorts, node: port};
      await _persist();
    }
  }

  /// Reconnects to the saved herdr target after a startup failure, with the
  /// same retry budget as launch.
  Future<void> retryHerdr() async {
    if (_herdrNode.isEmpty || !tailnetReady) return;
    _herdrAutoTried = true;
    await _connectHerdrStartup();
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

  /// The bridge's ring on native; the preview's sample lines and the event
  /// buffer when there is no bridge.
  String logsText() {
    final bridge = _bridge;
    final head = _platformWarning.isEmpty
        ? ''
        : 'platform: $_platformWarning\n';
    if (bridge == null) {
      return head + (demoData ? [...demoLogs(), ..._logs] : _logs).join('\n');
    }
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

  /// The app's lifecycle: alerts fire only while it is away, and without
  /// background keep-alive the foreground service follows the app.
  void setForeground(bool value) {
    if (value == _foreground) return;
    _foreground = value;
    _syncService();
  }

  /// Language the notification text is written in.
  void setNotificationLanguage(String code) => notifications.setLanguage(code);

  Future<void> setOpenInApp(bool value) async {
    if (value == _openInApp) return;
    _openInApp = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setServiceIcons(bool value) async {
    if (value == _serviceIcons) return;
    _serviceIcons = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalKeyHaptics(bool value) async {
    if (value == _terminalKeyHaptics) return;
    _terminalKeyHaptics = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalFontSize(double size) async {
    final next = clampTerminalFont(size);
    if (next == _terminalFontSize) return;
    _terminalFontSize = next;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalSwipeArrows(bool value) async {
    if (value == _terminalSwipeArrows) return;
    _terminalSwipeArrows = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalKeyRowWithKeyboard(bool value) async {
    if (value == _terminalKeyRowWithKeyboard) return;
    _terminalKeyRowWithKeyboard = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalSendEnter(bool value) async {
    if (value == _terminalSendEnter) return;
    _terminalSendEnter = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalTheme(TerminalThemeId value) async {
    if (value == _terminalTheme) return;
    _terminalTheme = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalFont(TerminalFontId value) async {
    if (value == _terminalFont) return;
    _terminalFont = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalCursor(TerminalCursorId value) async {
    if (value == _terminalCursor) return;
    _terminalCursor = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setTerminalCursorBlink(bool value) async {
    if (value == _terminalCursorBlink) return;
    _terminalCursorBlink = value;
    notifyListeners();
    await _persist();
  }

  /// Background keep-alive; off, the Android foreground service stops with the
  /// app in the background and the shell ends its sessions.
  Future<void> setTerminalKeepAlive(bool value) async {
    if (value == _terminalKeepAlive) return;
    _terminalKeepAlive = value;
    notifyListeners();
    _syncService();
    await _persist();
  }

  Future<void> setTerminalSnippets(List<TerminalSnippet> value) async {
    final next = parseTerminalSnippets([
      for (final snippet in value) snippet.toJson(),
    ]);
    if (_snippetsSignature(next) == _snippetsSignature(_terminalSnippets)) {
      return;
    }
    _terminalSnippets = next;
    notifyListeners();
    await _persist();
  }

  static String _snippetsSignature(List<TerminalSnippet> snippets) => [
    for (final snippet in snippets)
      '${snippet.id}\u0000${snippet.name}\u0000${snippet.enter}\u0000${snippet.command}',
  ].join('\u0001');

  /// Pages of the extra key row; unknown ids and duplicates are dropped.
  Future<void> setTerminalKeyPages(List<List<String>> pages) async {
    final next = parseTerminalKeyPages(pages);
    if (_pagesSignature(next) == _pagesSignature(_terminalKeyPages)) return;
    _terminalKeyPages = next;
    notifyListeners();
    await _persist();
  }

  static String _pagesSignature(List<List<String>>? pages) =>
      pages == null ? '' : pages.map((page) => page.join(',')).join('|');

  /// The icon of [service], fetched through the node. Null while the node is
  /// not running: that is a transient state, never a site without an icon.
  Future<FaviconImage?> favicon(Service service) async {
    final bridge = _bridge;
    if (bridge == null || !_started) return null;
    final reply = await bridge.favicon(
      host: service.node,
      port: service.port,
      scheme: service.scheme,
    );
    final raw = reply['bytes'] as String? ?? '';
    if (raw.isEmpty) return null;
    return FaviconImage(
      bytes: base64Decode(raw),
      contentType: reply['contentType'] as String? ?? '',
      etag: reply['etag'] as String? ?? '',
      lastModified: reply['lastModified'] as String? ?? '',
      url: reply['url'] as String? ?? '',
    );
  }

  /// Sign-out drops the node key; the next launch starts at the login screen.
  Future<void> signOut() async {
    if (_bridge != null && _started) {
      try {
        await _bridge.logout();
      } on BridgeException catch (error) {
        _error = error.message;
      }
      await _stopNode();
    }
    _self = null;
    _peers = const [];
    _tailnet = '';
    _statusApplied = false;
    _herdrAutoTried = false;
    unawaited(_herdr?.disconnect() ?? Future<void>.value());
    _hasPersistedLogin = false;
    await _persist(signedIn: false);
    notifyListeners();
  }

  /// Cancels a pending sign-in without dropping an existing key.
  Future<void> cancelSignIn() async {
    _cancelStart = true;
    await _stopNode();
    _hasPersistedLogin = false;
    await _persist(signedIn: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _events?.cancel();
    final bridge = _bridge;
    // The event callback stays registered until the node is down: Go may still
    // emit while it closes, and calling a closed NativeCallable crashes.
    final stopping = bridge != null && _started
        ? bridge.stop().catchError((Object _) {})
        : Future<void>.value();
    _herdr?.dispose();
    unawaited(stopping.whenComplete(() => bridge?.dispose()));
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
      final reply = await bridge.start(
        dir: dir,
        hostname: _hostname,
        controlURL: _controlURL,
        authKey: authKey,
        gatewayPort: defaultGatewayPort,
        platform: _platform,
      );
      _started = true;
      if (_cancelStart) {
        // Sign-in was cancelled while the node was coming up.
        await _stopNode();
        return;
      }
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

  Future<void> _stopNode() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final bridge = _bridge;
    if (bridge != null && _started) {
      _started = false;
      try {
        await bridge.stop();
      } on BridgeException catch (error) {
        _error = error.message;
      }
    }
    _started = false;
    _gatewayPort = 0;
    _rawState = '';
    _statusApplied = false;
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
        if (_logs.length > _logLimit) {
          _logs.removeRange(0, _logs.length - _logLimit);
        }
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
    _self = self is Map<String, dynamic>
        ? nodeFromJson(self, isSelf: true)
        : null;
    _peers = [
      for (final peer in status['peers'] as List? ?? const [])
        if (peer is Map<String, dynamic>) nodeFromJson(peer),
    ];
    _statusApplied = true;
    // herdr needs the peer table, which only this reply brings.
    if (_state == BackendState.running) _autoConnectHerdr();
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
      _hasPersistedLogin = true;
      if (!_persistedSignIn) _persist(signedIn: true);
    }
    _syncService();
  }

  /// Android keeps the node in a foreground service while it runs and while
  /// the app is on screen, or in the background when the user keeps sessions
  /// alive; sign-out drops the node and with it the service.
  void _syncService() {
    final wanted =
        _state == BackendState.running &&
        (_foreground || _terminalKeepAlive);
    if (wanted == _serviceRunning) return;
    _serviceRunning = wanted;
    unawaited(wanted ? _service.start() : _service.stop());
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

  /// Reconnects to the herdr target of the last session, once per launch and
  /// only once the node is Running with its peer table read.
  void _autoConnectHerdr() {
    final herdr = _herdr;
    if (herdr == null || _herdrAutoTried || _herdrNode.isEmpty) return;
    if (herdr.ready || herdr.link == HerdrLink.connecting) return;
    if (!tailnetReady) return;
    _herdrAutoTried = true;
    unawaited(_connectHerdrStartup());
  }

  Future<void> _connectHerdrStartup() async {
    final herdr = _herdr;
    if (herdr == null || _herdrWaking || !tailnetReady) return;
    _herdrWaking = true;
    notifyListeners();
    try {
      await connectHerdr(
        node: _herdrNode,
        user: _herdrUser,
        port: _herdrPort,
        auth: _herdrAuth,
        identityId: _herdrIdentity.isEmpty ? builtinKeyId : _herdrIdentity,
        attempts: herdrStartupAttempts,
      );
    } on Object {
      // The Agents page turns the failure into a sentence and offers Retry.
    } finally {
      _herdrWaking = false;
      notifyListeners();
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
          openInApp: _openInApp,
          serviceIcons: _serviceIcons,
          terminalKeyHaptics: _terminalKeyHaptics,
          terminalKeyPages: _terminalKeyPages,
          terminalFontSize: _terminalFontSize,
          terminalSwipeArrows: _terminalSwipeArrows,
          terminalKeyRowWithKeyboard: _terminalKeyRowWithKeyboard,
          terminalSendEnter: _terminalSendEnter,
          terminalTheme: _terminalTheme,
          terminalFont: _terminalFont,
          terminalCursor: _terminalCursor,
          terminalCursorBlink: _terminalCursorBlink,
          terminalKeepAlive: _terminalKeepAlive,
          terminalSnippets: _terminalSnippets,
          agentNotifications: notifications.enabled,
          herdrNode: _herdrNode,
          herdrUser: _herdrUser,
          herdrPort: _herdrPort,
          herdrAuth: _herdrAuth,
          herdrIdentity: _herdrIdentity,
          sshUsers: _sshUsers,
          sshPorts: _sshPorts,
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
