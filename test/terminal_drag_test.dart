import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/keys.dart';
import 'package:taildeck_ui/src/native/term.dart';
import 'package:taildeck_ui/src/pages/term_toolbar.dart';
import 'package:taildeck_ui/src/pages/term_view.dart';
import 'package:taildeck_ui/src/term_session.dart';
import 'package:taildeck_ui/src/terminal_appearance.dart';
import 'package:taildeck_ui/src/terminal_keys.dart';

/// Encodes like libghostty-vt for the cases the grid can produce: SGR mouse
/// reports when tracking is on, CSI arrows for the arrow keys.
class _FakeTerm implements NativeTerm {
  _FakeTerm({this.tracking = false, this.alternate = false});

  bool tracking;
  bool alternate;
  int offset = 80;
  final scrolls = <int>[];
  int selections = 0;

  static const _total = 100;

  @override
  int cols = 30;

  @override
  int rows = 10;

  @override
  TermSnapshot snapshot() {
    final cells = Int32List(cols * rows * 4);
    for (var i = 0; i < cols * rows; i++) {
      cells[i * 4] = 0x61;
    }
    final meta = Int32List(16);
    meta[TermMeta.mouseTracking] = tracking ? 1 : 0;
    meta[TermMeta.alternateScreen] = alternate ? 1 : 0;
    meta[TermMeta.scrollTotal] = _total;
    meta[TermMeta.scrollLen] = rows;
    meta[TermMeta.scrollOffset] = offset;
    return TermSnapshot(cols: cols, rows: rows, cells: cells, meta: meta);
  }

  @override
  void scroll(int delta) {
    scrolls.add(delta);
    offset = (offset + delta).clamp(0, _total - rows);
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
    if (!tracking) return null;
    final code = switch (button) {
      TerminalMouseButton.left => 0,
      TerminalMouseButton.middle => 1,
      TerminalMouseButton.right => 2,
      TerminalMouseButton.wheelUp => 64,
      TerminalMouseButton.wheelDown => 65,
      _ => 3,
    };
    final col = x ~/ cellWidth + 1;
    final row = y ~/ cellHeight + 1;
    final end = action == 0 ? 'M' : 'm';
    return Uint8List.fromList(utf8.encode('\x1b[<$code;$col;$row$end'));
  }

  @override
  TermReply? encodeKey(int key, int mods, {String? text, int unshifted = 0}) {
    final arrow = switch (key) {
      GhosttyKeys.arrowUp => 'A',
      GhosttyKeys.arrowDown => 'B',
      GhosttyKeys.arrowRight => 'C',
      GhosttyKeys.arrowLeft => 'D',
      _ => null,
    };
    return arrow == null
        ? null
        : Uint8List.fromList(utf8.encode('\x1b[$arrow'));
  }

  @override
  TermReply? resize(int cols, int rows, int cellWidth, int cellHeight) {
    this.cols = cols;
    this.rows = rows;
    return null;
  }

  @override
  void select(int x0, int y0, int x1, int y1) {
    if (x0 >= 0) selections++;
  }

  @override
  TermReply? write(Uint8List data) => null;

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
  _FakeTerm term,
  List<int> bytes, {
  ValueChanged<double>? onFontSize,
}) async {
  final session = TerminalSession(term);
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
            height: 500,
            child: TerminalCanvas(
              session: session,
              onBytes: bytes.addAll,
              onFontSize: onFontSize,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  term.scrolls.clear();
  term.offset = 60;
}

Future<void> _drag(WidgetTester tester, Offset by) async {
  final box = tester.getRect(find.byType(TerminalCanvas));
  await tester.timedDragFrom(
    box.center - by / 2,
    by,
    const Duration(milliseconds: 400),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

final _arrows = RegExp('\x1b[\\[O][ABCD]');

void main() {
  testWidgets('a drag on the normal screen scrolls and sends nothing', (
    tester,
  ) async {
    final term = _FakeTerm();
    final bytes = <int>[];
    await _pump(tester, term, bytes);
    final start = term.offset;

    await _drag(tester, const Offset(0, 200));
    expect(term.scrolls, isNotEmpty);
    expect(term.scrolls.every((delta) => delta < 0), isTrue);
    expect(term.offset, lessThan(start), reason: 'content follows the finger');

    final back = term.offset;
    term.scrolls.clear();
    await _drag(tester, const Offset(0, -200));
    expect(term.scrolls.every((delta) => delta > 0), isTrue);
    expect(term.offset, greaterThan(back));

    expect(bytes, isEmpty);
    expect(_arrows.hasMatch(latin1.decode(bytes)), isFalse);
    expect(term.selections, 0, reason: 'a drag never selects');
  });

  testWidgets('a drag stops at the top and leaves no carry', (tester) async {
    final term = _FakeTerm();
    final bytes = <int>[];
    await _pump(tester, term, bytes);

    for (var i = 0; i < 4; i++) {
      await _drag(tester, const Offset(0, 300));
    }
    expect(term.offset, 0);

    // 46 px is three lines and a remainder; a remainder kept across gestures
    // would turn one of these into four.
    term.scrolls.clear();
    for (var i = 0; i < 3; i++) {
      final box = tester.getRect(find.byType(TerminalCanvas));
      final gesture = await tester.startGesture(box.center);
      await gesture.moveBy(const Offset(0, -40));
      await gesture.moveBy(const Offset(0, -6));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(term.scrolls, [3, 3, 3]);
    expect(bytes, isEmpty);
  });

  testWidgets('with mouse tracking a drag sends only SGR wheel reports', (
    tester,
  ) async {
    final term = _FakeTerm(tracking: true, alternate: true);
    final bytes = <int>[];
    await _pump(tester, term, bytes);

    await _drag(tester, const Offset(0, 200));
    final up = latin1.decode(bytes);
    bytes.clear();
    await _drag(tester, const Offset(0, -200));
    final down = latin1.decode(bytes);

    final report = RegExp('\x1b\\[<(\\d+);(\\d+);(\\d+)M');
    expect(report.allMatches(up).map((m) => m[1]).toSet(), {'64'});
    expect(report.allMatches(down).map((m) => m[1]).toSet(), {'65'});
    expect(up.replaceAll(report, ''), isEmpty);
    expect(down.replaceAll(report, ''), isEmpty);
    expect(_arrows.hasMatch(up + down), isFalse);
    expect(report.allMatches(up).length, greaterThan(3));
    for (final match in report.allMatches(up)) {
      expect(int.parse(match[2]!), inInclusiveRange(1, term.cols));
      expect(int.parse(match[3]!), inInclusiveRange(1, term.rows));
    }
    expect(
      term.scrolls,
      isEmpty,
      reason: 'the program scrolls, not the buffer',
    );
  });

  testWidgets('the alternate screen without mouse reporting gets no bytes', (
    tester,
  ) async {
    final term = _FakeTerm(alternate: true);
    final bytes = <int>[];
    await _pump(tester, term, bytes);

    await _drag(tester, const Offset(0, 200));
    await _drag(tester, const Offset(0, -200));

    expect(bytes, isEmpty);
    expect(term.scrolls, isEmpty);
  });

  testWidgets('a long press selects and a drag after it extends', (
    tester,
  ) async {
    final term = _FakeTerm();
    final bytes = <int>[];
    await _pump(tester, term, bytes);

    final box = tester.getRect(find.byType(TerminalCanvas));
    final gesture = await tester.startGesture(
      box.topLeft + const Offset(40, 40),
    );
    await tester.pump(const Duration(milliseconds: 700));
    final selected = term.selections;
    expect(selected, greaterThan(0));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 60));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(term.selections, greaterThan(selected));
    expect(term.scrolls, isEmpty);
    expect(bytes, isEmpty);
  });

  testWidgets('a pinch still zooms', (tester) async {
    final term = _FakeTerm();
    final bytes = <int>[];
    final sizes = <double>[];
    await _pump(tester, term, bytes, onFontSize: sizes.add);

    final center = tester.getCenter(find.byType(TerminalCanvas));
    final a = await tester.startGesture(center - const Offset(0, 40));
    final b = await tester.startGesture(
      center + const Offset(0, 40),
      pointer: 2,
    );
    await a.moveBy(const Offset(0, -60));
    await b.moveBy(const Offset(0, 60));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(sizes, isNotEmpty);
    expect(sizes.last, greaterThan(13));
    expect(bytes, isEmpty);
  });

  testWidgets('the toolbar d-pad still sends the arrow', (tester) async {
    final term = _FakeTerm();
    final bytes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(411, 891)),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TerminalToolbar(
                palette: defaultTerminalPalette,
                mods: TerminalMods(),
                pages: defaultTerminalKeyPages,
                expanded: true,
                keyboardVisible: false,
                onToggleExpanded: () {},
                onKey: (key) => bytes.addAll(encodeTerminalKey(term, key, 0)!),
                onModifier: (_) {},
                onSnippets: () {},
                onPaste: () {},
                onCompose: () {},
                onKeyboard: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Up arrow'));
    await tester.pump();

    expect(latin1.decode(bytes), '\x1b[A');
  });
}
