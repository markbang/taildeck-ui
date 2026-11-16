import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/pages/term_toolbar.dart';
import 'package:taildeck_ui/src/terminal_appearance.dart';
import 'package:taildeck_ui/src/terminal_keys.dart';

Future<void> _pump(
  WidgetTester tester, {
  required TerminalMods mods,
  required bool expanded,
  required bool keyboardVisible,
  required ValueChanged<TerminalKey> onKey,
  required ValueChanged<TerminalMod> onModifier,
  VoidCallback? onToggleExpanded,
  VoidCallback? onKeyboard,
}) async {
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
                mods: mods,
                pages: defaultTerminalKeyPages,
                expanded: expanded,
                keyboardVisible: keyboardVisible,
                onToggleExpanded: onToggleExpanded ?? () {},
                onKey: onKey,
                onModifier: onModifier,
                onSnippets: () {},
                onPaste: () {},
                onCompose: () {},
                onKeyboard: onKeyboard ?? () {},
              ),
            ),
          ),
        ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the capsule sends Esc, Tab and the sticky Ctrl', (tester) async {
    final keys = <TerminalKey>[];
    final mods = TerminalMods();
    await _pump(
      tester,
      mods: mods,
      expanded: false,
      keyboardVisible: false,
      onKey: keys.add,
      onModifier: (mod) => mods.tap(mod),
    );

    await tester.tap(find.text('Esc'));
    await tester.tap(find.text('Tab'));
    await tester.tap(find.text('Ctrl'));
    await tester.pump();

    expect(keys.map((key) => key.id), ['esc', 'tab']);
    expect(mods.isArmed(TerminalMod.ctrl), isTrue);
  });

  testWidgets('the keyboard button says what it does', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      mods: TerminalMods(),
      expanded: false,
      keyboardVisible: false,
      onKey: (_) {},
      onModifier: (_) {},
      onKeyboard: () => taps++,
    );
    expect(find.bySemanticsLabel('Show keyboard'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Show keyboard'));
    expect(taps, 1);

    await _pump(
      tester,
      mods: TerminalMods(),
      expanded: false,
      keyboardVisible: true,
      onKey: (_) {},
      onModifier: (_) {},
    );
    expect(find.bySemanticsLabel('Hide keyboard'), findsOneWidget);
  });

  testWidgets('the d-pad opens the arrows and the custom keys', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      mods: TerminalMods(),
      expanded: true,
      keyboardVisible: false,
      onKey: (_) {},
      onModifier: (_) {},
      onToggleExpanded: () => opened++,
    );

    expect(find.bySemanticsLabel('Left arrow'), findsOneWidget);
    // The user's own pages follow the fixed arrow page.
    final semantics = tester.ensureSemantics();
    for (var page = 0; page < 2; page++) {
      await tester.drag(find.bySemanticsLabel('Left arrow'), const Offset(-600, 0));
      await tester.pumpAndSettle();
    }
    expect(find.bySemanticsLabel('Page up'), findsOneWidget);
    semantics.dispose();
    await tester.tap(find.bySemanticsLabel('Arrow keys and more'));
    expect(opened, 1);
  });
}
