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

Finder _title(double fontSize) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data == 'Settings' &&
      widget.style?.fontSize == fontSize,
);

Rect? _rect(WidgetTester tester, double fontSize) {
  final title = _title(fontSize);
  return title.evaluate().isEmpty ? null : tester.getRect(title);
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
    pinGoldenMotion();
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

  testWidgets('the large title scales down in place as the list scrolls', (
    tester,
  ) async {
    usePhone(tester, size: const Size(414, 300));
    await tester.pumpWidget(goldenApp(home: _page()));
    await tester.pump(const Duration(milliseconds: 300));
    final before = tester.getRect(_title(24));

    await tester.drag(find.byType(ListView), const Offset(0, -24));
    await tester.pump();

    expect(find.byType(PageHeader, skipOffstage: true), findsOneWidget);
    final scaled = tester.getRect(_title(24));
    expect(scaled.width, lessThan(before.width));
    expect(scaled.left, closeTo(before.left, 0.5));
    expect(_titleOpacity(tester, 17), 0);
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/title_collapsing.png'),
    );
  });

  testWidgets('one title at a time, and the scaled tail never past the other', (
    tester,
  ) async {
    usePhone(tester, size: const Size(414, 300));
    await tester.pumpWidget(goldenApp(home: _page()));
    await tester.pump(const Duration(milliseconds: 300));
    final list = tester.widget<ListView>(find.byType(ListView));
    final bar = tester.getRect(find.byType(PageBar));
    final lineCentre = tester.getCenter(find.byType(PageBar)).dy;

    for (var offset = 0.0; offset <= 40; offset += 1) {
      list.controller!.jumpTo(offset);
      await tester.pump();
      final large = _titleOpacity(tester, 24);
      final compact = _titleOpacity(tester, 17);
      expect(
        large > 0.5 && compact > 0.5,
        isFalse,
        reason: 'two titles above 0.5 at offset $offset',
      );
      final largeRect = _rect(tester, 24);
      final compactRect = _rect(tester, 17);
      if (compactRect != null && largeRect != null && compact > 0) {
        // The gate: the compact title shows only once the scaled title is
        // within 2 % of its width.
        expect(
          largeRect.width,
          lessThanOrEqualTo(
            compactRect.width * (1 + PageBar.compactGate) + 1e-6,
          ),
          reason: 'compact title shown while the large is too wide at $offset',
        );
      }
      if (largeRect != null &&
          compactRect != null &&
          large > 0 &&
          compact > 0) {
        // Tail check: the scaled title's painted right edge is at most the
        // compact title's right edge plus the gate's 2 %.
        expect(
          largeRect.right,
          lessThanOrEqualTo(
            compactRect.right + compactRect.width * PageBar.compactGate + 1e-6,
          ),
          reason: 'large tail past the compact title at offset $offset',
        );
      }
      // Anchored: each title shares the left edge and the line box's centre.
      for (final rect in [largeRect, compactRect]) {
        if (rect == null) continue;
        expect(rect.left, closeTo(bar.left + 20, 0.5));
        expect(rect.center.dy, closeTo(lineCentre, 0.5));
      }
      expect(tester.getRect(find.byType(PageBar)), bar);
      if (offset == 0) {
        expect(large, 1);
        expect(compact, 0);
      }
      if (offset == 40) {
        expect(compact, 1);
        expect(large, 0);
      }
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
