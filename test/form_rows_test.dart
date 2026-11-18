import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/theme.dart';
import 'package:taildeck_ui/src/widgets/entry_row.dart';
import 'package:taildeck_ui/src/widgets/select_row.dart';

import 'golden/golden_harness.dart' show loadGoldenFonts;

final _boundary = GlobalKey();

class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _name = TextEditingController();
  final _port = TextEditingController(text: '3000');
  final _path = TextEditingController();
  String _node = 'nas';
  String _scheme = 'http';

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => Surface(
        color: SurfaceLevel.page.colorOf(context.colorScheme),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              generateGroup([
                SelectRow<String>(
                  label: 'Node',
                  value: _node,
                  options: const [('nas', 'nas'), ('devbox', 'devbox')],
                  onChanged: (value) => setState(() => _node = value),
                ),
                EntryRow(label: 'Name', controller: _name, hintText: 'Grafana'),
                SelectRow<String>(
                  label: 'Protocol',
                  value: _scheme,
                  options: const [('http', 'http'), ('https', 'https')],
                  onChanged: (value) => setState(() => _scheme = value),
                ),
                EntryRow(label: 'Port', controller: _port, numeric: true),
                EntryRow(label: 'Path', controller: _path, hintText: '/'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _app(ThemeMode mode) {
  final theme = TaildeckTheme();
  return RepaintBoundary(
    key: _boundary,
    child: PrismApp(
      title: 'Taildeck',
      theme: theme.light,
      darkTheme: theme.dark,
      themeMode: mode,
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: const [Locale('en'), Locale('zh')],
      debugShowCheckedModeBanner: false,
      home: const _Form(),
    ),
  );
}

class _Shot {
  _Shot(this.width, this.rgba);

  final int width;
  final Uint8List rgba;

  int at(double x, double y) {
    final i = (y.floor() * width + x.floor()) * 4;
    return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
  }
}

Future<_Shot> _shot(WidgetTester tester) async {
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final shot = _Shot(image.width, bytes!.buffer.asUint8List());
    image.dispose();
    return shot;
  }))!;
}

Future<void> _pump(WidgetTester tester, ThemeMode mode) async {
  tester.view.physicalSize = const Size(414, 896);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(mode));
  await tester.pumpAndSettle();
}

List<Rect> _rows(WidgetTester tester) => [
  for (final element in find.byType(DecorationListItem).evaluate())
    tester.getRect(find.byWidget(element.widget)),
];

void main() {
  _heldSelectWhileEditing();
  setUpAll(loadGoldenFonts);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('every form row shares one fill, corners and inset hairlines '
        '(${mode.name})', (tester) async {
      await _pump(tester, mode);
      final rows = _rows(tester);
      expect(rows, hasLength(5));
      final shot = await _shot(tester);
      final page = shot.at(4, 30);
      // A spot in each row's gap between label and value: no box, no fill of
      // its own, the same surface on select and text rows.
      final fill = shot.at(rows.first.left + 200, rows.first.center.dy);
      expect(fill, isNot(page));
      for (final (i, row) in rows.indexed) {
        expect(row.left, rows.first.left);
        expect(row.width, rows.first.width);
        for (final x in [row.left + 4, row.left + 200, row.center.dx]) {
          expect(shot.at(x, row.center.dy), fill, reason: 'row $i at $x');
        }
        if (i > 0) expect(row.top, rows[i - 1].bottom, reason: 'row $i gap');
      }
      // The group's corners: the first row's top and the last row's bottom
      // are round, the rows between are square.
      expect(shot.at(rows.first.left + 1, rows.first.top + 1), page);
      expect(shot.at(rows.first.right - 2, rows.first.top + 1), page);
      expect(shot.at(rows.last.left + 1, rows.last.bottom - 2), page);
      expect(shot.at(rows.last.right - 2, rows.last.bottom - 2), page);
      for (final row in rows.skip(1)) {
        expect(shot.at(row.left + 1, row.top + 1), fill);
      }
      for (final row in rows.take(rows.length - 1)) {
        expect(shot.at(row.left + 1, row.bottom - 1), fill);
      }
      // Hairlines between rows, inset from the start; none under the last.
      for (final row in rows.take(rows.length - 1)) {
        expect(shot.at(row.left + 4, row.bottom - 1), fill);
        expect(shot.at(row.left + 100, row.bottom - 1), isNot(fill));
      }
      expect(shot.at(rows.last.left + 100, rows.last.bottom - 3), fill);
    });
  }

  testWidgets('a select row leaves no tint after a press, release and switch', (
    tester,
  ) async {
    await _pump(tester, ThemeMode.light);
    final rest = await _shot(tester);
    final row = _rows(tester)[2];
    final probe = Offset(row.left + 200, row.center.dy);

    final gesture = await tester.startGesture(probe);
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      (await _shot(tester)).at(probe.dx, probe.dy),
      isNot(rest.at(probe.dx, probe.dy)),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('https').last);
    await tester.pumpAndSettle();
    expect(find.text('https'), findsOneWidget);

    final after = await _shot(tester);
    for (final (i, r) in _rows(tester).indexed) {
      for (final x in [r.left + 4, r.left + 200]) {
        expect(
          after.at(x, r.center.dy),
          rest.at(x, r.center.dy),
          reason: 'row $i at $x',
        );
      }
    }
  });

  testWidgets('a text row is edited inline and tints only while focused', (
    tester,
  ) async {
    await _pump(tester, ThemeMode.dark);
    final rest = await _shot(tester);
    final rows = _rows(tester);
    final name = rows[1];
    final probe = Offset(name.left + 4, name.center.dy);

    // The value sits at the row's end, on the row's own surface.
    final field = tester.getRect(find.byType(EditableText).first);
    expect(field.right, closeTo(name.right - 16, 1));
    expect(field.center.dy, closeTo(name.center.dy, 1));

    // A tap on the label focuses the value.
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(editable.focusNode.hasFocus, isTrue);
    final focused = await _shot(tester);
    expect(focused.at(probe.dx, probe.dy), isNot(rest.at(probe.dx, probe.dy)));
    expect(_rows(tester), rows, reason: 'focus moved a row');

    // A long value scrolls inside the field; the keyboard moves nothing.
    await tester.enterText(find.byType(EditableText).first, 'a' * 200);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(
      _rows(tester),
      rows,
      reason: 'a long value or the keyboard moved a row',
    );
    expect(tester.takeException(), isNull);

    // Focus elsewhere: the tint goes with it.
    await tester.tap(find.text('Port'));
    await tester.pumpAndSettle();
    final after = await _shot(tester);
    expect(after.at(probe.dx, probe.dy), rest.at(probe.dx, probe.dy));
  });
}

void _heldSelectWhileEditing() {
  testWidgets('a select held while a text row is focused opens on release', (
    tester,
  ) async {
    await _pump(tester, ThemeMode.dark);
    final rest = await _shot(tester);
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    final row = _rows(tester)[2];
    final probe = Offset(row.left + 200, row.center.dy);
    final gesture = await tester.startGesture(probe);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('https'), findsOneWidget, reason: 'the menu did not open');
    await tester.pumpAndSettle();
    expect(
      (await _shot(tester)).at(probe.dx, probe.dy),
      rest.at(probe.dx, probe.dy),
    );
  });
}
