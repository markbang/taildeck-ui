import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/widgets/foundation.dart';
import 'package:taildeck_ui/src/widgets/header.dart';

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

void main() {
  testWidgets('a page keeps its last row above the dock and the gesture area', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        BottomInsetScope(
          inset: 88, // the floating dock, as the shell hands it down
          child: const PageBody(title: 'Settings', children: [Text('row')]),
        ),
        padding: const EdgeInsets.only(top: 47, bottom: 34),
      ),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    final padding = list.padding! as EdgeInsets;
    expect(padding.bottom, 40 + 88 + 34);
    expect(padding.top, greaterThanOrEqualTo(47));
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

  testWidgets('a subpage names itself in the floating bar, not in the body', (
    tester,
  ) async {
    var backed = 0;
    await tester.pumpWidget(
      _app(
        PageBody(
          title: 'Theme',
          subtitle: 'Auto',
          onBack: () => backed++,
          children: const [Text('row')],
        ),
        padding: const EdgeInsets.only(top: 47),
      ),
    );
    // The bar sits below the status bar and the content starts under it.
    expect(tester.getSize(find.byType(PageBar)).height, pageToolbarHeight);
    expect(
      tester.getTopLeft(find.text('Theme')).dy,
      greaterThanOrEqualTo(47),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      (list.padding! as EdgeInsets).top,
      greaterThanOrEqualTo(47 + pageToolbarHeight),
    );
    // One back button, above the content, that pops the page.
    await tester.tap(find.byTooltip('Back'));
    expect(backed, 1);
    // The large title is the bar's alone.
    final titles = tester.widgetList<Text>(find.text('Theme'));
    expect(titles.length, 1);
    expect(titles.single.style!.fontSize, lessThan(20));
  });

  testWidgets('a first-level page keeps its large title until it scrolls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        PageBody(
          title: 'Settings',
          children: [for (var i = 0; i < 20; i++) Text('row $i')],
        ),
        padding: const EdgeInsets.only(top: 47),
      ),
    );
    // At rest the bar is out of the way and the large title names the page.
    expect(find.byType(PageBar, skipOffstage: true), findsNothing);
    final large = tester.widget<Text>(find.text('Settings'));
    expect(large.style!.fontSize, greaterThan(30));

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pump();

    // Once the title has scrolled under it, the bar carries the page's name.
    expect(find.byType(PageBar, skipOffstage: true), findsOneWidget);
    expect(
      tester
          .widgetList<Text>(find.text('Settings', skipOffstage: true))
          .map((text) => text.style!.fontSize),
      contains(lessThan(20)),
    );
  });
}
