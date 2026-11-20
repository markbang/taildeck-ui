import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/glyphs.dart';
import 'package:taildeck_ui/src/motion.dart';

import 'golden/golden_harness.dart';

const _tabs = [Glyphs2.nodes, Glyphs2.grid, Glyphs2.agents, Glyphs2.sliders];

Widget _dock(int selected) => goldenApp(
  home: Align(
    alignment: Alignment.bottomCenter,
    child: NavigationDock(
      destinations: [
        for (final (index, glyph) in _tabs.indexed)
          NavigationDockDestination(glyph: glyph, label: 'Tab $index'),
      ],
      selectedIndex: selected,
      onSelected: (_) {},
    ),
  ),
);

double _fillOf(WidgetTester tester, Glyph glyph) {
  final fills = {
    for (final icon in tester.widgetList<GlyphIcon>(find.byType(GlyphIcon)))
      if (icon.glyph == glyph) icon.fill ?? 0,
  };
  expect(fills, hasLength(1), reason: 'every copy of a tab draws one state');
  return fills.single;
}

Widget _bare(Widget child, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: IconTheme(
      data: const IconThemeData(color: Color(0xFF000000)),
      child: Center(child: child),
    ),
  ),
);

void main() {
  test('every tab glyph has a body to fill when it is active', () {
    for (final glyph in _tabs) {
      expect(
        glyph.shapes.where((shape) => shape.role == GlyphRole.body),
        isNotEmpty,
      );
    }
  });

  testWidgets(
    'a dock tab fills as the lens reaches it and drains as it leaves',
    (tester) async {
      await tester.pumpWidget(_dock(0));
      await tester.pumpAndSettle();
      expect(_fillOf(tester, Glyphs2.nodes), 1);
      expect(_fillOf(tester, Glyphs2.agents), 0);

      await tester.pumpWidget(_dock(2));
      final seen = <double>{};
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(_fillOf(tester, Glyphs2.agents));
      }
      expect(
        seen.where((fill) => fill > 0 && fill < 1),
        isNotEmpty,
        reason: 'the fill grows over frames instead of switching',
      );
      await tester.pumpAndSettle();
      expect(_fillOf(tester, Glyphs2.agents), 1);
      expect(_fillOf(tester, Glyphs2.nodes), 0);
      expect(_fillOf(tester, Glyphs2.grid), 0);
    },
  );

  testWidgets('with reduced motion a dock tab fills in one frame', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_dock(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_dock(3));
    await tester.pump();
    expect(_fillOf(tester, Glyphs2.sliders), 1);
    expect(_fillOf(tester, Glyphs2.nodes), 0);
  });

  testWidgets('a bar glyph morphs to filled and back', (tester) async {
    Widget glyph(bool filled, {bool reduceMotion = false}) => _bare(
      AnimatedGlyph(glyph: Glyphs2.agents, filled: filled),
      reduceMotion: reduceMotion,
    );
    await tester.pumpWidget(glyph(false));
    expect(_fillOf(tester, Glyphs2.agents), 0);

    await tester.pumpWidget(glyph(true));
    await tester.pump(const Duration(milliseconds: 120));
    final mid = _fillOf(tester, Glyphs2.agents);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
    await tester.pumpAndSettle();
    expect(_fillOf(tester, Glyphs2.agents), 1);

    await tester.pumpWidget(glyph(false, reduceMotion: true));
    await tester.pump();
    expect(_fillOf(tester, Glyphs2.agents), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets(
    'a live status dot breathes; an idle one and reduced motion hold',
    (tester) async {
      const tint = Color(0xFF3FB950);
      await tester.pumpWidget(_bare(const PulsingDot(color: tint)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(
        _bare(const PulsingDot(color: tint, pulse: true)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        _bare(const PulsingDot(color: tint, pulse: true), reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
    },
  );
}
