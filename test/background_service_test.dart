import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/favicons.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/node_service.dart';
import 'package:taildeck_ui/src/native/storage.dart';
import 'package:taildeck_ui/src/services.dart';
import 'package:taildeck_ui/src/shell.dart';
import 'package:taildeck_ui/src/theme.dart';

import 'golden/fake_backend.dart';

/// Records the calls and refuses a start while the app is in the background,
/// as Android 12+ does.
class _FakeService implements NodeService {
  bool foreground = true;
  bool running = false;
  int refused = 0;
  int prompts = 0;
  bool? exempt = false;

  @override
  Future<bool> start() async {
    if (!foreground) {
      refused++;
      return false;
    }
    running = true;
    return true;
  }

  @override
  Future<void> stop() async => running = false;

  @override
  Future<bool?> batteryExempt() async => exempt;

  @override
  Future<void> requestBatteryExempt() async => prompts++;
}

class _CountingBridge extends FakeBridge {
  int rebinds = 0;

  @override
  void networkChanged() => rebinds++;
}

void main() {
  group('serviceWanted', () {
    bool wanted(
      BackendState state, {
      bool started = true,
      bool foreground = false,
      bool keepAlive = true,
    }) => serviceWanted(
      started: started,
      state: state,
      foreground: foreground,
      keepAlive: keepAlive,
    );

    test('holds the node in the background while it is up', () {
      expect(wanted(BackendState.running), isTrue);
      expect(wanted(BackendState.starting), isTrue);
    });

    test('keep-alive off follows the app', () {
      expect(wanted(BackendState.running, keepAlive: false), isFalse);
      expect(
        wanted(BackendState.running, keepAlive: false, foreground: true),
        isTrue,
      );
    });

    test('no node, no service', () {
      expect(wanted(BackendState.running, started: false), isFalse);
      for (final state in [
        BackendState.stopped,
        BackendState.needsLogin,
        BackendState.error,
        BackendState.unavailable,
      ]) {
        expect(wanted(state, foreground: true), isFalse, reason: '$state');
      }
    });
  });

  group('background keep-alive', () {
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    TaildeckBackend signedIn(
      FakeBridge bridge,
      _FakeService service, {
      bool keepAlive = true,
    }) => TaildeckBackend(
      bridge: bridge,
      storage: MemoryStorage()
        ..config = StoredConfig(signedIn: true, terminalKeepAlive: keepAlive),
      service: service,
    );

    test(
      'the service is up before Running, so leaving early keeps it',
      () async {
        final bridge = FakeBridge()
          ..statusReply = {...FakeBridge.readyStatus, 'state': 'Starting'};
        final service = _FakeService();
        final backend = signedIn(bridge, service);
        await backend.init();
        await settle();
        expect(backend.state, BackendState.starting);
        expect(service.running, isTrue);

        service.foreground = false;
        backend.setForeground(false);
        bridge.statusReply = FakeBridge.readyStatus;
        await backend.refresh();
        await settle();

        expect(backend.state, BackendState.running);
        expect(service.running, isTrue);
        expect(service.refused, 0);
        backend.dispose();
      },
    );

    test('a start refused in the background is retried on resume', () async {
      final bridge = _CountingBridge();
      final service = _FakeService()..foreground = false;
      final backend = signedIn(bridge, service);
      backend.setForeground(false);
      await backend.init();
      await settle();
      expect(service.refused, isNonZero);
      expect(service.running, isFalse);

      service.foreground = true;
      backend.setForeground(true);
      await settle();

      expect(service.running, isTrue);
      expect(bridge.rebinds, 1);
      backend.dispose();
    });

    test('keep-alive off stops the service in the background', () async {
      final service = _FakeService();
      final backend = signedIn(FakeBridge(), service, keepAlive: false);
      await backend.init();
      await settle();
      expect(service.running, isTrue);

      backend.setForeground(false);
      await settle();
      expect(service.running, isFalse);
      backend.dispose();
    });

    test('sign-out stops the service', () async {
      final service = _FakeService();
      final backend = signedIn(FakeBridge(), service);
      await backend.init();
      await settle();
      expect(service.running, isTrue);

      await backend.signOut();
      await settle();
      expect(service.running, isFalse);
      backend.dispose();
    });

    test('battery exemption is read at launch and after the prompt', () async {
      final service = _FakeService();
      final backend = signedIn(FakeBridge(), service);
      await backend.init();
      expect(backend.batteryExempt, isFalse);

      await backend.requestBatteryExempt();
      expect(service.prompts, 1);
      service.exempt = true;
      backend
        ..setForeground(false)
        ..setForeground(true);
      await settle();
      expect(backend.batteryExempt, isTrue);
      backend.dispose();
    });
  });
  group('settings', () {
    Future<void> pumpSettings(WidgetTester tester, _FakeService service) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final backend = TaildeckBackend(
        bridge: FakeBridge(),
        storage: MemoryStorage()..config = const StoredConfig(signedIn: true),
        service: service,
      );
      await tester.runAsync(backend.init);
      final theme = TaildeckTheme();
      await tester.pumpWidget(
        PrismApp(
          theme: theme.light,
          darkTheme: theme.dark,
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en'), Locale('zh')],
          builder: (context, child) => ViewScope(
            size: MediaQuery.sizeOf(context),
            isMobile: true,
            child: BackendScope(
              backend: backend,
              child: ServicesScope(
                store: ServiceStore.open(),
                child: FaviconsScope(
                  controller: FaviconsController(fetch: (_) async => null),
                  child: child!,
                ),
              ),
            ),
          ),
          home: TaildeckShell(theme: theme),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      final terminal = find.text('Terminal');
      await tester.scrollUntilVisible(
        terminal,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(terminal);
      await tester.pumpAndSettle();
    }

    testWidgets('asks for unrestricted battery until it is granted', (
      tester,
    ) async {
      final service = _FakeService();
      await pumpSettings(tester, service);
      final row = find.text('Unrestricted battery');
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.text(
          'Battery optimisation may pause the tailnet in the background. '
          'Tap to allow background use.',
        ),
        findsOneWidget,
      );
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(service.prompts, 1);
    });

    testWidgets('no battery row where the platform has none', (tester) async {
      await pumpSettings(tester, _FakeService()..exempt = null);
      await tester.scrollUntilVisible(
        find.text('Keep sessions in background'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Unrestricted battery'), findsNothing);
    });
  });
}
