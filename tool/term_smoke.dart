// Smoke test for the libghostty-vt FFI binding: build the library with
// tool/build_term.sh, then `dart run tool/term_smoke.dart [path/to/lib]`.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:taildeck_ui/src/native/term.dart';
import 'package:taildeck_ui/src/native/term_demo.dart';

var _failures = 0;

void check(bool ok, String what) {
  print('${ok ? 'ok  ' : 'FAIL'}  $what');
  if (!ok) _failures++;
}

void checkBytes(List<int>? actual, List<int>? expected, String what) {
  final ok = actual != null &&
      expected != null &&
      actual.length == expected.length &&
      Iterable<int>.generate(actual.length).every((i) => actual[i] == expected[i]);
  print('${ok ? 'ok  ' : 'FAIL'}  $what${ok ? '' : ' (got $actual, want $expected)'}');
  if (!ok) _failures++;
}

void checkEq(Object? actual, Object? expected, String what) {
  final ok = actual == expected;
  print('${ok ? 'ok  ' : 'FAIL'}  $what${ok ? '' : ' (got $actual, want $expected)'}');
  if (!ok) _failures++;
}

Uint8List ansi(String s) => Uint8List.fromList(utf8.encode(s));

String rowText(TermSnapshot s, int y) {
  final b = StringBuffer();
  for (var x = 0; x < s.cols; x++) {
    // Wide glyphs carry a spacer cell; it paints nothing.
    if (s.flagsAt(x, y) & TermFlags.spacer != 0) continue;
    final cp = s.codepointAt(x, y);
    b.write(cp == 0 ? ' ' : String.fromCharCode(cp));
  }
  return b.toString().trimRight();
}

int findCell(TermSnapshot s, int y, int codepoint) {
  for (var x = 0; x < s.cols; x++) {
    if (s.codepointAt(x, y) == codepoint) return x;
  }
  return -1;
}

int findRow(TermSnapshot s, String needle) {
  for (var y = 0; y < s.rows; y++) {
    if (rowText(s, y).contains(needle)) return y;
  }
  return -1;
}

int findCol(TermSnapshot s, int y, String needle) {
  final text = rowText(s, y);
  final i = text.indexOf(needle);
  return i < 0 ? -1 : i;
}

String hex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'linux/lib/libtaildeck_term.so';
  final term = createNativeTerm(cols: 80, rows: 24, libraryPath: path);
  if (term == null) {
    print('term_smoke: cannot open $path (run tool/build_term.sh)');
    _failures++;
    return _report(term);
  }
  print('lib: $path (${term.cols}x${term.rows})');

  // Plain text and cursor movement.
  check(term.write(ansi('hello')) == null, 'write returns no reply');
  var s = term.snapshot();
  checkEq(s.cols, 80, 'cols');
  checkEq(s.rows, 24, 'rows');
  checkEq(s.codepointAt(0, 0), 'h'.codeUnitAt(0), 'cell(0,0) text');
  check(rowText(s, 0) == 'hello', 'row 0 reads back');
  checkEq(s.cursorX, 5, 'cursor x after 5 chars');
  checkEq(s.cursorY, 0, 'cursor y');
  check(s.cursorVisible, 'cursor visible');

  // Colors: bold red, then reset.
  term.write(ansi('\r\n\x1b[1;31mred\x1b[0m \x1b[32mgreen\x1b[0m'));
  s = term.snapshot();
  final redY = findRow(s, 'red green');
  final redX = findCol(s, redY, 'red');
  final greenX = findCol(s, redY, 'green');
  final redFg = s.fgAt(redX, redY);
  final greenFg = s.fgAt(greenX, redY);
  check(redFg != s.defaultFg, 'red cell has its own fg (${hex(redFg)})');
  check(greenFg != s.defaultFg, 'green cell has its own fg (${hex(greenFg)})');
  check(s.flagsAt(greenX, redY) & TermFlags.hasFg != 0, 'green cell reports hasFg');
  check(redFg != greenFg, 'red and green differ');
  check((redFg >> 16 & 0xFF) > (redFg >> 8 & 0xFF), 'red channel dominates in red');
  check(s.flagsAt(redX, redY) & TermFlags.bold != 0, 'red cell is bold');
  check(s.flagsAt(redX, redY) & TermFlags.hasFg != 0, 'red cell reports hasFg');
  checkEq(s.flagsAt(redX + 3, redY) & TermFlags.bold, 0, 'reset clears bold');

  // Underline and background.
  term.write(ansi('\r\n\x1b[4;44munder\x1b[0m'));
  s = term.snapshot();
  final ulY = findRow(s, 'under');
  final ulX = findCol(s, ulY, 'under');
  check(s.flagsAt(ulX, ulY) & TermFlags.underline != 0, 'underline flag');
  check(s.flagsAt(ulX, ulY) & TermFlags.hasBg != 0, 'background flag');
  check(s.bgAt(ulX, ulY) != s.defaultBg, 'blue background differs from default (${hex(s.bgAt(ulX, ulY))})');

  // A wide CJK glyph covers two cells: wide lead plus spacer tail.
  term.write(ansi('\r\n\x1b[0m中文 ok'));
  s = term.snapshot();
  final cjkY = findRow(s, '中文 ok');
  final cjkX = findCell(s, cjkY, '中'.codeUnitAt(0));
  check(s.flagsAt(cjkX, cjkY) & TermFlags.wide != 0, 'CJK lead cell is wide');
  checkEq(s.codepointAt(cjkX, cjkY), '中'.codeUnitAt(0), 'CJK codepoint');
  check(s.flagsAt(cjkX + 1, cjkY) & TermFlags.spacer != 0, 'CJK tail is a spacer');
  checkEq(term.codepointWidth('中'.codeUnitAt(0)), 2, 'codepoint width of 中');
  checkEq(term.codepointWidth('a'.codeUnitAt(0)), 1, 'codepoint width of a');
  checkEq(findCell(s, cjkY, 'o'.codeUnitAt(0)), cjkX + 5, 'text after 中文 keeps its cells');

  // Truecolor.
  term.write(ansi('\r\n\x1b[38;2;255;153;51morange\x1b[0m'));
  s = term.snapshot();
  final oy = findRow(s, 'orange');
  checkEq(hex(s.fgAt(findCol(s, oy, 'orange'), oy)), '#ff9933', 'truecolor fg');

  // Scrollback: 40 lines push the first ones off the viewport.
  term.write(ansi('\x1b[H\x1b[2J'));
  final lines = StringBuffer();
  for (var i = 1; i <= 40; i++) {
    lines.write('line $i\r\n');
  }
  term.write(ansi(lines.toString()));
  s = term.snapshot();
  check(s.scrollTotal > s.scrollLen, 'scrollback filled (${s.scrollTotal} > ${s.scrollLen})');
  check(findRow(s, 'line 40') >= 0, 'last line is on screen');
  checkEq(findRow(s, 'line 1 '), -1, 'first line scrolled away');
  term.scroll(-3);
  s = term.snapshot();
  checkEq(findRow(s, 'line 15'), 0, 'scrolling up puts line 15 on the first row');
  final line37 = findRow(s, 'line 37');
  check(line37 >= 0 && line37 <= s.rows - 1, 'line 37 is still on screen after scrolling up');
  checkEq(findRow(s, 'line 40'), -1, 'line 40 left the viewport');
  term.scroll(0);

  // Title and focus reporting.
  term.write(ansi('\x1b]0;smoke title\x07'));
  s = term.snapshot();
  checkEq(s.meta[TermMeta.titleChanged], 1, 'title change reported');
  checkEq(term.title(), 'smoke title', 'title text');
  check(term.encodeFocus(true) == null, 'focus report stays off unless enabled');
  term.write(ansi('\x1b[?1004h'));
  checkBytes(term.encodeFocus(true), ansi('\x1b[I'), 'focus report after 1004h');

  // Input encoding honors cursor-key mode.
  term.write(ansi('\x1b[?1h'));
  checkBytes(term.encodeKey(0x41, 0, text: 'a', unshifted: 0x61), ansi('a'), 'plain key encoding');
  check(term.encodeKey(0x0D, 0x02) != null, 'ctrl+enter encodes');

  // Selection text.
  term.write(ansi('\x1b[H\x1b[2Jsel text'));
  term.select(0, 0, 7, 0);
  checkEq(term.selectionText(), 'sel text', 'selection text');
  term.select(-1, -1, -1, -1);
  checkEq(term.selectionText(), null, 'cleared selection');

  // The canned session `?ssh=demo` feeds through the same emulator.
  term.write(demoSessionBytes());
  s = term.snapshot();
  final demoY = findRow(s, '全角中文');
  check(demoY >= 0, 'demo CJK line is on screen');
  check(findRow(s, 'truecolor #FF9933') >= 0, 'demo truecolor line is on screen');
  check(findCell(s, demoY, '全'.codeUnitAt(0)) >= 0, 'demo CJK glyphs are in the grid');
  check(findRow(s, './cjk') >= 0, 'demo prompt line is on screen');
  check(s.scrollTotal > s.scrollLen, 'demo has a scrolled-away region');

  print('');
  print(_dump(s));
  _report(term);
}

String _dump(TermSnapshot s) {
  final b = StringBuffer();
  b.writeln('dump ${s.cols}x${s.rows} cursor=(${s.cursorX},${s.cursorY}) '
      'fg=${hex(s.defaultFg)} bg=${hex(s.defaultBg)} scroll=${s.scrollOffset}/${s.scrollLen}/${s.scrollTotal}');
  for (var y = 0; y < s.rows; y++) {
    final line = rowText(s, y);
    if (line.isEmpty) continue;
    final styles = <String>[];
    for (var x = 0; x < s.cols; x++) {
      final flags = s.flagsAt(x, y);
      if (flags & TermFlags.hasFg == 0 && flags & TermFlags.hasBg == 0) continue;
      styles.add('$x:${hex(s.fgAt(x, y))}/${hex(s.bgAt(x, y))}:${flags.toRadixString(16)}');
      if (styles.length >= 4) break;
    }
    b.writeln('${y.toString().padLeft(2)} | $line${styles.isEmpty ? '' : '   [${styles.join(' ')}]'}');
  }
  return b.toString();
}

void _report(NativeTerm? term) {
  term?.dispose();
  print(_failures == 0 ? 'term_smoke: all checks passed' : 'term_smoke: $_failures failure(s)');
  if (_failures != 0) throw StateError('term_smoke failed');
}
