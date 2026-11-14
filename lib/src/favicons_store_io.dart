import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'favicons_store.dart';

FaviconStore createFaviconStore() => _DiskFaviconStore();

/// Icons live in the app support dir: raw bytes next to a small JSON record,
/// so a cached icon survives a restart and an offline launch.
class _DiskFaviconStore implements FaviconStore {
  Directory? _dir;

  Future<Directory> _root() async {
    final cached = _dir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/favicons');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Service names and hosts are DNS labels; anything else cannot touch the path.
  static String _safe(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<File> _meta(String key) async =>
      File('${(await _root()).path}/${_safe(key)}.json');

  Future<File> _bytes(String key) async =>
      File('${(await _root()).path}/${_safe(key)}.bin');

  @override
  Future<CachedFavicon?> read(String key) async {
    try {
      final meta = await _meta(key);
      if (!await meta.exists()) return null;
      final raw = jsonDecode(await meta.readAsString());
      if (raw is! Map<String, dynamic>) return null;
      final at = DateTime.tryParse(raw['at'] as String? ?? '');
      if (at == null) return null;
      if (raw['negative'] == true) {
        return CachedFavicon(at: at, negative: true);
      }
      final bytes = await _bytes(key);
      if (!await bytes.exists()) return null;
      return CachedFavicon(
        at: at,
        image: CachedFaviconImage(
          bytes: await bytes.readAsBytes(),
          contentType: raw['contentType'] as String? ?? '',
          etag: raw['etag'] as String? ?? '',
          lastModified: raw['lastModified'] as String? ?? '',
          url: raw['url'] as String? ?? '',
        ),
      );
    } on Object {
      // A damaged cache entry is a miss, never an error the user must see.
      return null;
    }
  }

  @override
  Future<void> write(String key, CachedFavicon value) async {
    try {
      final meta = await _meta(key);
      await meta.writeAsString(
        jsonEncode({
          'at': value.at.toUtc().toIso8601String(),
          'negative': value.negative,
          if (value.image case final image?) ...{
            'contentType': image.contentType,
            'etag': image.etag,
            'lastModified': image.lastModified,
            'url': image.url,
          },
        }),
      );
      final bytes = await _bytes(key);
      final image = value.image;
      if (image == null) {
        if (await bytes.exists()) await bytes.delete();
        return;
      }
      await bytes.writeAsBytes(image.bytes, flush: false);
    } on Object {
      // Losing a cache write only costs a refetch next launch.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final dir = await _root();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } on Object {
      // Already gone.
    }
  }
}
