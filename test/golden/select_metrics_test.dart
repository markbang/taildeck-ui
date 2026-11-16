@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/widgets/foundation.dart';
import 'package:taildeck_ui/src/widgets/select_row.dart';
import 'package:taildeck_ui/src/widgets/select_value_button.dart';

import 'golden_harness.dart';

// FlClash 0.9.3's menu metrics (plugins/prism_ui/lib/popup.dart, lib/ui/
// list_item.dart), which the menu is drawn from.
const _cardInset = 8.0;
const _rowExtent = 44.0;
const _itemPadding = 12.0;
const _arrowRight = 8.0;
const _arrowSize = 16.0;
const _menuMinWidth = 160.0;
const _menuMaxWidth = 280.0;
const _maxVisibleItems = 7;
const _screenMargin = 16.0;
const _anchorOverlap = 8.0;

const _languages = [
  ('system', 'System'),
  ('en', 'English'),
  ('zh', '中文'),
];

const _flclashLanguages = [
  ('default', 'Default'),
  ('en', 'English'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('ja', 'Japanese'),
  ('ko', 'Korean'),
  ('ru', 'Russian'),
  ('zh', 'Simplified Chinese'),
];

class _SelectPage extends StatefulWidget {
  const _SelectPage({
    this.options = _languages,
    this.value = 'en',
    this.margin = 16,
  });

  final List<(String, String)> options;
  final String value;
  final double margin;

  @override
  State<_SelectPage> createState() => _SelectPageState();
}

class _SelectPageState extends State<_SelectPage> {
  late String _value = widget.value;

  @override
  Widget build(BuildContext context) {
    return Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: PageBody(
        title: 'Settings',
        onBack: () {},
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.margin),
            child: Card(
              child: SelectRow<String>(
                label: 'Language',
                value: _value,
                options: widget.options,
                onChanged: (value) => setState(() => _value = value),
              ),
            ),
          ),
          const SizedBox(height: 1200),
        ],
      ),
    );
  }
}

Future<Rect> _open(WidgetTester tester, Widget page) async {
  usePhone(tester);
  await tester.pumpWidget(goldenApp(home: page));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byType(SelectValueButton));
  await pumpFrames(tester, const Duration(milliseconds: 600));
  return tester.getRect(find.byType(PopupMenuCard));
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  testWidgets('the menu keeps FlClash\'s rows and padding', (tester) async {
    final card = await _open(tester, const _SelectPage());

    // FlClash's card: the items' rows at 44 dp inside 8 dp of card padding.
    expect(card.height, _cardInset * 2 + _rowExtent * _languages.length);
    expect(card.width, greaterThanOrEqualTo(_menuMinWidth));
    expect(card.width, lessThanOrEqualTo(_menuMaxWidth));

    final texts = [
      for (final (_, label) in _languages) tester.getRect(find.text(label).last),
    ];
    for (var i = 1; i < texts.length; i++) {
      expect(
        texts[i].top - texts[i - 1].top,
        _rowExtent,
        reason: 'row ${i + 1} is not one FlClash row tall',
      );
    }
    // A row pads 12 dp above its label, inside the card's own 8 dp.
    expect(texts.first.top, card.top + _cardInset + _itemPadding);
    expect(texts.first.left, card.left + _cardInset + _itemPadding);

    // The check sits at the row's end, 8 dp in, 16 dp wide.
    final check = tester.getRect(find.byType(GlyphIcon).last);
    expect(check.width, _arrowSize);
    expect(card.right - check.right, _cardInset + _arrowRight);
  });

  testWidgets('the menu opens over its value, as FlClash\'s does', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(goldenApp(home: const _SelectPage()));
    await tester.pump(const Duration(milliseconds: 400));
    final value = tester.getRect(find.byType(SelectValueButton));
    await tester.tap(find.byType(SelectValueButton));
    await pumpFrames(tester, const Duration(milliseconds: 600));
    final card = tester.getRect(find.byType(PopupMenuCard));

    expect(card.top, value.top - _anchorOverlap);
    expect(card.right, value.right);
  });

  testWidgets('the value keeps FlClash\'s padding and hit area', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(goldenApp(home: const _SelectPage()));
    await tester.pump(const Duration(milliseconds: 400));
    final value = tester.getRect(find.byType(SelectValueButton));
    final row = tester.getRect(find.text('Language'));
    // TextButton's 48 dp minimum with 8 dp of horizontal padding.
    expect(value.height, greaterThanOrEqualTo(48));
    expect(value.top, lessThan(row.top));
    expect(value.bottom, greaterThan(row.bottom));
  });

  testWidgets('a long list caps at 7.5 rows, as FlClash\'s', (tester) async {
    final card = await _open(
      tester,
      const _SelectPage(options: _flclashLanguages, value: 'en'),
    );
    expect(card.height, _cardInset * 2 + (_maxVisibleItems + 0.5) * _rowExtent);
    expect(card.width, lessThanOrEqualTo(_menuMaxWidth));
    // The rows below the cap are scrolled to, not shown.
    final visible = find.text('Default').evaluate().length;
    expect(visible, 1);
  });

  testWidgets('the menu stays on a 414 dp screen beside the edge', (
    tester,
  ) async {
    // No margin: the value ends at the screen's edge, so the menu must come
    // back inside FlClash's 16 dp screen insets rather than off the edge.
    final card = await _open(
      tester,
      const _SelectPage(options: _flclashLanguages, value: 'en', margin: 0),
    );
    expect(card.left, greaterThanOrEqualTo(_screenMargin));
    expect(card.right, lessThanOrEqualTo(phoneSize.width - _screenMargin));
    expect(card.bottom, lessThanOrEqualTo(phoneSize.height - gestureBar - _screenMargin));
  });
}
