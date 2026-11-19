import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/storage.dart';
import 'package:taildeck_ui/src/pages/key_sheet.dart';

import 'golden/fake_backend.dart';

final class _NoIo extends IOOverrides {
  final touched = <String>[];

  @override
  File createFile(String path) {
    touched.add(path);
    return super.createFile(path);
  }

  @override
  Directory createDirectory(String path) {
    touched.add(path);
    return super.createDirectory(path);
  }
}

void main() {
  testWidgets('the key sheet opens on its first frame without file IO', (
    tester,
  ) async {
    final backend = TaildeckBackend(
      bridge: FakeBridge(),
      storage: MemoryStorage()..config = const StoredConfig(signedIn: true),
    );
    await tester.runAsync(backend.init);
    await tester.pumpWidget(
      PrismApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () => showKeySheet(context, backend),
            child: const Text('open'),
          ),
        ),
      ),
    );
    final io = _NoIo();
    await IOOverrides.runWithIOOverrides(() async {
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }, io);
    expect(find.byType(EditableText), findsWidgets);
    expect(io.touched, isEmpty);
    await tester.pumpAndSettle();
  });
}
