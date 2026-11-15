import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/demo/demo.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/pages/terminal_sessions.dart';
import 'package:taildeck_ui/src/terminal_appearance.dart';
import 'package:taildeck_ui/src/terminal_store.dart';

void main() {
  final store = TerminalStore();

  tearDown(store.dispose);

  testWidgets('the strip lists every session and switches on a tap', (
    tester,
  ) async {
    final first = store.open(
      node: demoSelfNode,
      credentials: const SshCredentials(user: 'root', port: 22),
    );
    final second = store.open(
      node: demoPeers.first,
      credentials: const SshCredentials(user: 'deploy', port: 2222),
    );
    SshTerminal? switched;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: TerminalSessionStrip(
            sessions: [first, second],
            current: first,
            palette: defaultTerminalPalette,
            onSwitch: (session) => switched = session,
          ),
        ),
      ),
    );

    expect(find.text('root@${demoSelfNode.name}'), findsOneWidget);
    expect(find.text('deploy@${demoPeers.first.name}'), findsOneWidget);

    await tester.tap(find.text('deploy@${demoPeers.first.name}'));
    expect(switched, same(second));

    switched = null;
    await tester.tap(find.text('root@${demoSelfNode.name}'));
    expect(switched, isNull, reason: 'the open session is not a switch');
  });
}
