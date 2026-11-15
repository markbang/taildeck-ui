import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/shell.dart';

void main() {
  testWidgets('a controller with two positions does not throw', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SizedBox(
              height: 80,
              child: PageView(
                controller: controller,
                children: const [Text('a')],
              ),
            ),
            SizedBox(
              height: 80,
              child: PageView(
                controller: controller,
                children: const [Text('b')],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(controller.positions, hasLength(2));
    expect(tabOffset(controller, 0), 0);
  });

  testWidgets('a detached controller reads as no travel', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    expect(tabOffset(controller, 0), 0);
  });
}
