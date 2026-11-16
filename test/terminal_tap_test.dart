import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/term.dart';
import 'package:taildeck_ui/src/pages/term_view.dart';
import 'package:taildeck_ui/src/term_session.dart';

class _Mouse {
  const _Mouse(this.action, this.button, this.pressed, this.x, this.y, this.mods);

  final int action;
  final int button;
  final bool pressed;
  final double x;
  final double y;
  final int mods;
}

class _FakeTerm implements NativeTerm {
  _FakeTerm({this.tracking = true, this.scrollOffset = 0});

  bool tracking;
  int scrollOffset;
  final mice = <_Mouse>[];
  final scrolls = <int>[];
  final resizes = <(int, int)>[];
  int selected = -1;

  @override
  int cols = 20;

  @override
  int rows = 10;

  @override
  TermSnapshot snapshot() {
    final cells = Int32List(cols * rows * 4);
    for (var x = 0; x < cols; x++) {
      cells[(3 * cols + x) * 4] = 0x61; // a row of 'a'
    }
    final meta = Int32List(16);
    meta[TermMeta.mouseTracking] = tracking ? 1 : 0;
    meta[TermMeta.scrollTotal] = 100;
    meta[TermMeta.scrollLen] = rows;
    meta[TermMeta.scrollOffset] = scrollOffset;
    return TermSnapshot(cols: cols, rows: rows, cells: cells, meta: meta);
  }

  @override
  TermReply? encodeMouse({
    required int action,
    required int button,
    required bool pressed,
    required double x,
    required double y,
    required int width,
    required int height,
    required int cellWidth,
    required int cellHeight,
    int mods = 0,
  }) {
    mice.add(_Mouse(action, button, pressed, x, y, mods));
    return Uint8List.fromList([action, button, pressed ? 1 : 0]);
  }

  @override
  TermReply? resize(int cols, int rows, int cellWidth, int cellHeight) {
    resizes.add((cols, rows));
    this.cols = cols;
    this.rows = rows;
    return null;
  }

  @override
  void scroll(int delta) => scrolls.add(delta);

  @override
  void select(int x0, int y0, int x1, int y1) => selected = x0;

  @override
  TermReply? write(Uint8List data) => null;

  @override
  TermReply? encodeKey(int key, int mods, {String? text, int unshifted = 0}) =>
      null;

  @override
  TermReply? encodeFocus(bool gained) => null;

  @override
  TermReply? encodePaste(Uint8List data) => null;

  @override
  TermReply? takeClipboard() => null;

  @override
  String? selectionText() => null;

  @override
  String? title() => null;

  @override
  int codepointWidth(int codepoint) => 1;

  @override
  void dispose() {}
}

Future<void> _pump(
  WidgetTester tester,
  TerminalSession session, {
  required ValueChanged<Uint8List> onBytes,
  VoidCallback? onMouseSent,
  int mods = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 320,
            child: TerminalCanvas(
              session: session,
              onBytes: onBytes,
              onMouseSent: onMouseSent,
              mouseMods: mods,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a tap clicks a tracking program and asks for no keyboard', (
    tester,
  ) async {
    final term = _FakeTerm();
    final session = TerminalSession(term);
    var sent = 0;
    final bytes = <int>[];
    await _pump(
      tester,
      session,
      onBytes: bytes.addAll,
      onMouseSent: () => sent++,
      mods: 6,
    );

    await tester.tapAt(tester.getCenter(find.byType(TerminalCanvas)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('terminal-ime'));
    expect(term.mice, hasLength(2));
    expect(term.mice[0].action, 0);
    expect(term.mice[0].pressed, isTrue);
    expect(term.mice[1].action, 1);
    expect(term.mice[1].pressed, isFalse);
    for (final mouse in term.mice) {
      expect(mouse.button, TerminalMouseButton.left);
      expect(mouse.mods, 6);
      expect(mouse.x, greaterThanOrEqualTo(0));
      expect(mouse.y, greaterThanOrEqualTo(0));
    }
    expect(bytes, isNotEmpty);
    expect(sent, 1);
  });

  testWidgets('a second tap and a tap on a blank cell still click', (
    tester,
  ) async {
    final term = _FakeTerm();
    final session = TerminalSession(term);
    await _pump(tester, session, onBytes: (_) {});

    final canvas = tester.getRect(find.byType(TerminalCanvas));
    await tester.tapAt(canvas.center);
    await tester.pump(const Duration(milliseconds: 400));
    // The bottom padding is blank space, not a cell.
    await tester.tapAt(canvas.bottomCenter - const Offset(0, 4));
    await tester.pump(const Duration(milliseconds: 400));

    expect(term.mice, hasLength(4));
  });

  testWidgets('a terminal without mouse reporting sends no click', (
    tester,
  ) async {
    final term = _FakeTerm(tracking: false);
    final session = TerminalSession(term);
    await _pump(tester, session, onBytes: (_) {});

    await tester.tapAt(tester.getCenter(find.byType(TerminalCanvas)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(term.mice, isEmpty);
  });

  testWidgets('a long press selects the word without the keyboard', (
    tester,
  ) async {
    final term = _FakeTerm();
    final session = TerminalSession(term);
    await _pump(tester, session, onBytes: (_) {});

    final box = tester.getRect(find.byType(TerminalCanvas));
    await tester.longPressAt(box.topLeft + const Offset(30, 70));
    await tester.pumpAndSettle();

    expect(term.selected, isNot(-1));
    expect(term.mice, isEmpty, reason: 'a long press is not a click');
  });

  testWidgets('a resize follows the cursor back to the live screen', (
    tester,
  ) async {
    final term = _FakeTerm(scrollOffset: 5);
    final session = TerminalSession(term);
    await _pump(tester, session, onBytes: (_) {});
    await tester.pump();

    expect(term.resizes, isNotEmpty);
    // 100 lines total, the viewport is the rows after the resize.
    expect(term.scrolls, isNotEmpty);
    expect(term.scrolls.last, 100 - term.rows - 5);
  });
}
