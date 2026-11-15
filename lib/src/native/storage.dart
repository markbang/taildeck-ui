import 'dart:convert';

import '../terminal_appearance.dart';
import '../terminal_gestures.dart';
import '../terminal_keys.dart';
import '../terminal_snippets.dart';
import 'storage_stub.dart' if (dart.library.io) 'storage_io.dart';

class StoredConfig {
  const StoredConfig({
    this.hostname = 'taildeck',
    this.controlURL = '',
    this.signedIn = false,
    this.openInApp = false,
    this.serviceIcons = true,
    this.agentNotifications = false,
    this.terminalKeyHaptics = true,
    this.terminalKeyPages,
    this.terminalFontSize = terminalFontDefault,
    this.terminalSwipeArrows = true,
    this.terminalKeyRowWithKeyboard = false,
    this.terminalSendEnter = true,
    this.terminalTheme = TerminalThemeId.follow,
    this.terminalFont = TerminalFontId.dejavu,
    this.terminalCursor = TerminalCursorId.follow,
    this.terminalCursorBlink = true,
    this.terminalKeepAlive = true,
    this.terminalSnippets = const [],
    this.herdrNode = '',
    this.herdrUser = 'root',
    this.herdrPort = 22,
    this.herdrAuth = 'tailscale',
    this.herdrIdentity = '',
    this.sshUsers = const {},
    this.sshPorts = const {},
  });

  factory StoredConfig.fromJson(Map<String, dynamic> json) => StoredConfig(
    hostname: json['hostname'] as String? ?? 'taildeck',
    controlURL: json['controlURL'] as String? ?? '',
    signedIn: json['signedIn'] as bool? ?? false,
    openInApp: json['openInApp'] as bool? ?? false,
    serviceIcons: json['serviceIcons'] as bool? ?? true,
    agentNotifications: json['agentNotifications'] as bool? ?? false,
    terminalKeyHaptics: json['terminalKeyHaptics'] as bool? ?? true,
    terminalKeyPages: json['terminalKeyPages'] == null
        ? null
        : parseTerminalKeyPages(json['terminalKeyPages']),
    terminalFontSize: clampTerminalFont(
      (json['terminalFontSize'] as num?)?.toDouble() ?? terminalFontDefault,
    ),
    terminalSwipeArrows: json['terminalSwipeArrows'] as bool? ?? true,
    terminalKeyRowWithKeyboard:
        json['terminalKeyRowWithKeyboard'] as bool? ?? false,
    terminalSendEnter: json['terminalSendEnter'] as bool? ?? true,
    terminalTheme: parseTerminalThemeId(json['terminalTheme']),
    terminalFont: parseTerminalFontId(json['terminalFont']),
    terminalCursor: parseTerminalCursorId(json['terminalCursor']),
    terminalCursorBlink: json['terminalCursorBlink'] as bool? ?? true,
    terminalKeepAlive: json['terminalKeepAlive'] as bool? ?? true,
    terminalSnippets: parseTerminalSnippets(json['terminalSnippets']),
    herdrNode: json['herdrNode'] as String? ?? '',
    herdrUser: json['herdrUser'] as String? ?? 'root',
    herdrPort: (json['herdrPort'] as num?)?.toInt() ?? 22,
    herdrAuth: json['herdrAuth'] as String? ?? 'tailscale',
    herdrIdentity: json['herdrIdentity'] as String? ?? '',
    sshUsers: switch (json['sshUsers']) {
      final Map<String, dynamic> map => {
        for (final entry in map.entries)
          if (entry.value case final String user when user.isNotEmpty)
            entry.key: user,
      },
      _ => const {},
    },
    sshPorts: switch (json['sshPorts']) {
      final Map<String, dynamic> map => {
        for (final entry in map.entries)
          if (entry.value case final num port when port >= 1 && port <= 65535)
            entry.key: port.toInt(),
      },
      _ => const {},
    },
  );

  final String hostname;
  final String controlURL;

  /// True when the node key in the tsnet state dir was authenticated.
  final bool signedIn;

  /// Whether services open in the in-app WebView (Android/iOS) or the browser.
  final bool openInApp;

  /// Whether service rows show the site's favicon.
  final bool serviceIcons;

  /// Whether agents post an attention notification while the app is away.
  final bool agentNotifications;

  /// Whether a press on the extra key row vibrates.
  final bool terminalKeyHaptics;

  /// Keys per page of the extra key row; null until the user edits it.
  final List<List<String>>? terminalKeyPages;

  /// Grid font size in points, kept across launches.
  final double terminalFontSize;

  /// Whether a one-finger swipe on the grid sends arrow keys.
  final bool terminalSwipeArrows;

  /// Whether the extra key row stays while a hardware keyboard is attached.
  final bool terminalKeyRowWithKeyboard;

  /// Whether Send presses Enter after the line. Off inserts the text only.
  final bool terminalSendEnter;
  /// Appearance: theme, family, cursor shape and blink.
  final TerminalThemeId terminalTheme;
  final TerminalFontId terminalFont;
  final TerminalCursorId terminalCursor;
  final bool terminalCursorBlink;

  /// Whether SSH sessions stay alive with the app in the background; off,
  /// they end when the app leaves the foreground.
  final bool terminalKeepAlive;

  /// Named commands in the terminal drawer.
  final List<TerminalSnippet> terminalSnippets;

  /// Node, user and auth the Agents page reconnects to herdr with. The
  /// password itself is never written.
  final String herdrNode;
  final String herdrUser;
  final int herdrPort;
  final String herdrAuth;
  final String herdrIdentity;

  /// Last SSH login and port per target (`sshLoginKey`); passwords are never
  /// written.
  final Map<String, String> sshUsers;
  final Map<String, int> sshPorts;

  Map<String, dynamic> toJson() => {
    'hostname': hostname,
    'controlURL': controlURL,
    'signedIn': signedIn,
    'openInApp': openInApp,
    'serviceIcons': serviceIcons,
    'agentNotifications': agentNotifications,
    'terminalKeyHaptics': terminalKeyHaptics,
    if (terminalKeyPages != null) 'terminalKeyPages': terminalKeyPages,
    'terminalFontSize': terminalFontSize,
    'terminalSwipeArrows': terminalSwipeArrows,
    'terminalKeyRowWithKeyboard': terminalKeyRowWithKeyboard,
    'terminalSendEnter': terminalSendEnter,
    'terminalTheme': terminalTheme.name,
    'terminalFont': terminalFont.name,
    'terminalCursor': terminalCursor.name,
    'terminalCursorBlink': terminalCursorBlink,
    'terminalKeepAlive': terminalKeepAlive,
    'terminalSnippets': [
      for (final snippet in terminalSnippets) snippet.toJson(),
    ],
    'herdrNode': herdrNode,
    'herdrUser': herdrUser,
    'herdrPort': herdrPort,
    'herdrAuth': herdrAuth,
    'herdrIdentity': herdrIdentity,
    'sshUsers': sshUsers,
    'sshPorts': sshPorts,
  };
}

/// Config key for a saved SSH login: the node, or one service on it.
String sshLoginKey(String node, {String service = ''}) =>
    service.isEmpty ? node : '$node/$service';

/// Whether tsnet's `tailscaled.state` holds an authenticated profile: the
/// FileStore keeps each value as base64 of its JSON, and a `Persist.NodeID`
/// set means the control server accepted this node's key. A key alone is not
/// enough, and reading one small file must not wait for the node to start.
bool savedLoginInState(String raw) {
  try {
    final state = jsonDecode(raw);
    if (state is! Map) return false;
    for (final value in state.values) {
      for (final text in _stateTexts(value)) {
        if (_signedInPrefs(text)) return true;
      }
    }
  } on Object {
    return false;
  }
  return false;
}

/// A state value both as the FileStore writes it (base64) and as plain JSON,
/// since older files may hold either.
List<String> _stateTexts(Object? value) {
  if (value is! String || value.isEmpty) return const [];
  try {
    return [utf8.decode(base64Decode(value)), value];
  } on FormatException {
    return [value];
  }
}

bool _signedInPrefs(String text) {
  try {
    final prefs = jsonDecode(text);
    if (prefs is! Map) return false;
    final persist = prefs['Persist'];
    if (persist is! Map) return false;
    final node = persist['NodeID'];
    return node is String && node.isNotEmpty;
  } on FormatException {
    return false;
  }
}

abstract class BackendStorage {
  /// tsnet state dir; created on demand.
  Future<String> stateDir();

  /// App-private SSH dir (keys live here); created on demand.
  Future<String> sshDir();
  Future<StoredConfig> readConfig();
  Future<void> writeConfig(StoredConfig config);

  /// Whether a signed-in tsnet profile is already on disk; one small read, so
  /// the first route does not wait for the node.
  Future<bool> hasSavedLogin();

  /// Raw `services.json`, or null when the file does not exist.
  Future<String?> readServicesJson();
  Future<void> writeServicesJson(String json);

  /// Raw `ssh/identities.json`, or null when nothing was imported yet.
  Future<String?> readIdentitiesJson();
  Future<void> writeIdentitiesJson(String json);

  /// Path of the imported key `ssh/<name>.key`.
  Future<String> sshKeyPath(String name);
  Future<void> writeSshKey(String name, String contents);
  Future<void> deleteSshKey(String name);
}

/// Null on web, where the app stays on mock data.
BackendStorage? openBackendStorage() => openStoragePlatform();
