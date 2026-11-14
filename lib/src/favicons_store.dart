/// Disk (or memory, on web) cache for service icons.
library;

import 'dart:typed_data';

import 'favicons_store_stub.dart'
    if (dart.library.io) 'favicons_store_io.dart'
    as impl;

/// One cached icon: the bytes plus when they were fetched, or a negative
/// marker for a target that has no icon.
class CachedFavicon {
  const CachedFavicon({this.image, required this.at, this.negative = false});

  final CachedFaviconImage? image;
  final DateTime at;
  final bool negative;
}

/// The raw bytes the bridge returned, before the UI decides how to draw them.
class CachedFaviconImage {
  const CachedFaviconImage({
    required this.bytes,
    required this.contentType,
    this.etag = '',
    this.lastModified = '',
    this.url = '',
  });

  final Uint8List bytes;
  final String contentType;
  final String etag;
  final String lastModified;
  final String url;
}

abstract class FaviconStore {
  Future<CachedFavicon?> read(String key);
  Future<void> write(String key, CachedFavicon value);
  Future<void> clear();
}

FaviconStore openFaviconStore() => impl.createFaviconStore();
