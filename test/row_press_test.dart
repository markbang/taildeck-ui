import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/theme.dart';
import 'package:taildeck_ui/src/widgets/controls.dart';
import 'package:taildeck_ui/src/widgets/foundation.dart';

final _boundary = GlobalKey();
const _rowHeight = 56.0;

Widget _app(ThemeMode mode, Widget body) {
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
      home: Builder(
        builder: (context) => Surface(
          color: SurfaceLevel.page.colorOf(context.colorScheme),
          child: body,
        ),
      ),
    ),
  );
}

Widget _listItems(int count) => generateGroup([
  for (var i = 0; i < count; i++)
    DecorationListItem(
      title: const SizedBox(height: _rowHeight - 24),
      onPressed: () {},
    ),
]);

Widget _tapRows(int count) => GroupCard(
  children: [
    for (var i = 0; i < count; i++)
      TapFeedback(
        onTap: () {},
        child: const SizedBox(height: _rowHeight),
      ),
  ],
);

class _Shot {
  _Shot(this.width, this.rgba);

  final int width;
  final Uint8List rgba;

  int at(Offset point) {
    final i = (point.dy.floor() * width + point.dx.floor()) * 4;
    return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
  }

  /// The box round every pixel that differs from [other].
  Rect changedFrom(_Shot other) {
    var left = width, top = 1 << 30, right = -1, bottom = -1;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i] == other.rgba[i] &&
          rgba[i + 1] == other.rgba[i + 1] &&
          rgba[i + 2] == other.rgba[i + 2]) {
        continue;
      }
      final x = (i ~/ 4) % width, y = (i ~/ 4) ~/ width;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
    if (right < 0) return Rect.zero;
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right + 1.0,
      bottom + 1.0,
    );
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

void _setUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(414, 896);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Presses a group's first, middle and last rows: the highlight is the row's
/// own rect in the group's corners, flat while held, gone after the release.
Future<void> _expectRowHighlights(
  WidgetTester tester,
  Finder rows, {
  required Duration release,
}) async {
  final rest = await _shot(tester);
  for (final index in [0, 1, 2]) {
    final row = tester.getRect(rows.at(index));
    final gesture = await tester.startGesture(row.center);
    await tester.pump();
    final pressed = await _shot(tester);
    final changed = pressed.changedFrom(rest);
    expect(changed.left, row.left, reason: 'row $index left');
    expect(changed.right, row.right, reason: 'row $index right');
    expect(changed.top, closeTo(row.top, 1), reason: 'row $index top');
    expect(changed.bottom, closeTo(row.bottom, 1), reason: 'row $index bottom');

    final inside = [
      Offset(row.left + 1, row.center.dy),
      Offset(row.left + 24, row.top + 2),
      row.center,
      Offset(row.right - 1.5, row.center.dy),
      Offset(row.right - 24, row.bottom - 2),
    ];
    final highlight = pressed.at(row.center);
    expect(highlight, isNot(rest.at(row.center)));
    for (final point in inside) {
      expect(pressed.at(point), highlight, reason: 'row $index at $point');
    }

    final topCorner = Offset(row.left + 1, row.top + 1);
    final bottomCorner = Offset(row.right - 1.5, row.bottom - 1.5);
    expect(
      pressed.at(topCorner) == highlight,
      index != 0,
      reason: 'row $index top corner',
    );
    expect(
      pressed.at(bottomCorner) == highlight,
      index != 2,
      reason: 'row $index bottom corner',
    );

    await tester.pump(const Duration(milliseconds: 300));
    final held = await _shot(tester);
    for (final point in inside) {
      expect(held.at(point), highlight, reason: 'row $index held at $point');
    }

    await gesture.up();
    await tester.pump();
    await tester.pump(release);
    await tester.pump(const Duration(milliseconds: 16));
    final after = await _shot(tester);
    expect(after.changedFrom(rest), Rect.zero, reason: 'row $index released');
  }
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('a list row highlights whole in its group corners '
        '(${mode.name})', (tester) async {
      _setUp(tester);
      await tester.pumpWidget(
        _app(
          mode,
          Padding(padding: const EdgeInsets.all(16), child: _listItems(3)),
        ),
      );
      await tester.pumpAndSettle();
      await _expectRowHighlights(
        tester,
        find.byType(DecorationListItem),
        release: const Duration(milliseconds: 100),
      );
    });

    testWidgets('a group card row highlights the same way (${mode.name})', (
      tester,
    ) async {
      _setUp(tester);
      await tester.pumpWidget(
        _app(
          mode,
          Padding(padding: const EdgeInsets.all(16), child: _tapRows(3)),
        ),
      );
      await tester.pumpAndSettle();
      await _expectRowHighlights(
        tester,
        find.byType(TapFeedback),
        release: const Duration(milliseconds: 60),
      );
    });
  }

  testWidgets('a drag that starts on a list row never presses it', (
    tester,
  ) async {
    _setUp(tester);
    await tester.pumpWidget(
      _app(ThemeMode.light, ListView(children: [_listItems(30)])),
    );
    await tester.pumpAndSettle();
    double pressed() => tester
        .widgetList<CardSurface>(find.byType(CardSurface))
        .fold(
          0.0,
          (most, surface) =>
              surface.pressed.value > most ? surface.pressed.value : most,
        );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DecorationListItem).at(5)),
    );
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -8));
      await tester.pump(const Duration(milliseconds: 16));
      expect(pressed(), 0, reason: 'frame $i');
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(pressed(), 0);
  });

  testWidgets('a drag that starts on a group card row never highlights it', (
    tester,
  ) async {
    _setUp(tester);
    await tester.pumpWidget(
      _app(ThemeMode.light, ListView(children: [_tapRows(30)])),
    );
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byType(TapFeedback).at(5));
    final rest = (await _shot(tester)).at(Offset(30, row.center.dy));

    final gesture = await tester.startGesture(Offset(30, row.center.dy));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -8));
      await tester.pump(const Duration(milliseconds: 16));
      final now = tester.getRect(find.byType(TapFeedback).at(5));
      expect(
        (await _shot(tester)).at(Offset(30, now.center.dy)),
        rest,
        reason: 'frame $i',
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
