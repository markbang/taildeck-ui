import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' hide TextButton;
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/motion.dart';

Widget _app({
  required int index,
  required bool fade,
  bool animate = true,
  VoidCallback? onSwitch,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Column(
        children: [
          Expanded(
            child: TabSwitcher(
              index: index,
              count: 3,
              fade: fade,
              animate: animate,
              background: const Color(0xFF101214),
              pageBuilder: (context, i) => Center(child: Text('page$i')),
            ),
          ),
          TextButton(onPressed: onSwitch, child: const Text('switch')),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('at rest only the current page is painted', (tester) async {
    for (final fade in [false, true]) {
      await tester.pumpWidget(_app(index: 1, fade: fade));
      expect(find.text('page1'), findsOneWidget);
      expect(find.text('page0'), findsNothing);
      expect(find.text('page2'), findsNothing);
    }
  });

  testWidgets('a fade-through never paints two pages at once', (tester) async {
    await tester.pumpWidget(_app(index: 0, fade: true));
    await tester.pumpWidget(_app(index: 1, fade: true));
    for (var step = 0; step < 20; step++) {
      await tester.pump(const Duration(milliseconds: 15));
      final painted = [
        for (final i in [0, 1, 2])
          if (find.text('page$i').evaluate().isNotEmpty) i,
      ];
      expect(painted.length, lessThanOrEqualTo(1), reason: 'step $step');
      if (painted.isEmpty) continue;
    }
    await tester.pumpAndSettle();
    expect(find.text('page1'), findsOneWidget);
  });

  testWidgets('a slide keeps both pages opaque', (tester) async {
    await tester.pumpWidget(_app(index: 0, fade: false));
    await tester.pumpWidget(_app(index: 1, fade: false));
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('page0'), findsOneWidget);
    expect(find.text('page1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TabSwitcher),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(find.text('page0'), findsNothing);
  });

  testWidgets('rapid switches end on the last tab', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _app(
          index: index,
          fade: false,
          onSwitch: () => setState(() => index = (index + 1) % 3),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('switch'));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(find.text('page2'), findsOneWidget);
    expect(find.textContaining('page'), findsOneWidget);
  });

  testWidgets('a wide layout jumps without animating', (tester) async {
    await tester.pumpWidget(_app(index: 0, fade: false, animate: false));
    await tester.pumpWidget(_app(index: 2, fade: false, animate: false));
    await tester.pump();
    expect(find.text('page2'), findsOneWidget);
    expect(find.text('page0'), findsNothing);
  });
}
