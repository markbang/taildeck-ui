import 'package:flutter/material.dart' hide SelectionArea;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart' show SelectionArea;
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/pages/agent_command_output.dart';

final _long = [
  for (var i = 0; i < 40; i++)
    'line $i ${'/home/bang/src/taildeck-ui/native/bridge/transcript.go:$i ' * 6}',
].join('\n');

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: const [Locale('en'), Locale('zh')],
  home: Scaffold(
    body: SizedBox(width: 360, child: ListView(children: [child])),
  ),
);

void main() {
  testWidgets('long command output lays out, folds and scrolls inside', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CommandOutput(
          text: _long,
          style: const TextStyle(fontFamily: 'DejaVuSansMono', fontSize: 11.5),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);

    final text = find.textContaining('line 0 ');
    expect(tester.widget<Text>(text).data, endsWith('…'));
    final scroll = find.byType(SingleChildScrollView);
    expect(tester.getSize(scroll).width, lessThanOrEqualTo(360));
    expect(tester.getSize(text).width, greaterThan(360));

    final folded = tester.getSize(scroll).height;
    await tester.tap(scroll);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(text).data, _long);
    expect(tester.getSize(scroll).height, greaterThan(folded * 4));

    await tester.drag(scroll, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(text).dx, lessThan(0));
  });
}
