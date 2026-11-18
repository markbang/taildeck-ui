import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/terminal_gestures.dart';

void main() {
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
