@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/pages/agents.dart';

import 'fake_backend.dart';
import 'golden_harness.dart';

const _failure = "Can't find node bangwu — is it online and is MagicDNS on?";
const _connecting = 'Connecting to herdr · bangwu';

/// The shell keeps the page alive and ticks only the tab on screen.
class _Shell extends StatelessWidget {
  const _Shell({required this.backend, required this.live});

  final TaildeckBackend backend;
  final ValueNotifier<bool> live;

  @override
  Widget build(BuildContext context) {
    return goldenApp(
      home: BackendScope(
        backend: backend,
        child: Builder(
          builder: (context) => Surface(
            color: SurfaceLevel.page.colorOf(context.colorScheme),
            child: ValueListenableBuilder<bool>(
              valueListenable: live,
              builder: (context, live, _) =>
                  TickerMode(enabled: live, child: const AgentsPage()),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useGoldenComparator();
  });

  testWidgets('a failed dial is one human card with Retry', (tester) async {
    usePhone(tester, size: const Size(414, 300));
    final bridge = FakeBridge()
      ..herdrError = 'connect bangwu:22: lookup bangwu: no such host';
    final backend = failedHerdrBackend(bridge);
    await backend.init();
    await tester.pumpWidget(
      _Shell(backend: backend, live: ValueNotifier(true)),
    );
    await pumpFrames(tester, const Duration(milliseconds: 500));

    expect(find.text(_failure), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/agents_failed.png'),
    );

    await tester.pumpWidget(const SizedBox());
    backend.dispose();
    await tester.pump();
  });

  testWidgets('opening the tab turns a stale failure into connecting', (
    tester,
  ) async {
    usePhone(tester, size: const Size(414, 270));
    final bridge = FakeBridge()
      ..herdrError = 'connect bangwu:22: lookup bangwu: no such host';
    final backend = failedHerdrBackend(bridge);
    final live = ValueNotifier<bool>(true);
    addTearDown(live.dispose);
    await backend.init();
    await tester.pumpWidget(_Shell(backend: backend, live: live));
    await pumpFrames(tester, const Duration(milliseconds: 500));
    expect(find.text('Retry'), findsOneWidget);

    // Another tab is up long enough for the page to settle unseen.
    live.value = false;
    await pumpFrames(tester, const Duration(milliseconds: 400));

    // Opening this tab starts its own dial; every frame shows connecting.
    bridge
      ..herdrError = ''
      ..herdrGate = Completer<void>();
    live.value = true;
    await pumpFrames(tester, const Duration(milliseconds: 48));
    expect(find.text(_failure, skipOffstage: false), findsNothing);
    expect(find.text('Retry', skipOffstage: false), findsNothing);
    expect(find.text(_connecting, skipOffstage: false), findsOneWidget);
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/agents_switch.png'),
    );
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text(_failure), findsNothing, reason: 'frame $frame');
      expect(find.text('Retry'), findsNothing, reason: 'frame $frame');
      expect(find.text(_connecting), findsOneWidget, reason: 'frame $frame');
      if (frame == 8) {
        await expectLater(
          find.byType(PrismApp),
          matchesGoldenFile('goldens/agents_connecting.png'),
        );
      }
    }

    bridge.herdrGate!.complete();
    await pumpFrames(tester, const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
    await tester.pump();
  });
}
