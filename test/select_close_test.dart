import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart' hide Card, ColorScheme, ThemeData;
import 'package:prism_ui/prism_ui.dart' as prism show ThemeMode;
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/theme.dart';
import 'package:taildeck_ui/src/widgets/select_row.dart';

final _boundary = GlobalKey();

Widget _app(Widget child) {
  return RepaintBoundary(
    key: _boundary,
    child: MediaQuery(
    data: const MediaQueryData(size: Size(414, 896)),
    child: PrismApp(
      title: 'Taildeck',
      theme: TaildeckTheme().dark,
      darkTheme: TaildeckTheme().dark,
      themeMode: prism.ThemeMode.dark,
      liquidGlass: LiquidGlassQuality.ultra,
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: const [Locale('en'), Locale('zh')],
      home: child,
    ),
  ),
  );
}

Widget _row() {
  return Scaffold(
    body: Center(
        child: SizedBox(
          width: 382,
          child: Card(
            child: SelectRow<String>(
              label: 'Language',
              value: 'en',
              options: const [
                ('system', 'System'),
                ('en', 'English'),
                ('zh', '中文'),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
  );
}

/// The frame's pixels, as a grey image of the whole screen.
Future<List<int>> _screen(WidgetTester tester) async {
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final rgba = bytes!.buffer.asUint8List();
    final grey = <int>[];
    for (var i = 0; i < rgba.length; i += 4) {
      grey.add((rgba[i] + rgba[i + 1] + rgba[i + 2]) ~/ 3);
    }
    return grey;
  }).then((value) => value!);
}

/// The mean grey of [rect] in a frame.
double _grey(List<int> frame, Rect rect) {
  const width = 414;
  var total = 0;
  var count = 0;
  for (var y = rect.top.round(); y < rect.bottom.round(); y++) {
    for (var x = rect.left.round(); x < rect.right.round(); x++) {
      total += frame[y * width + x];
      count++;
    }
  }
  return total / count;
}

/// Mean absolute difference of two frames inside [rect], in grey levels.
double _difference(List<int> a, List<int> b, Rect rect) {
  const width = 414;
  var total = 0;
  var count = 0;
  for (var y = rect.top.round(); y < rect.bottom.round(); y++) {
    for (var x = rect.left.round(); x < rect.right.round(); x++) {
      final at = y * width + x;
      total += (a[at] - b[at]).abs();
      count++;
    }
  }
  return total / count;
}

/// Every layer on screen, by type name, so a pane left over shows up.
List<String> _layerTypes(WidgetTester tester) => [
  for (final layer in tester.layers) layer.runtimeType.toString(),
];

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(414, 896);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('a value with no surface of its own keeps no drop on close', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_row()));
    await tester.pumpAndSettle();

    // Where the value sits, and how the row looks at rest: the golden.
    final value = tester.getRect(find.text('English'));
    final area = Rect.fromCenter(
      center: value.center,
      width: value.width + 56,
      height: value.height + 26,
    );
    final rest = await _screen(tester);
    final restLayers = _layerTypes(tester)
        .where((type) => type.contains('LiquidGlass'))
        .length;

    // Open from the value, as a thumb does, and let the menu unfold.
    await tester.tap(find.text('English'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('中文'), findsOneWidget, reason: 'the menu did not open');

    // Close it by tapping the page, one frame at a time.
    await tester.tapAt(const Offset(24, 24));
    final frames = <List<int>>[];
    final layers = <List<String>>[];
    for (var i = 0; i < 48; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(await _screen(tester));
      layers.add(_layerTypes(tester));
    }

    final diffs = [for (final frame in frames) _difference(frame, rest, area)];
    // A block at the value is brighter or darker than the row at rest, so the
    // measure is the mean grey of those frames against the row's, as the
    // emulator and web checks measure it.
    final restGrey = _grey(rest, area);
    final lifts = [
      for (final frame in frames) (_grey(frame, area) - restGrey).abs(),
    ];
    final dirty = [
      for (var i = 0; i < diffs.length; i++)
        if (diffs[i] > 0.2) i,
    ];
    expect(dirty, isNotEmpty, reason: 'the menu never covered the value');
    final last = dirty.last;
    final late = dirty.sublist(last - 5 < 0 ? 0 : last - 5);
    final worst = late.map((i) => lifts[i]).reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print('close: last differing frame $last of ${diffs.length}, '
        'worst lift ${worst.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('lifts ${lifts.map((d) => d.toStringAsFixed(1)).join(' ')}');
    // ignore: avoid_print
    print('diffs ${diffs.map((d) => d.toStringAsFixed(1)).join(' ')}');

    expect(
      worst,
      lessThan(1.0),
      reason: 'a block was still painted at the value: $lifts',
    );

    // Once it is done, the row is the row again.
    await tester.pumpAndSettle();
    final settled = await _screen(tester);
    expect(_difference(settled, rest, area), lessThan(0.2));
    // No glass pane of the drop is left on screen once the row is back.
    expect(
      _layerTypes(tester).where((type) => type.contains('LiquidGlass')).length,
      restLayers,
      reason: 'the drop kept a glass layer after the close',
    );
    expect(find.text('中文'), findsNothing);
  });
}
