import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';

BackendStorage? openStoragePlatform() => _IoStorage();

class _IoStorage implements BackendStorage {
  Directory? _root;

  Future<Directory> _rootDir() async {
    final root = _root ??= await getApplicationSupportDirectory();
    return root;
  }

  @override
  Future<String> stateDir() async {
    final dir = Directory('${(await _rootDir()).path}/tsnet');
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String> sshDir() async {
    final dir = Directory('${(await _rootDir()).path}/ssh');
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<File> _configFile() async =>
      File('${(await _rootDir()).path}/config.json');

  Future<File> _servicesFile() async =>
      File('${(await _rootDir()).path}/services.json');

  Future<File> _identitiesFile() async =>
      File('${(await _rootDir()).path}/ssh/identities.json');

  @override
  Future<StoredConfig> readConfig() async {
    final file = await _configFile();
    if (!await file.exists()) return const StoredConfig();
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) return StoredConfig.fromJson(raw);
    } on FormatException {
      // A corrupt config must not block sign-in.
    }
    return const StoredConfig();
  }

  @override
  Future<void> writeConfig(StoredConfig config) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  @override
  Future<String?> readServicesJson() async {
    final file = await _servicesFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeServicesJson(String json) async {
    final file = await _servicesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
  }

  @override
  Future<String?> readIdentitiesJson() async {
    final file = await _identitiesFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeIdentitiesJson(String json) async {
    final file = await _identitiesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
  }

  @override
  Future<String> sshKeyPath(String name) async => '${await sshDir()}/$name.key';

  @override
  Future<void> writeSshKey(String name, String contents) async {
    final file = File(await sshKeyPath(name));
    await file.writeAsString(contents);
    // Best effort; Windows has no chmod and the support dir is already private.
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', file.path]);
    }
  }

  @override
  Future<void> deleteSshKey(String name) async {
    final file = File(await sshKeyPath(name));
    if (await file.exists()) await file.delete();
  }
}
