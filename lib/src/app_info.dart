import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The version this build carries, read from the platform at launch so it
/// always matches `version:` in pubspec without a second place to edit.
abstract final class AppInfo {
  static String _version = '';

  /// '0.2.15' on a real build; '—' when the platform could not answer.
  static String get version => _version.isEmpty ? '—' : _version;

  static Future<void> load() async {
    try {
      _version = (await PackageInfo.fromPlatform()).version;
    } on Object catch (error) {
      debugPrint('taildeck: version unavailable: $error');
    }
  }
}
