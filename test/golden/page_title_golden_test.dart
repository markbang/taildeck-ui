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
    expect(
      tester.widget<Text>(find.text('Settings')).style!.fontSize,
      24,
    );
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
    // Halfway through the handover the large title fades out as the bar's
    // compact title comes in: both are in the tree, one size each.
    final sizes = tester
        .widgetList<Text>(find.text('Settings', skipOffstage: true))
        .map((text) => text.style!.fontSize);
    expect(sizes, unorderedEquals([24, 17]));
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/title_collapsing.png'),
    );
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
