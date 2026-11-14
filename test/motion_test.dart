import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/widgets/loading.dart';

void main() {
  test('the loading shapes stay inside their box and morph apart', () {
    const size = Size.square(24);
    final paths = [
      for (final shape in LoadingShape.sequence) shape.pathIn(size),
    ];
    for (final path in paths) {
      final bounds = path.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(-0.01));
      expect(bounds.top, greaterThanOrEqualTo(-0.01));
      expect(bounds.right, lessThanOrEqualTo(size.width + 0.01));
      expect(bounds.bottom, lessThanOrEqualTo(size.height + 0.01));
    }
    expect(paths.first.getBounds(), isNot(paths.last.getBounds()));

    final half = LoadingShape.lerp(
      LoadingShape.sequence.first,
      LoadingShape.sequence.last,
      0.5,
    );
    expect(half.radiusAt(0), isNot(LoadingShape.sequence.first.radiusAt(0)));
  });

  testWidgets('the loading dot runs and stops with reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      Theme(
        data: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B6BFF))),
        child: const Center(child: LoadingIndicator(size: 24)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });
}
