import 'data.dart';
import 'herdr.dart' show HerdrFailure;
import 'l10n.dart';
import 'ssh_identities.dart' show builtinKeyId;

enum SshAuth { tailscale, password, key }

enum ConnectionAction { ssh, ping }

SshAuth? parseSshAuth(Object? raw) {
  for (final auth in SshAuth.values) {
    if (auth.name == raw) return auth;
  }
  return null;
}

/// How one device was last reached. Passwords are never part of it.
class SavedConnection {
  const SavedConnection({
    this.action = ConnectionAction.ssh,
    this.user = '',
    this.port = 22,
    this.auth,
    this.identityId = '',
  });

  factory SavedConnection.fromJson(Map<String, dynamic> json) =>
      SavedConnection(
        action: json['action'] == ConnectionAction.ping.name
            ? ConnectionAction.ping
            : ConnectionAction.ssh,
        user: json['user'] as String? ?? '',
        port: switch (json['port']) {
          final num port when port >= 1 && port <= 65535 => port.toInt(),
          _ => 22,
        },
        auth: parseSshAuth(json['auth']),
        identityId: json['identity'] as String? ?? '',
      );

  final ConnectionAction action;
  final String user;
  final int port;

  /// Null for a login carried over from the old per-host user/port maps: its
  /// auth was never recorded, so the first tap still goes through the menu.
  final SshAuth? auth;

  /// The key used with [SshAuth.key]; empty otherwise.
  final String identityId;

  /// A tap acts on this connection without the menu.
  bool get ready =>
      action == ConnectionAction.ping || (auth != null && user.isNotEmpty);

  /// The key to dial with: the remembered one for key auth, the built-in one
  /// otherwise.
  String get dialIdentity =>
      auth == SshAuth.key && identityId.isNotEmpty ? identityId : builtinKeyId;

  Map<String, dynamic> toJson() => {
    'action': action.name,
    if (user.isNotEmpty) 'user': user,
    'port': port,
    if (auth != null) 'auth': auth!.name,
    if (identityId.isNotEmpty) 'identity': identityId,
  };
}

/// Config key of a device: its tailnet stable id, or the hostname for a node
/// that reports none (demo nodes, entries from before ids were kept).
String deviceKey(NodeItem node) => node.id.isNotEmpty ? node.id : node.name;

/// Per-host logins from `sshUsers`/`sshPorts`, as device entries keyed by
/// hostname. Service-scoped keys (`node/service`) stay where they are.
Map<String, SavedConnection> migrateSshLogins(
  Map<String, String> users,
  Map<String, int> ports,
) => {
  for (final entry in users.entries)
    if (!entry.key.contains('/'))
      entry.key: SavedConnection(
        user: entry.value,
        port: ports[entry.key] ?? 22,
      ),
};

enum TapPlan { menu, dial, sheet, ping }

/// What a tap on a device does with what was saved for it. Password auth asks
/// for the password every time, since it is never stored.
TapPlan planTap(SavedConnection? saved) {
  if (saved == null || !saved.ready) return TapPlan.menu;
  if (saved.action == ConnectionAction.ping) return TapPlan.ping;
  if (saved.auth == SshAuth.password) return TapPlan.sheet;
  return TapPlan.dial;
}

/// Dials [saved] once; on failure the sheet opens with the reason and the
/// same values. There is no fallback to another auth method.
Future<T?> connectRemembered<T>({
  required SavedConnection saved,
  required Future<T> Function(SavedConnection saved) dial,
  required Future<T?> Function(Object error) openSheet,
}) async {
  try {
    return await dial(saved);
  } on Object catch (error) {
    return openSheet(error);
  }
}

String authLabel(AppLocalizations l10n, SshAuth auth) => switch (auth) {
  SshAuth.tailscale => l10n.authTailscale,
  SshAuth.password => l10n.authPassword,
  SshAuth.key => l10n.authKey,
};

/// The row's read-only summary, e.g. `SSH · bangwu · Tailscale SSH`.
String connectionLabel(AppLocalizations l10n, SavedConnection saved) {
  if (saved.action == ConnectionAction.ping) return l10n.ping;
  return [l10n.ssh, saved.user, authLabel(l10n, saved.auth!)].join(' · ');
}

/// An SSH dial failure in words a person can act on.
String sshFailureText(AppLocalizations l10n, String node, String message) =>
    switch (HerdrFailure.of(message)) {
      HerdrFailure.unknownHost => l10n.herdrErrorNoHost(node),
      HerdrFailure.timeout => l10n.herdrErrorTimeout,
      HerdrFailure.unreachable => l10n.herdrErrorUnreachable,
      HerdrFailure.auth => l10n.herdrErrorAuth,
      HerdrFailure.passphrase => l10n.herdrErrorPassphrase,
      _ => l10n.sshFailed(message),
    };
