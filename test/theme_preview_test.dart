import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/theme.dart';
import 'package:taildeck_ui/src/widgets/theme_preview.dart';

void main() {
  for (final size in const [Size(96, 128), Size(96, 181), Size(168, 317)]) {
    testWidgets('mini screen $size lays out', (tester) async {
      final theme = TaildeckTheme();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: MiniScreen(colorScheme: theme.dark.colorScheme),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('thumbnail lays out', (tester) async {
    final theme = TaildeckTheme();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MiniScreenThumb(
          screen: MiniScreen(colorScheme: theme.dark.colorScheme),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
