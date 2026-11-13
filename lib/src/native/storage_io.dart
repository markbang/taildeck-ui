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
}
