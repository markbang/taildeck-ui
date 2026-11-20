@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/glyphs.dart';
import 'package:taildeck_ui/src/widgets/foundation.dart';

import 'golden_harness.dart';

const _sheet = <(String, Glyph)>[
  ('nodes', Glyphs2.nodes),
  ('grid', Glyphs2.grid),
  ('agents', Glyphs2.agents),
  ('sliders', Glyphs2.sliders),
  ('terminal', Glyphs2.terminal),
  ('globe', Glyphs2.globe),
  ('ping', Glyphs2.ping),
  ('radar', Glyphs2.radar),
  ('bolt', Glyphs2.bolt),
  ('relay', Glyphs2.relay),
  ('search', Glyphs2.search),
  ('plus', Glyphs2.plus),
  ('checklist', Glyphs2.checklist),
  ('sun', Glyphs2.sun),
  ('laptop', Glyphs2.laptop),
  ('monitor', Glyphs2.monitor),
  ('phone', Glyphs2.phone),
  ('key', Glyphs2.key),
  ('trash', Glyphs2.trash),
  ('refresh', Glyphs2.refresh),
  ('logout', Glyphs2.logout),
  ('schedule', Glyphs2.schedule),
  ('photo', Glyphs2.photo),
  ('bell', Glyphs2.bell),
  ('doc', Glyphs2.doc),
  ('keyboard', Glyphs2.keyboard),
  ('dpad', Glyphs2.dpad),
  ('compose', Glyphs2.compose),
  ('arrowUp', Glyphs2.arrowUp),
  ('arrowDown', Glyphs2.arrowDown),
];

Widget _cell(BuildContext context, String name, Glyph glyph) {
  final scheme = context.colorScheme;
  final caption = AppTextStyle.caption2
      .of(context)
      .copyWith(color: scheme.onSurfaceVariant);
  return SizedBox(
    width: 124,
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlyphIcon(glyph, size: 28, color: scheme.onSurface, fill: 0),
            const SizedBox(width: 10),
            GlyphIcon(glyph, size: 28, color: scheme.primary, fill: 1),
          ],
        ),
        const SizedBox(height: 4),
        Text(name, style: caption),
      ],
    ),
  );
}

Widget _page(ThemeMode mode) => goldenApp(
  themeMode: mode,
  home: Builder(
    builder: (context) => Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Wrap(
          runSpacing: 14,
          children: [
            for (final (name, glyph) in _sheet) _cell(context, name, glyph),
          ],
        ),
      ),
    ),
  ),
);

Widget _dock(ThemeMode mode, int selected) => goldenApp(
  themeMode: mode,
  home: Builder(
    builder: (context) => Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StatusPill(
                label: 'Working',
                tint: Color(0xFF3FB950),
                dot: true,
                pulse: true,
              ),
              SizedBox(width: 12),
              StatusPill(label: 'Idle', tint: Color(0xFF8B949E), dot: true),
            ],
          ),
          NavigationDock(
            destinations: [
              for (final (glyph, label) in const [
                (Glyphs2.nodes, 'Nodes'),
                (Glyphs2.grid, 'Services'),
                (Glyphs2.agents, 'Agents'),
                (Glyphs2.sliders, 'Settings'),
              ])
                NavigationDockDestination(glyph: glyph, label: label),
            ],
            selectedIndex: selected,
            onSelected: (_) {},
          ),
        ],
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    useGoldenComparator();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('every app glyph at rest and active (${mode.name})', (
      tester,
    ) async {
      usePhone(tester, size: const Size(404, 640));
      await tester.pumpWidget(_page(mode));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(PrismApp),
        matchesGoldenFile('goldens/glyphs_${mode.name}.png'),
      );
    });
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('a dock tab fills as the lens arrives (${mode.name})', (
      tester,
    ) async {
      usePhone(tester, size: const Size(414, 200));
      await tester.pumpWidget(_dock(mode, 0));
      await pumpFrames(tester, const Duration(milliseconds: 500));
      await tester.pumpWidget(_dock(mode, 2));
      await pumpFrames(tester, const Duration(milliseconds: 128));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(PrismApp),
        matchesGoldenFile('goldens/dock_moving_${mode.name}.png'),
      );
      await pumpFrames(tester, const Duration(milliseconds: 800));
      await expectLater(
        find.byType(PrismApp),
        matchesGoldenFile('goldens/dock_settled_${mode.name}.png'),
      );
    });
  }
}
