import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/demo/demo_herdr.dart';
import 'package:taildeck_ui/src/herdr.dart';
import 'package:taildeck_ui/src/pages/agent_chat.dart';
import 'package:taildeck_ui/src/widgets/header.dart';

import 'golden/golden_harness.dart';

const _toolbar = 72.0;

Future<HerdrController> _open(WidgetTester tester) async {
  usePhone(tester);
  final herdr = demoHerdr();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pumpWidget(
    goldenApp(
      home: AgentChatPage(agent: herdr.agents.first, herdr: herdr),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  return herdr;
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

EdgeInsets _listPadding(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).padding! as EdgeInsets;

Rect _foot(WidgetTester tester) => _rect(tester, find.byType(PageFooter));

Rect _header(WidgetTester tester) => _rect(tester, find.byType(PageHeader));

Rect _field(WidgetTester tester) => _rect(
  tester,
  find.descendant(
    of: find.byType(PageFooter),
    matching: find.byType(EditableText),
  ),
);

Rect _strip(WidgetTester tester) => _rect(tester, find.text('Stop').first);

void main() {
  testWidgets('three layers float over a list that runs the full page', (
    tester,
  ) async {
    await _open(tester);
    final header = _header(tester);
    final foot = _foot(tester);
    expect(header.top, 0);
    expect(header.height, statusBar + _toolbar);
    expect(foot.bottom, phoneSize.height - gestureBar);
    expect(_strip(tester).top, greaterThanOrEqualTo(foot.top));
    expect(_field(tester).bottom, lessThanOrEqualTo(foot.bottom));

    final list = _rect(tester, find.byType(ListView));
    expect(list.top, 0);
    expect(list.bottom, phoneSize.height - gestureBar);
    final padding = _listPadding(tester);
    expect(padding.top, header.bottom + 12);
    expect(padding.bottom, foot.height + 12);
    await _close(tester);
  });

  testWidgets('the list opens on its newest message, above the foot', (
    tester,
  ) async {
    await _open(tester);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, position.maxScrollExtent);
    expect(position.maxScrollExtent, greaterThan(0));
    final last = _rect(tester, find.text('Bash · tool/golden.sh').first);
    expect(last.bottom, lessThanOrEqualTo(_foot(tester).top));
    await _close(tester);
  });

  testWidgets('the keyboard lifts the strip and the composer together', (
    tester,
  ) async {
    await _open(tester);
    final strip = _strip(tester);
    final field = _field(tester);
    final foot = _foot(tester);

    // The engine reports padding as viewPadding less the insets.
    const keyboard = 320.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    tester.view.padding = const FakeViewPadding(top: statusBar);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The gesture area lies under the keyboard: the foot rises by the rest.
    const lift = keyboard - gestureBar;
    expect(_foot(tester).bottom, foot.bottom - lift);
    expect(_strip(tester).top, strip.top - lift);
    expect(_field(tester).top, field.top - lift);
    expect(_foot(tester).height, foot.height);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, position.maxScrollExtent);
    final last = _rect(tester, find.text('Bash · tool/golden.sh').first);
    expect(last.bottom, lessThanOrEqualTo(_foot(tester).top));

    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.padding = const FakeViewPadding(
      top: statusBar,
      bottom: gestureBar,
    );
    await tester.pump();
    expect(_foot(tester).bottom, foot.bottom);
    await _close(tester);
  });

  testWidgets('nothing opaque lies over the body between the layers', (
    tester,
  ) async {
    await _open(tester);
    final band = Rect.fromLTRB(
      0,
      _header(tester).bottom + 16,
      phoneSize.width,
      _foot(tester).top - 16,
    );
    final list = find.byType(ListView);
    final page = Offset.zero & phoneSize;
    final painted = <Rect>[];
    for (final element
        in find
            .byWidgetPredicate((w) => w is ColoredBox || w is DecoratedBox)
            .evaluate()) {
      if (find
          .descendant(of: list, matching: find.byWidget(element.widget))
          .evaluate()
          .isNotEmpty) {
        continue;
      }
      final box = element.renderObject! as RenderBox;
      if (!box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect == page || !rect.overlaps(band)) continue;
      painted.add(rect);
    }
    expect(painted, isEmpty);
    await _close(tester);
  });

  testWidgets('overscroll at either end leaves the layers in place', (
    tester,
  ) async {
    await _open(tester);
    final header = _header(tester);
    final foot = _foot(tester);
    final list = find.byType(ListView);
    Future<void> pull(Offset by) async {
      final gesture = await tester.startGesture(tester.getCenter(list));
      for (var step = 0; step < 12; step++) {
        await gesture.moveBy(by / 12);
        await tester.pump(const Duration(milliseconds: 16));
        expect(_header(tester), header);
        expect(_foot(tester), foot);
      }
      await gesture.up();
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_header(tester), header);
        expect(_foot(tester), foot);
      }
    }

    await pull(const Offset(0, -400));
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await pull(const Offset(0, 400));
    await _close(tester);
  });
}
