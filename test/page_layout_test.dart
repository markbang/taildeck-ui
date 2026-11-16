import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/widgets/foundation.dart';
import 'package:taildeck_ui/src/widgets/header.dart';

const _safeTop = 47.0;

Widget _app(Widget child, {EdgeInsets padding = EdgeInsets.zero}) {
  return MediaQuery(
    data: MediaQueryData(size: const Size(414, 896), padding: padding),
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: const [Locale('en'), Locale('zh')],
      home: Scaffold(body: child),
    ),
  );
}

/// The alpha of the bar's material at its top, where the status icons sit.
double _materialAlpha(WidgetTester tester) {
  final decoration = tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((box) => box.gradient)
      .whereType<LinearGradient>()
      .first;
  return decoration.colors.first.a;
}

void main() {
  setUp(() {
    // The top 300 dp are compared on a phone's width, not the test window's.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(414, 896);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('a page keeps its last row above the dock and the gesture area', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        BottomInsetScope(
          inset: 88, // the floating dock, as the shell hands it down
          child: const PageBody(title: 'Settings', children: [Text('row')]),
        ),
        padding: const EdgeInsets.only(top: _safeTop, bottom: 34),
      ),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    final padding = list.padding! as EdgeInsets;
    expect(padding.bottom, 40 + 88 + 34);
    expect(padding.top, greaterThanOrEqualTo(_safeTop));
  });

  testWidgets('a long value stays on one line and ends at the row edge', (
    tester,
  ) async {
    const value = 'controlplane.tailscale.com';
    await tester.pumpWidget(
      _app(
        const Center(
          child: SizedBox(
            width: 360,
            child: Row(children: [RowValue(value)]),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text(value));
    expect(text.maxLines, 1);
    expect(text.textAlign, TextAlign.end);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.byType(RowValue)).width, lessThanOrEqualTo(160));
  });

  // The top 300 dp as the eye compares them: FlClash puts its page title in a
  // 72 dp bar under the status bar, and the content starts 12 dp under that.
  testWidgets('a first-level title sits at the safe area, as FlClash bar does', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const PageBody(title: 'Settings', children: [Text('first row')]),
        padding: const EdgeInsets.only(top: _safeTop),
      ),
    );
    final title = tester.widget<Text>(find.text('Settings').first);
    expect(title.style!.fontSize, 24);
    expect(title.style!.fontWeight, FontWeight.w600);
    // Centred in the bar, not pushed a title block's height down the page.
    final top = tester.getTopLeft(find.text('Settings').first).dy;
    expect(top - _safeTop, lessThan(30));
    expect(top, greaterThanOrEqualTo(_safeTop));
    expect(
      tester.getTopLeft(find.text('Settings').first).dx,
      lessThanOrEqualTo(32),
    );
    // The content starts under the bar, 12 dp below it.
    final row = tester.widget<ListView>(find.byType(ListView));
    expect((row.padding! as EdgeInsets).top, _safeTop + pageToolbarHeight + 12);
    expect(
      tester.getTopLeft(find.text('first row')).dy,
      greaterThanOrEqualTo(_safeTop + pageToolbarHeight),
    );
    // Nothing paints over the status icons at rest.
    expect(_materialAlpha(tester), 0);
  });

  testWidgets('the title collapses into a lit bar as the list scrolls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        PageBody(
          title: 'Settings',
          children: [for (var i = 0; i < 80; i++) Text('row $i')],
        ),
        padding: const EdgeInsets.only(top: _safeTop),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump();
    // A real background, over the status bar and down past the bar.
    expect(_materialAlpha(tester), greaterThan(0.8));
    expect(
      tester
          .widgetList<Text>(find.text('Settings'))
          .map((text) => text.style!.fontSize),
      contains(17),
    );
  });

  testWidgets('a subpage names itself in the compact bar, not in the body', (
    tester,
  ) async {
    var backed = 0;
    await tester.pumpWidget(
      _app(
        PageBody(
          title: 'Theme',
          onBack: () => backed++,
          children: const [Text('row')],
        ),
        padding: const EdgeInsets.only(top: _safeTop),
      ),
    );
    expect(tester.getSize(find.byType(PageBar)).height, pageToolbarHeight);
    final title = tester.widget<Text>(find.text('Theme'));
    expect(title.style!.fontSize, 17);
    // One back button, in the bar, that pops the page.
    await tester.tap(find.byTooltip('Back'));
    expect(backed, 1);
    // The body has no title of its own, and its content starts under the bar.
    expect(find.text('Theme'), findsOneWidget);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      (list.padding! as EdgeInsets).top,
      greaterThanOrEqualTo(_safeTop + pageToolbarHeight),
    );
    expect(_materialAlpha(tester), greaterThan(0.8));
  });
}
