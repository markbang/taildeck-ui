import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/terminal_gestures.dart';

void main() {
  group('SwipeStepper', () {
    test('locks the axis it moved furthest along', () {
      final swipe = SwipeStepper(step: 20, slop: 5);
      expect(swipe.update(const Offset(2, 1)), isEmpty);
      expect(swipe.axis, isNull);
      final arrows = swipe.update(const Offset(20, 2));
      expect(swipe.axis, SwipeAxis.horizontal);
      expect(arrows, [TerminalArrow.right]);
    });

    test('one key per step and no zig-zag across the axis', () {
      final swipe = SwipeStepper(step: 20, slop: 1);
      expect(swipe.update(const Offset(0, 30)), [TerminalArrow.down]);
      expect(swipe.update(const Offset(60, 20)), [TerminalArrow.down]);
      expect(swipe.update(const Offset(60, -45)), [TerminalArrow.up]);
    });

    test('a flick is capped per update', () {
      final swipe = SwipeStepper(step: 10, slop: 1, maxPerUpdate: 3);
      expect(swipe.update(const Offset(200, 0)), hasLength(3));
    });

    test('reset forgets the axis', () {
      final swipe = SwipeStepper(step: 10, slop: 1);
      swipe.update(const Offset(40, 0));
      swipe.reset();
      expect(swipe.axis, isNull);
      expect(swipe.update(const Offset(0, 20)), [
        TerminalArrow.down,
        TerminalArrow.down,
      ]);
    });
  });

  test('wordRange widens over filled cells only', () {
    const line = 'ab  cd';
    bool filled(int column) => line[column] != ' ';
    expect(wordRange(1, line.length, filled), (from: 0, to: 1));
    expect(wordRange(5, line.length, filled), (from: 4, to: 5));
    expect(wordRange(2, line.length, filled), (from: 2, to: 2));
  });

  test('a wide character keeps its spacer in the word', () {
    // 你 at 10, its spacer at 11, 好 at 12, its spacer at 13.
    const spacerCells = {11, 13};
    const textCells = {10, 12};
    bool hasText(int column) => textCells.contains(column);
    bool spacer(int column) => spacerCells.contains(column);

    final range = wordRangeWithSpacers(
      10,
      20,
      hasText: hasText,
      spacer: spacer,
    );
    expect(range, (from: 10, to: 13));
  });

  test('urlInSelection accepts one link and drops trailing punctuation', () {
    expect(
      urlInSelection('https://tailscale.com/kb/1151'),
      'https://tailscale.com/kb/1151',
    );
    expect(
      urlInSelection('  http://example.com/a).  '),
      'http://example.com/a',
    );
    expect(urlInSelection('two words https://example.com'), isNull);
    expect(urlInSelection('ftp://example.com'), isNull);
    expect(urlInSelection('https://'), isNull);
    expect(urlInSelection(null), isNull);
  });

  test('font size clamps to the zoom limits', () {
    expect(clampTerminalFont(4), terminalFontMin);
    expect(clampTerminalFont(40), terminalFontMax);
    expect(clampTerminalFont(14), 14);
  });
}
