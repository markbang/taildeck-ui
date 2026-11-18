import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/favicons.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/storage.dart';
import 'package:taildeck_ui/src/services.dart';
import 'package:taildeck_ui/src/shell.dart';
import 'package:taildeck_ui/src/theme.dart';

import 'golden/fake_backend.dart';

Future<(TaildeckTheme, TaildeckBackend)> _pumpSettings(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final backend = TaildeckBackend(
    bridge: FakeBridge(),
    storage: MemoryStorage()..config = const StoredConfig(signedIn: true),
  );
  await tester.runAsync(backend.init);
  final theme = TaildeckTheme();
  final services = ServiceStore.open();
  final favicons = FaviconsController(fetch: (_) async => null);
  await tester.pumpWidget(
    ListenableBuilder(
      listenable: theme,
      builder: (context, _) => PrismApp(
        theme: theme.light,
        darkTheme: theme.dark,
        themeMode: theme.mode,
        liquidGlass: LiquidGlassQuality.ultra,
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en'), Locale('zh')],
        builder: (context, child) => ViewScope(
          size: MediaQuery.sizeOf(context),
          isMobile: true,
          child: BackendScope(
            backend: backend,
            child: ServicesScope(
              store: services,
              child: FaviconsScope(controller: favicons, child: child!),
            ),
          ),
        ),
        home: TaildeckShell(theme: theme),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings').last);
  await tester.pumpAndSettle();
  return (theme, backend);
}

void main() {
  testWidgets('Theme opens, takes a mode and closes, and every frame settles', (
    tester,
  ) async {
    final (theme, backend) = await _pumpSettings(tester);
    expect(find.text('Theme'), findsWidgets);

    await tester.tap(find.text('Theme').last);
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsWidgets);

    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.light);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Tailnet & device'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  });
}
