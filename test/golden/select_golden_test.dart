@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/widgets/foundation.dart';
import 'package:taildeck_ui/src/widgets/select_row.dart';
import 'package:taildeck_ui/src/widgets/select_value_button.dart';

import 'golden_harness.dart';

const _options = [
  ('follow', 'Follow system'),
  ('taildeck', 'Taildeck'),
  ('midnight', 'Midnight'),
];

class _SelectPage extends StatefulWidget {
  const _SelectPage();

  @override
  State<_SelectPage> createState() => _SelectPageState();
}

class _SelectPageState extends State<_SelectPage> {
  String _value = 'follow';

  @override
  Widget build(BuildContext context) {
    return Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: PageBody(
        title: 'Terminal',
        onBack: () {},
        children: [
          generateGroup([
            SelectRow<String>(
              label: 'Colors',
              value: _value,
              options: _options,
              onChanged: (value) => setState(() => _value = value),
            ),
            const SizedBox(height: 1200),
          ]),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useGoldenComparator();
    pinGoldenMotion();
  });

  testWidgets('the select opens out of its value and returns into it', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(goldenApp(home: const _SelectPage()));
    await tester.pump(const Duration(milliseconds: 400));

    final row = find.byType(SelectValueButton);
    final rect = tester.getRect(row);
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/select_rest.png'),
    );

    await tester.tapAt(tester.getCenter(row));
    await pumpFrames(tester, const Duration(milliseconds: 96));
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/select_opening.png'),
    );
    await pumpFrames(tester, const Duration(milliseconds: 500));
    expect(find.text('Midnight'), findsOneWidget);
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/select_open.png'),
    );

    await tester.tap(find.text('Midnight'));
    await pumpFrames(tester, const Duration(milliseconds: 96));
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/select_closing.png'),
    );
    await pumpFrames(tester, const Duration(seconds: 1));

    // The menu is gone, not merely invisible, and the row is what it was.
    expect(find.byType(PopupMenu, skipOffstage: false), findsNothing);
    expect(
      tester
          .widgetList<ImageFiltered>(
            find.byType(ImageFiltered, skipOffstage: false),
          )
          .where((blur) => blur.enabled),
      isEmpty,
    );
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      false,
    );
    expect(find.text('Midnight'), findsOneWidget);
    expect(find.text('Taildeck'), findsNothing);
    final settled = tester.getRect(row);
    expect(settled.right, rect.right);
    expect(settled.top, rect.top);
    expect(settled.bottom, rect.bottom);

    // Choose the value already set: closing must return the row to the very
    // pixels it had before the menu opened, with no layer left over it.
    await tester.tapAt(tester.getCenter(row));
    await pumpFrames(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Follow system').last);
    await pumpFrames(tester, const Duration(seconds: 1));
    expect(find.text('Midnight'), findsNothing);
    expect(tester.getRect(row), rect);
    await expectLater(
      find.byType(PrismApp),
      matchesGoldenFile('goldens/select_rest.png'),
    );
  });
}
