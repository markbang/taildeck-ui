/// Service icons: fetched through the tailnet node, cached on disk, and shown
/// by [ServiceAvatar]. A site's address never leaves the device.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'demo/demo_favicon.dart';
import 'favicons_store.dart';
import 'services.dart';

/// One icon per service target, so two services on the same port share a file.
String faviconKey(Service service) =>
    '${service.node}-${service.port}-${service.scheme}';

/// After this the icon is still drawn but refetched in the background.
const faviconSoftTtl = Duration(days: 7);

/// A target without an icon is not retried for a day: a dead service would
/// otherwise be hit on every visit and every scroll.
const faviconNegativeTtl = Duration(days: 1);

/// At most this many icon fetches run at once.
const faviconConcurrency = 4;

/// A single fetch is bounded in Go too; this catches a stuck library.
const faviconTimeout = Duration(seconds: 10);

enum FaviconState { idle, loading, ready, failed }

class FaviconImage {
  const FaviconImage({
    required this.bytes,
    required this.contentType,
    this.etag = '',
    this.lastModified = '',
    this.url = '',
  });

  factory FaviconImage.fromCached(CachedFaviconImage cached) => FaviconImage(
    bytes: cached.bytes,
    contentType: cached.contentType,
    etag: cached.etag,
    lastModified: cached.lastModified,
    url: cached.url,
  );

  final Uint8List bytes;
  final String contentType;
  final String etag;
  final String lastModified;
  final String url;

  bool get vector => contentType == 'image/svg+xml';

  CachedFaviconImage get asCached => CachedFaviconImage(
    bytes: bytes,
    contentType: contentType,
    etag: etag,
    lastModified: lastModified,
    url: url,
  );
}

class FaviconEntry {
  const FaviconEntry({this.image, this.state = FaviconState.idle, this.at});

  final FaviconImage? image;
  final FaviconState state;
  final DateTime? at;

  bool get ready => state == FaviconState.ready && image != null;

  FaviconEntry copyWith({
    FaviconImage? image,
    FaviconState? state,
    DateTime? at,
  }) => FaviconEntry(
    image: image ?? this.image,
    state: state ?? this.state,
    at: at ?? this.at,
  );
}

/// Fetches one icon through the node; null when the node is not running, which
/// is a transient state and must not be cached as "no icon".
typedef FaviconFetch = Future<FaviconImage?> Function(Service service);

/// Resolves service icons and keeps the last result per target. Tiles call
/// [ensure] when they appear, so only visible services are fetched.
class FaviconsController extends ChangeNotifier {
  FaviconsController({
    required this.fetch,
    FaviconStore? store,
    DateTime Function()? now,
  }) : _store = store ?? openFaviconStore(),
       _now = now ?? DateTime.now;

  final FaviconFetch fetch;
  final FaviconStore _store;
  final DateTime Function() _now;
  final Map<String, FaviconEntry> _entries = {};
  final Set<String> _inflight = {};
  final Queue<Completer<void>> _queue = Queue<Completer<void>>();
  int _active = 0;
  bool _disposed = false;

  FaviconEntry entryFor(Service service) =>
      _entries[faviconKey(service)] ?? const FaviconEntry();

  /// Starts a fetch for [service] unless a fresh result is already there. Safe
  /// to call on every build.
  void ensure(Service service) {
    final key = faviconKey(service);
    if (_inflight.contains(key)) return;
    final entry = _entries[key];
    final now = _now();
    if (entry != null) {
      final age = now.difference(entry.at ?? now);
      if (entry.state == FaviconState.failed && age < faviconNegativeTtl) {
        return;
      }
      // A soft-expired icon stays on screen while it is refreshed.
      if (entry.ready && age < faviconSoftTtl) return;
    }
    unawaited(_load(service, key));
  }

  /// Drops the cache and refetches [services]: the Settings action.
  Future<void> refreshAll(Iterable<Service> services) async {
    final list = services.toList();
    _entries.clear();
    await _store.clear();
    _notify();
    for (final service in list) {
      ensure(service);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _entries.clear();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load(Service service, String key) async {
    _inflight.add(key);
    try {
      if (_entries[key]?.ready != true) {
        if (await _readDisk(key)) return;
      }
      final image = await _limit(() => fetch(service).timeout(faviconTimeout));
      if (image == null) return;
      final previous = _entries[key];
      // Same validators: keep the bytes the UI already decoded, bump the age.
      final unchanged =
          previous?.image != null &&
          image.etag.isNotEmpty &&
          image.etag == previous!.image!.etag;
      final at = _now();
      _entries[key] = FaviconEntry(
        image: unchanged ? previous.image : image,
        state: FaviconState.ready,
        at: at,
      );
      _notify();
      await _store.write(
        key,
        CachedFavicon(image: _entries[key]!.image!.asCached, at: at),
      );
    } on Object catch (error) {
      debugPrint('taildeck: no icon for ${faviconKey(service)}: $error');
      final at = _now();
      final previous = _entries[key];
      _entries[key] = FaviconEntry(
        image: previous?.image,
        state: FaviconState.failed,
        at: at,
      );
      _notify();
      await _store.write(
        key,
        CachedFavicon(at: at, negative: previous?.image == null),
      );
    } finally {
      _inflight.remove(key);
    }
  }

  /// A cold entry reads the disk first; a fresh one is drawn without waiting
  /// on the network.
  Future<bool> _readDisk(String key) async {
    final cached = await _store.read(key);
    if (cached == null) return false;
    final age = _now().difference(cached.at);
    if (cached.negative) {
      if (age >= faviconNegativeTtl) return false;
      _entries[key] = FaviconEntry(state: FaviconState.failed, at: cached.at);
      _notify();
      return true;
    }
    final fresh = age < faviconSoftTtl;
    final image = cached.image;
    if (image == null) return false;
    _entries[key] = FaviconEntry(
      image: FaviconImage.fromCached(image),
      state: FaviconState.ready,
      at: cached.at,
    );
    _notify();
    return fresh;
  }

  /// Keeps at most [faviconConcurrency] fetches alive; the rest wait, so a
  /// long services list never floods the node or the UI.
  Future<T> _limit<T>(Future<T> Function() task) async {
    while (_active >= faviconConcurrency) {
      final slot = Completer<void>();
      _queue.add(slot);
      await slot.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_queue.isNotEmpty) _queue.removeFirst().complete();
    }
  }
}

class FaviconsScope extends InheritedNotifier<FaviconsController> {
  const FaviconsScope({
    super.key,
    required FaviconsController controller,
    required super.child,
  }) : super(notifier: controller);

  static FaviconsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FaviconsScope>();
    assert(scope != null, 'FaviconsScope missing above this widget');
    return scope!.notifier!;
  }

  /// Optional lookup for widgets that must not trigger a fetch decision.
  static FaviconsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FaviconsScope>()?.notifier;
}

/// Bundled demo icons for `?favicons=demo`: clearly not a real fetch, so a
/// screenshot can show the placeholder and the cross-fade without a tailnet.
Future<FaviconImage?> demoFavicon(Service service) async {
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final bytes = switch (service.port) {
    3000 => grafanaDemo,
    8080 => codeServerDemo,
    _ => null,
  };
  if (bytes == null) return null;
  return FaviconImage(bytes: bytes, contentType: 'image/png');
}
