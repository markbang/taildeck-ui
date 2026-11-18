@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/demo/demo_transcript.dart';
import 'package:taildeck_ui/src/markdown/markdown_view.dart';

import 'golden_harness.dart';

Widget _page(ThemeMode mode) => goldenApp(
  themeMode: mode,
  home: Builder(
    builder: (context) => Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, statusBar + 12, 20, 40),
        child: MarkdownView(
          demoAgentReply,
          style: AppTextStyle.body.of(context).copyWith(height: 1.45),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useGoldenComparator();
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('an agent reply renders as Markdown (${mode.name})', (
      tester,
    ) async {
      usePhone(tester, size: const Size(414, 1500));
      await tester.pumpWidget(_page(mode));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(PrismApp),
        matchesGoldenFile('goldens/markdown_${mode.name}.png'),
      );
    });
  }
}
