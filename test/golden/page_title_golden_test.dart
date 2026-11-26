@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/widgets/foundation.dart';
import 'package:taildeck_ui/src/widgets/header.dart';

import 'golden_harness.dart';

Widget _page({String? subtitle, VoidCallback? onBack, int rows = 30}) {
  return Builder(
    builder: (context) => Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: PageBody(
        title: 'Settings',
        subtitle: subtitle,
        onBack: onBack,
        children: [
          generateGroup([
            for (var i = 0; i < rows; i++)
              DecorationListItem(title: Text('Setting $i')),
          ]),
        ],
      ),
    ),
  );
}

double _titleOpacity(WidgetTester tester, double fontSize) {
  final title = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data == 'Settings' &&
        widget.style?.fontSize == fontSize,
  );
  return tester
      .widgetList<Opacity>(
        find.ancestor(of: title, matching: find.byType(Opacity)),
      )
      .fold(
        title.evaluate().isEmpty ? 0.0 : 1.0,
        (alpha, opacity) => alpha * opacity.opacity,
      );
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useGoldenComparator();
  });

  testWidgets('a first-level page opens on its title, not on a gap', (
    tester,
  ) async {
    usePhone(tester, size: const Size(414, 300));
    await tester.pumpWidget(goldenApp(home: _page()));
    await tester.pump(const Duration(milliseconds: 300));

    // The large title is centred in the 72 dp bar under the status bar, with
    // no block of blank space above it.
    final title = tester.getCenter(find.text('Settings'));
    expect(title.dy, greaterThan(statusBar));
    expect(title.dy, lessThan(statusBar + pageToolbarHeight));
    expect(tester.widget<Text>(find.text('Settings')).style!.fontSize, 24);
    // At rest there is one title: the compact one waits for the scroll.
    expect(find.text('Settings'), findsOneWidget);
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/title_top_300.png'),
    );
  });

  testWidgets('the large title hands over as the list scrolls', (tester) async {
    usePhone(tester, size: const Size(414, 300));
    await tester.pumpWidget(goldenApp(home: _page()));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.drag(find.byType(ListView), const Offset(0, -24));
    await tester.pump();

    expect(find.byType(PageHeader, skipOffstage: true), findsOneWidget);
    expect(_titleOpacity(tester, 17), greaterThan(0));
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/title_collapsing.png'),
    );
  });

  testWidgets('the two titles never show at once across the handover', (
    tester,
  ) async {
    usePhone(tester, size: const Size(414, 300));
    await tester.pumpWidget(goldenApp(home: _page()));
    await tester.pump(const Duration(milliseconds: 300));
    final list = tester.widget<ListView>(find.byType(ListView));

    for (var offset = 0.0; offset <= 40; offset += 1) {
      list.controller!.jumpTo(offset);
      await tester.pump();
      final large = _titleOpacity(tester, 24);
      final compact = _titleOpacity(tester, 17);
      expect(
        large == 0 || compact == 0,
        isTrue,
        reason: 'both titles visible at offset $offset',
      );
      if (offset == 0) expect(large, 1);
      if (offset == 40) expect(compact, 1);
    }
  });

  testWidgets('a subpage names itself in the compact bar', (tester) async {
    usePhone(tester, size: const Size(414, 300));
    var backed = 0;
    await tester.pumpWidget(
      goldenApp(
        home: _page(subtitle: 'Auto', onBack: () => backed++),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final bar = find.byType(PageBar);
    expect(bar, findsOneWidget);
    expect(tester.getTopLeft(bar).dy, statusBar);
    expect(tester.getSize(bar).height, pageToolbarHeight);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      (list.padding! as EdgeInsets).top,
      greaterThanOrEqualTo(statusBar + pageToolbarHeight),
    );
    // Not two titles: the body has no large title of its own.
    expect(find.text('Settings'), findsOneWidget);
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/subpage_bar.png'),
    );

    await tester.tap(find.byTooltip('Back'));
    expect(backed, 1);
  });
}
