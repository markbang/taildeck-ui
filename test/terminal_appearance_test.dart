import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/native/term.dart';
import 'package:taildeck_ui/src/terminal_appearance.dart';

void main() {
  test('follow picks a light or dark palette from the app', () {
    expect(
      terminalPaletteOf(TerminalThemeId.follow, Brightness.dark).id,
      TerminalThemeId.taildeck,
    );
    expect(
      terminalPaletteOf(TerminalThemeId.follow, Brightness.light).id,
      TerminalThemeId.paper,
    );
  });

  test('every palette is defined and has its own colors', () {
    for (final id in TerminalThemeId.values) {
      if (id == TerminalThemeId.follow) continue;
      final palette = terminalPalettes[id]!;
      expect(palette.background, isNot(palette.foreground));
      expect(palette.cursor, isNot(palette.background));
    }
    expect(terminalPalettes.length, greaterThanOrEqualTo(4));
  });

  test('a light palette inverts the page, not only the grid', () {
    final paper = terminalPaletteOf(TerminalThemeId.paper, Brightness.dark);
    expect(paper.isLight, isTrue);
    expect(
      paper.background.computeLuminance(),
      greaterThan(paper.foreground.computeLuminance()),
    );
  });

  test('unknown stored ids keep the defaults', () {
    expect(parseTerminalThemeId('nope'), TerminalThemeId.follow);
    expect(parseTerminalThemeId(null), TerminalThemeId.follow);
    expect(parseTerminalThemeId('midnight'), TerminalThemeId.midnight);
    expect(parseTerminalFontId('mono-from-the-future'), TerminalFontId.dejavu);
    expect(parseTerminalCursorId('bar'), TerminalCursorId.bar);
  });

  test('the cursor setting overrides the program only when set', () {
    expect(terminalCursorStyleOf(TerminalCursorId.follow, CursorStyle.bar), CursorStyle.bar);
    expect(terminalCursorStyleOf(TerminalCursorId.block, CursorStyle.bar), CursorStyle.block);
    expect(
      terminalCursorStyleOf(TerminalCursorId.underline, CursorStyle.block),
      CursorStyle.underline,
    );
  });

  test('font ids name a family, with a CJK fallback', () {
    expect(terminalFontFamily(TerminalFontId.dejavu), 'DejaVuSansMono');
    expect(terminalFontFamily(TerminalFontId.systemMono), 'monospace');
    expect(terminalFontFamily(TerminalFontId.sans), 'Roboto');
    expect(terminalFontFallback, contains('NotoSansCJK'));
  });
}
