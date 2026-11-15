import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/keys.dart';
import 'package:taildeck_ui/src/pages/term_key_bar.dart';
import 'package:taildeck_ui/src/terminal_keys.dart';

void main() {
  test('ctrl arms, locks on a double tap, and clears after a key', () {
    final mods = TerminalMods();
    final start = DateTime(2026, 11, 14, 12);

    mods.tap(TerminalMod.ctrl, now: start);
    expect(mods.isArmed(TerminalMod.ctrl), isTrue);
    expect(mods.mask, GhosttyMods.ctrl);

    mods.tap(
      TerminalMod.ctrl,
      now: start.add(const Duration(milliseconds: 120)),
    );
    expect(mods.isLocked(TerminalMod.ctrl), isTrue);
    expect(mods.consume(), isFalse, reason: 'a locked modifier survives a key');
    expect(mods.mask, GhosttyMods.ctrl);

    mods.tap(TerminalMod.ctrl, now: start.add(const Duration(seconds: 3)));
    expect(mods.mask, 0);
  });

  test('the insert-only key keeps its default page and sends no bytes', () {
    final pages = parseTerminalKeyPages(defaultTerminalKeyPages);
    expect(pages.expand((page) => page), contains('insert'));
    expect(terminalKeyById('insert')?.toggle, isTrue);
  });

  test('an armed modifier clears after the next key', () {
    final mods = TerminalMods()
      ..tap(TerminalMod.alt, now: DateTime(2026, 11, 14, 12));
    expect(mods.consume(), isTrue);
    expect(mods.mask, 0);
  });

  testWidgets('a horizontal drag turns the key row page', (tester) async {
    final pressed = <TerminalKey>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TerminalKeyBar(
              pages: defaultTerminalKeyPages,
              mods: TerminalMods(),
              onKey: pressed.add,
              onModifier: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Esc'), findsOneWidget);
    await tester.drag(find.text('Esc'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Esc'), findsNothing);

    await tester.tap(find.text('Home'));
    expect(pressed.single.id, 'home');
  });
}
