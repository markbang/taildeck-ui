import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/widgets/foundation.dart';

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

  testWidgets('the status bar gets an opaque scrim once a page has one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const PageBody(title: 'Settings', children: [Text('row')]),
        padding: const EdgeInsets.only(top: 47),
      ),
    );
    final scrim = find.byWidgetPredicate(
      (widget) => widget is Container && widget.decoration is BoxDecoration,
    );
    expect(scrim, findsOneWidget);
  });
}
