import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/demo/demo_herdr.dart';
import 'package:taildeck_ui/src/pages/agent_chat.dart';
import 'package:taildeck_ui/src/widgets/loading.dart';

import 'golden/golden_harness.dart';

final _capsule = find.byKey(const ValueKey('model-capsule'));

Future<void> _open(WidgetTester tester, {bool failModel = false}) async {
  usePhone(tester);
  final herdr = demoHerdr(failModel: failModel);
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
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Finder _inCapsule(Finder finder) =>
    find.descendant(of: _capsule, matching: finder);

Future<void> _pickSonnet(WidgetTester tester) async {
  await tester.tap(_capsule);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.text('Model and thinking'), findsOneWidget);
  expect(find.text('Fable'), findsOneWidget);
  expect(find.text('Thinking level'), findsOneWidget);
  expect(find.text('Restart agent'), findsOneWidget);
  await tester.tap(find.text('Sonnet'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the capsule names the session model', (tester) async {
    await _open(tester);
    expect(_inCapsule(find.text('Opus 4.1')), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a switch shows its progress, then the new model', (
    tester,
  ) async {
    await _open(tester);
    await _pickSonnet(tester);
    expect(_inCapsule(find.text('To Sonnet…')), findsOneWidget);
    expect(_inCapsule(find.byType(LoadingIndicator)), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Next turn uses Sonnet'), findsOneWidget);
    expect(_inCapsule(find.byType(LoadingIndicator)), findsNothing);
    expect(_inCapsule(find.text('Sonnet 4.5')), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a failed switch says so and keeps the model', (tester) async {
    await _open(tester, failModel: true);
    await _pickSonnet(tester);
    expect(_inCapsule(find.byType(LoadingIndicator)), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.textContaining('Couldn’t switch: agent.prompt: pane w1:p1 is busy'),
      findsOneWidget,
    );
    expect(_inCapsule(find.text('Opus 4.1')), findsOneWidget);
    expect(_inCapsule(find.byType(LoadingIndicator)), findsNothing);
    expect(
      tester.getSemantics(_capsule).getSemanticsData().value,
      'Switch failed',
    );
    await _close(tester);
  });

  testWidgets('a thinking level is its own switch', (tester) async {
    await _open(tester);
    await tester.tap(_capsule);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('max'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_inCapsule(find.text('To max…')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Next turn uses max'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a long press shows the session model', (tester) async {
    await _open(tester);
    await tester.longPress(_capsule);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('This session’s model'), findsOneWidget);
    expect(find.text('claude-opus-4-1-20250805'), findsOneWidget);
    expect(find.text('high'), findsOneWidget);
    expect(find.text('58k / 200k · 29%'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('restart stays reachable from the panel', (tester) async {
    await _open(tester);
    await tester.tap(_capsule);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Restart agent'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.text('Quits the agent and reopens the same session with its flags.'),
      findsOneWidget,
    );
    await _close(tester);
  });
}
