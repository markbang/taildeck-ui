import 'storage_stub.dart' if (dart.library.io) 'storage_io.dart';

class StoredConfig {
  const StoredConfig({
    this.hostname = 'taildeck',
    this.controlURL = '',
    this.signedIn = false,
    this.openInApp = false,
  });

  factory StoredConfig.fromJson(Map<String, dynamic> json) => StoredConfig(
    hostname: json['hostname'] as String? ?? 'taildeck',
    controlURL: json['controlURL'] as String? ?? '',
    signedIn: json['signedIn'] as bool? ?? false,
    openInApp: json['openInApp'] as bool? ?? false,
  );

  final String hostname;
  final String controlURL;

  /// True when the node key in the tsnet state dir was authenticated.
  final bool signedIn;

  /// Service links open in the system browser until an in-app browser lands;
  /// the choice is kept so that setting survives.
  final bool openInApp;

  Map<String, dynamic> toJson() => {
    'hostname': hostname,
    'controlURL': controlURL,
    'signedIn': signedIn,
    'openInApp': openInApp,
  };
}

abstract class BackendStorage {
  /// tsnet state dir; created on demand.
  Future<String> stateDir();

  /// App-private SSH dir (keys live here); created on demand.
  Future<String> sshDir();
  Future<StoredConfig> readConfig();
  Future<void> writeConfig(StoredConfig config);

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
