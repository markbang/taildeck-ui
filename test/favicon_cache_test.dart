import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/favicons.dart';
import 'package:taildeck_ui/src/favicons_store.dart';
import 'package:taildeck_ui/src/services.dart';

class FakeStore implements FaviconStore {
  final Map<String, CachedFavicon> entries = {};
  int clears = 0;

  @override
  Future<CachedFavicon?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, CachedFavicon value) async =>
      entries[key] = value;

  @override
  Future<void> clear() async {
    clears++;
    entries.clear();
  }
}

Service service(int port, {String node = 'devbox'}) => Service(
  id: '$node-$port',
  node: node,
  name: 'svc$port',
  url: 'http://$node:$port/',
);

FaviconImage png(String etag) => FaviconImage(
  bytes: Uint8List.fromList([1, 2, 3]),
  contentType: 'image/png',
  etag: etag,
);

void main() {
  test('a fetch is cached on disk and reused without the network', () async {
    final store = FakeStore();
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final first = FaviconsController(
      store: store,
      fetch: (_) async {
        calls++;
        return png('"v1"');
      },
      now: () => now,
    );
    first.ensure(service(3000));
    await pumpEventQueue();
    expect(calls, 1);
    expect(first.entryFor(service(3000)).ready, isTrue);
    expect(store.entries, hasLength(1));

    final second = FaviconsController(
      store: store,
      fetch: (_) async {
        calls++;
        return png('"v1"');
      },
      now: () => now,
    );
    second.ensure(service(3000));
    await pumpEventQueue();
    expect(calls, 1, reason: 'a fresh disk entry must not refetch');
    expect(second.entryFor(service(3000)).ready, isTrue);
  });

  test('a failed fetch is remembered for a day, then tried again', () async {
    final store = FakeStore();
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final controller = FaviconsController(
      store: store,
      fetch: (_) async {
        calls++;
        throw StateError('no icon');
      },
      now: () => now,
    );
    controller.ensure(service(3000));
    await pumpEventQueue();
    expect(calls, 1);
    expect(controller.entryFor(service(3000)).state, FaviconState.failed);

    controller.ensure(service(3000));
    await pumpEventQueue();
    expect(calls, 1, reason: 'the negative cache holds for a day');

    now = now.add(const Duration(hours: 25));
    controller.ensure(service(3000));
    await pumpEventQueue();
    expect(calls, 2);
  });

  test('an offline node is not cached as a site without an icon', () async {
    final store = FakeStore();
    var calls = 0;
    final controller = FaviconsController(
      store: store,
      fetch: (_) async {
        calls++;
        return null;
      },
    );
    controller.ensure(service(3000));
    await pumpEventQueue();
    controller.ensure(service(3000));
    await pumpEventQueue();
    expect(calls, 2);
    expect(store.entries, isEmpty);
  });

  test('a soft-expired icon stays while it is refetched', () async {
    final store = FakeStore();
    var now = DateTime(2026, 1, 1);
    var calls = 0;
    final controller = FaviconsController(
      store: store,
      fetch: (_) async {
        calls++;
        return png('"v$calls"');
      },
      now: () => now,
    );
    controller.ensure(service(3000));
    await pumpEventQueue();
    final firstImage = controller.entryFor(service(3000)).image;

    now = now.add(faviconSoftTtl + const Duration(minutes: 1));
    controller.ensure(service(3000));
    expect(
      controller.entryFor(service(3000)).image,
      same(firstImage),
      reason: 'the old icon is drawn until the new one lands',
    );
    await pumpEventQueue();
    expect(calls, 2);
    expect(controller.entryFor(service(3000)).image, isNot(same(firstImage)));
  });

  test('the same etag keeps the decoded bytes', () async {
    final store = FakeStore();
    var now = DateTime(2026, 1, 1);
    final controller = FaviconsController(
      store: store,
      fetch: (_) async => png('"same"'),
      now: () => now,
    );
    controller.ensure(service(3000));
    await pumpEventQueue();
    final firstImage = controller.entryFor(service(3000)).image;

    now = now.add(faviconSoftTtl + const Duration(minutes: 1));
    controller.ensure(service(3000));
    await pumpEventQueue();
    expect(controller.entryFor(service(3000)).image, same(firstImage));
  });

  test('at most four fetches run at once', () async {
    final store = FakeStore();
    var active = 0;
    var peak = 0;
    final controller = FaviconsController(
      store: store,
      fetch: (_) async {
        active++;
        peak = active > peak ? active : peak;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return png('"v"');
      },
    );
    for (var port = 3000; port < 3008; port++) {
      controller.ensure(service(port));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(peak, faviconConcurrency);
    expect(store.entries, hasLength(8));
  });

  test('refreshAll clears the cache and refetches', () async {
    final store = FakeStore();
    var calls = 0;
    final controller = FaviconsController(
      store: store,
      fetch: (_) async {
        calls++;
        return png('"v$calls"');
      },
    );
    final one = service(3000);
    controller.ensure(one);
    await pumpEventQueue();
    await controller.refreshAll([one]);
    await pumpEventQueue();
    expect(store.clears, 1);
    expect(calls, 2);
    expect(controller.entryFor(one).ready, isTrue);
  });
}
