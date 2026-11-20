import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/native/keys.dart';
import 'package:taildeck_ui/src/native/term.dart';
import 'package:taildeck_ui/src/terminal_input.dart';
import 'package:taildeck_ui/src/terminal_keys.dart';

/// A legacy (xterm) key encoder: what libghostty-vt sends for these keys
/// outside the Kitty protocol. The last test pins the real encoder to it.
class _LegacyTerm implements NativeTerm {
  @override
  TermReply? encodeKey(int key, int mods, {String? text, int unshifted = 0}) {
    final alt = mods & GhosttyMods.alt != 0 ? [0x1b] : <int>[];
    if (key == GhosttyKeys.enter) return Uint8List.fromList([...alt, 0x0d]);
    if (key == GhosttyKeys.backspace) return Uint8List.fromList([0x7f]);
    var ch = text;
    if (ch == null && key >= 20 && key < 46) {
      ch = String.fromCharCode(0x61 + key - 20);
    }
    if (ch == null) return null;
    final bytes = utf8.encode(ch);
    if (mods & GhosttyMods.ctrl != 0 && bytes.length == 1) {
      final b = bytes.single;
      if (b == 0x20) return Uint8List.fromList([...alt, 0]);
      if (b >= 0x40 && b < 0x80) {
        return Uint8List.fromList([...alt, b & 0x1f]);
      }
    }
    return Uint8List.fromList([...alt, ...bytes]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Harness {
  _Harness([NativeTerm? term]) : term = term ?? _LegacyTerm();

  final NativeTerm term;
  final ime = TextEditingController();
  final imeFocus = FocusNode();
  final keyFocus = FocusNode();
  final mods = TerminalMods();
  final sent = <int>[];
  late final input = TerminalInput(
    ime: ime,
    mods: mods,
    term: () => term,
    deliver: (bytes) => sent.addAll(bytes ?? const []),
    onModsConsumed: () {},
  );

  Future<void> pump(WidgetTester tester) async {
    input;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            focusNode: keyFocus,
            onKeyEvent: (node, event) => input.onKey(
              event,
              typing: imeFocus.hasFocus,
              held: ghosttyModsOf(HardwareKeyboard.instance),
            ),
            child: TextField(
              controller: ime,
              focusNode: imeFocus,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ),
        ),
      ),
    );
  }

  void armCtrl() => mods.tap(TerminalMod.ctrl, now: DateTime(2026));

  List<int> take() {
    final out = List<int>.of(sent);
    sent.clear();
    return out;
  }
}

TextEditingValue _typed(String text, {int? composeFrom}) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
  composing: composeFrom == null
      ? TextRange.empty
      : TextRange(start: composeFrom, end: text.length),
);

void main() {
  testWidgets('armed Ctrl turns a committed letter into a chord', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.showKeyboard(find.byType(TextField));

    for (var i = 0; i < 26; i++) {
      final letter = String.fromCharCode(0x61 + i);
      h.armCtrl();
      tester.testTextInput.updateEditingValue(_typed(letter));
      await tester.pump();
      expect(h.take(), [i + 1], reason: 'Ctrl+$letter');
      expect(h.mods.mask, 0, reason: 'armed Ctrl lasts one key');
      expect(h.ime.text, isEmpty, reason: 'a chord is not text');
    }

    for (final (key, byte) in [('[', 0x1b), (r'\', 0x1c), (']', 0x1d)]) {
      h.armCtrl();
      tester.testTextInput.updateEditingValue(_typed(key));
      await tester.pump();
      expect(h.take(), [byte], reason: 'Ctrl+$key');
    }

    tester.testTextInput.updateEditingValue(_typed('c'));
    await tester.pump();
    expect(h.take(), [0x63], reason: 'the next key is plain again');
  });

  testWidgets('armed Ctrl takes a letter the IME is still composing', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.showKeyboard(find.byType(TextField));

    h.armCtrl();
    tester.testTextInput.updateEditingValue(_typed('c', composeFrom: 0));
    await tester.pump();
    expect(h.take(), [0x03]);
    expect(h.mods.mask, 0);
    expect(h.ime.value.composing.isValid, isFalse);
    expect(tester.testTextInput.editingState?['text'], '');

    // The IME then commits nothing new: no stray "c" follows the chord.
    tester.testTextInput.updateEditingValue(_typed(''));
    await tester.pump();
    expect(h.take(), isEmpty);
  });

  testWidgets('a composition before the chord goes out as text first', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.showKeyboard(find.byType(TextField));

    tester.testTextInput.updateEditingValue(_typed('ls', composeFrom: 0));
    await tester.pump();
    expect(h.take(), isEmpty, reason: 'a composition waits for its commit');

    h.armCtrl();
    tester.testTextInput.updateEditingValue(_typed('lsc', composeFrom: 0));
    await tester.pump();
    expect(h.take(), [...'ls'.codeUnits, 0x03]);
    expect(h.ime.text, 'ls');

    // Backspace in the IME still deletes on the remote.
    tester.testTextInput.updateEditingValue(_typed('l'));
    await tester.pump();
    expect(h.take(), [0x7f]);
  });

  testWidgets('committing a held composition is not the armed key', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.showKeyboard(find.byType(TextField));

    tester.testTextInput.updateEditingValue(_typed('ls', composeFrom: 0));
    await tester.pump();
    h.armCtrl();
    tester.testTextInput.updateEditingValue(_typed('ls'));
    await tester.pump();
    expect(h.take(), 'ls'.codeUnits);
    expect(h.mods.mask, GhosttyMods.ctrl, reason: 'no key was typed yet');

    tester.testTextInput.updateEditingValue(_typed('lsd'));
    await tester.pump();
    expect(h.take(), [0x04]);
  });

  testWidgets('locked Ctrl chords every letter', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.showKeyboard(find.byType(TextField));

    h.mods
      ..tap(TerminalMod.ctrl, now: DateTime(2026))
      ..tap(TerminalMod.ctrl, now: DateTime(2026).add(Durations.short1));
    expect(h.mods.isLocked(TerminalMod.ctrl), isTrue);
    tester.testTextInput.updateEditingValue(_typed('a', composeFrom: 0));
    await tester.pump();
    tester.testTextInput.updateEditingValue(_typed('e', composeFrom: 0));
    await tester.pump();
    expect(h.take(), [0x01, 0x05]);
    expect(h.mods.mask, GhosttyMods.ctrl);
  });

  testWidgets('armed Alt prefixes ESC on an IME letter', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.showKeyboard(find.byType(TextField));

    h.mods.tap(TerminalMod.alt, now: DateTime(2026));
    tester.testTextInput.updateEditingValue(_typed('b', composeFrom: 0));
    await tester.pump();
    expect(h.take(), [0x1b, 0x62]);
  });

  testWidgets('hardware keys: held Ctrl, armed Ctrl and plain typing', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    h.keyFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(h.take(), [0x03]);

    h.armCtrl();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(h.take(), [0x03]);
    expect(h.mods.mask, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(h.take(), [0x63]);
  });

  test(
    'libghostty-vt: armed Ctrl on IME text gives the C0 byte',
    () {
      final term = createNativeTerm(cols: 80, rows: 24)!;
      final ime = TextEditingController();
      final mods = TerminalMods();
      final sent = <int>[];
      final input = TerminalInput(
        ime: ime,
        mods: mods,
        term: () => term,
        deliver: (bytes) => sent.addAll(bytes ?? const []),
        onModsConsumed: () {},
      );
      final cases = <(String, int)>[
        for (var i = 0; i < 26; i++) (String.fromCharCode(0x61 + i), i + 1),
        ('[', 0x1b),
        (r'\', 0x1c),
        (']', 0x1d),
        (' ', 0x00),
      ];
      for (final (ch, byte) in cases) {
        mods.tap(TerminalMod.ctrl, now: DateTime(2026));
        ime.value = _typed(ch, composeFrom: 0);
        expect(sent, [byte], reason: 'Ctrl+$ch');
        sent.clear();
      }
      mods.tap(TerminalMod.alt, now: DateTime(2026));
      mods.tap(TerminalMod.ctrl, now: DateTime(2026));
      ime.value = _typed('[');
      expect(sent, [0x1b, 0x1b], reason: 'Ctrl+Alt+[');
      input.dispose();
      term.dispose();
    },
    skip: nativeTermAvailable
        ? false
        : 'needs TAILDECK_TERM=<libtaildeck_term.so>',
  );

  testWidgets('libghostty-vt: hardware Ctrl+[ and Ctrl+I give Esc and Tab', (
    tester,
  ) async {
    final term = createNativeTerm(cols: 80, rows: 24)!;
    final h = _Harness(term);
    await h.pump(tester);
    h.keyFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(h.take(), [0x1b, 0x09, 0x03]);
    term.dispose();
  }, skip: !nativeTermAvailable);
}
