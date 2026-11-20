import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/terminal_appearance.dart';

const _nerdFile = 'assets/fonts/SymbolsNerdFontMono.ttf';
const _dejavuFile = 'assets/fonts/DejaVuSansMono.ttf';
const _cjkFile = 'assets/fonts/NotoSansCJK-subset.otf';

/// Whether the font's format 12 cmap, which covers every code point, maps
/// [codePoint] to a glyph.
bool _mapsCodePoint(ByteData font, int codePoint) {
  final tables = font.getUint16(4);
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes([
      for (var k = 0; k < 4; k++) font.getUint8(record + k),
    ]);
    if (tag != 'cmap') continue;
    final cmap = font.getUint32(record + 8);
    for (var j = 0; j < font.getUint16(cmap + 2); j++) {
      final subtable = cmap + font.getUint32(cmap + 4 + j * 8 + 4);
      if (font.getUint16(subtable) != 12) continue;
      final groups = font.getUint32(subtable + 12);
      for (var g = 0; g < groups; g++) {
        final at = subtable + 16 + g * 12;
        if (codePoint >= font.getUint32(at) &&
            codePoint <= font.getUint32(at + 4)) {
          return true;
        }
      }
      return false;
    }
  }
  return false;
}

Future<void> _loadFamily(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

double _widthOf(String text, String family, List<String> fallback) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 14,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the fallback list ends with the Nerd Font family', () {
    expect(terminalFontFallback, contains(nerdFontFamily));
    expect(terminalFontFallback.last, nerdFontFamily);
  });

  test('the bundled symbols font maps the Nerd Font code points', () async {
    final data = await rootBundle.load(_nerdFile);
    final font = data.buffer.asByteData();
    for (final cp in [0xE0A0, 0xE5FA, 0xF000, 0xF0001]) {
      expect(
        _mapsCodePoint(font, cp),
        isTrue,
        reason: 'U+${cp.toRadixString(16).toUpperCase()}',
      );
    }
  });

  test('a Nerd Font icon measures one grid cell wide', () async {
    await _loadFamily(terminalFontFamily(TerminalFontId.dejavu), _dejavuFile);
    await _loadFamily(nerdFontFamily, _nerdFile);
    await _loadFamily('NotoSansCJK', _cjkFile);
    final family = terminalFontFamily(TerminalFontId.dejavu);
    final cell = _widthOf('M', family, terminalFontFallback);
    expect(cell, greaterThan(0));
    for (final icon in ['\uE0A0', '\uE5FA', '\uF000', '\u{F0001}']) {
      expect(
        _widthOf(icon, family, terminalFontFallback),
        closeTo(cell, 0.01),
        reason: 'U+${icon.runes.single.toRadixString(16).toUpperCase()}',
      );
    }
  });
}
