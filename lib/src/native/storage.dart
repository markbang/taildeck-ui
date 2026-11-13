import 'storage_stub.dart' if (dart.library.io) 'storage_io.dart';

class StoredConfig {
  const StoredConfig({
    this.hostname = 'taildeck',
    this.controlURL = '',
    this.signedIn = false,
  });

  factory StoredConfig.fromJson(Map<String, dynamic> json) => StoredConfig(
    hostname: json['hostname'] as String? ?? 'taildeck',
    controlURL: json['controlURL'] as String? ?? '',
    signedIn: json['signedIn'] as bool? ?? false,
  );

  final String hostname;
  final String controlURL;

  /// True when the node key in the tsnet state dir was authenticated.
  final bool signedIn;

  Map<String, dynamic> toJson() => {
    'hostname': hostname,
    'controlURL': controlURL,
    'signedIn': signedIn,
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
}

/// Null on web, where the app stays on mock data.
BackendStorage? openBackendStorage() => openStoragePlatform();
