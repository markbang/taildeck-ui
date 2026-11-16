import 'package:flutter/material.dart' hide TextField;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart' show TextField;
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/storage.dart';
import 'package:taildeck_ui/src/pages/terminal_compose_sheet.dart';

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

Future<void> _open(
  WidgetTester tester,
  TaildeckBackend backend, {
  required void Function(String?) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: const [Locale('en')],
      home: BackendScope(
        backend: backend,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(
                await showTerminalComposeSheet(context, backend: backend),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Compose returns the text it held', (tester) async {
    final backend = TaildeckBackend(storage: _MemoryStorage());
    addTearDown(backend.dispose);
    String? sent;
    await _open(tester, backend, onResult: (text) => sent = text);

    await tester.enterText(find.byType(TextField), 'echo 你好\necho done');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(sent, 'echo 你好\necho done');
  });

  testWidgets('Compose appends the clipboard, CJK included', (tester) async {
    final backend = TaildeckBackend(storage: _MemoryStorage());
    addTearDown(backend.dispose);
    String? sent;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': '你好'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _open(tester, backend, onResult: (text) => sent = text);

    await tester.tap(find.byTooltip('Paste'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '你好',
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent, '你好');
  });

  testWidgets('Compose can leave the Enter off, and the setting sticks', (
    tester,
  ) async {
    final backend = TaildeckBackend(storage: _MemoryStorage());
    addTearDown(backend.dispose);
    await _open(tester, backend, onResult: (_) {});

    expect(backend.terminalSendEnter, isTrue);
    await tester.tap(find.bySemanticsLabel(RegExp('Append Enter')));
    await tester.pumpAndSettle();
    expect(backend.terminalSendEnter, isFalse);
  });
}
