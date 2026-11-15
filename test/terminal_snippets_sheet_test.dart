import 'package:flutter/material.dart' hide TextField;
import 'package:prism_ui/prism_ui.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/storage.dart';
import 'package:taildeck_ui/src/pages/terminal_snippets_sheet.dart';
import 'package:taildeck_ui/src/terminal_snippets.dart';

class _MemoryStorage implements BackendStorage {
  StoredConfig config = const StoredConfig();

  @override
  Future<bool> hasSavedLogin() async => false;

  @override
  Future<StoredConfig> readConfig() async => config;

  @override
  Future<void> writeConfig(StoredConfig config) async => this.config = config;

  @override
  Future<String> stateDir() async => '/tmp/state';

  @override
  Future<String> sshDir() async => '/tmp/ssh';

  @override
  Future<String?> readServicesJson() async => null;

  @override
  Future<void> writeServicesJson(String json) async {}

  @override
  Future<String?> readIdentitiesJson() async => null;

  @override
  Future<void> writeIdentitiesJson(String json) async {}

  @override
  Future<String> sshKeyPath(String name) async => '/tmp/ssh/$name.key';

  @override
  Future<void> writeSshKey(String name, String contents) async {}

  @override
  Future<void> deleteSshKey(String name) async {}
}

void main() {
  testWidgets('a snippet is added, saved and written to the config', (
    tester,
  ) async {
    final storage = _MemoryStorage();
    final backend = TaildeckBackend(storage: storage);
    addTearDown(backend.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: BackendScope(
          backend: backend,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTerminalSnippetsSheet(
                context,
                backend: backend,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('No snippets yet. Save a command and send it from the terminal with one tap.'), findsOneWidget);

    await tester.tap(find.text('New snippet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Disk');
    await tester.enterText(find.byType(TextField).last, 'df -h');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Disk'), findsOneWidget);
    expect(backend.terminalSnippets, hasLength(1));
    expect(backend.terminalSnippets.single.command, 'df -h');
    expect(backend.terminalSnippets.single.enter, isTrue);
    expect(storage.config.terminalSnippets, hasLength(1));
  });

  testWidgets('a saved snippet is sent with one tap in the terminal', (
    tester,
  ) async {
    final backend = TaildeckBackend(storage: _MemoryStorage());
    addTearDown(backend.dispose);
    await backend.setTerminalSnippets([
      const TerminalSnippet(id: 'uptime', name: 'Uptime', command: 'uptime'),
    ]);
    TerminalSnippet? sent;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: BackendScope(
          backend: backend,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTerminalSnippetsSheet(
                context,
                backend: backend,
                onSend: (snippet) => sent = snippet,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uptime'));
    expect(sent?.command, 'uptime');
  });
}
