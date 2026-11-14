import 'favicons_store.dart';

FaviconStore createFaviconStore() => _MemoryFaviconStore();

/// Web has no app support dir; the preview keeps icons for the session.
class _MemoryFaviconStore implements FaviconStore {
  final Map<String, CachedFavicon> _entries = {};

  @override
  Future<CachedFavicon?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, CachedFavicon value) async =>
      _entries[key] = value;

  @override
  Future<void> clear() async => _entries.clear();
}
