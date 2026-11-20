import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/demo/demo_herdr.dart';
import 'package:taildeck_ui/src/herdr.dart';
import 'package:taildeck_ui/src/pages/agent_chat.dart';
import 'package:taildeck_ui/src/pages/agent_steps.dart';
import 'package:taildeck_ui/src/pages/agent_stream.dart';

import 'golden/golden_harness.dart';

/// A herdr whose session file grows when the test says so.
class _Feed extends DemoHerdrBridge {
  _Feed({super.agentStatus});

  final messages = <Map<String, Object>>[];
  int reads = 0;

  @override
  Future<String> herdrTranscript(String pane) async {
    reads++;
    return jsonEncode({'messages': messages});
  }
}

String _reply(String first, String last) =>
    '$first ${List.filled(150, 'word').join(' ')} $last';

List<Map<String, Object>> _history(int turns) => [
  for (var i = 0; i < turns; i++) ...[
    {'id': 'u$i', 'role': 'user', 'text': 'question $i'},
    {'id': 'a$i', 'role': 'assistant', 'text': 'answer $i\n\nsecond line'},
  ],
];

Future<_Feed> _open(
  WidgetTester tester, {
  String status = 'working',
  List<Map<String, Object>> history = const [],
}) async {
  usePhone(tester);
  final feed = _Feed(agentStatus: status)..messages.addAll(history);
  final herdr = HerdrController(feed);
  await herdr.connect(node: 'devbox');
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pumpWidget(
    goldenApp(
      home: AgentChatPage(agent: herdr.agents.first, herdr: herdr),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  return feed;
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Finder _text(String text) => find.textContaining(text, findRichText: true);

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// One poll, then frames for the reveal.
Future<void> _poll(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

Future<void> _frames(WidgetTester tester, Duration total) async {
  for (
    var t = Duration.zero;
    t < total;
    t += const Duration(milliseconds: 16)
  ) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  settledMarkdownTests();

  testWidgets('a working pane is re-read every 400 ms, a quiet one every 4 s', (
    tester,
  ) async {
    final working = await _open(tester);
    final before = working.reads;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 10));
    expect(working.reads - before, inInclusiveRange(4, 6));
    await _close(tester);

    final idle = await _open(tester, status: 'idle');
    final idleBefore = idle.reads;
    await tester.pump(const Duration(seconds: 2));
    expect(idle.reads, idleBefore);
    await tester.pump(const Duration(seconds: 3));
    expect(idle.reads, idleBefore + 1);
    await _close(tester);
  });

  testWidgets('a reply that arrives is typed out, not dropped in whole', (
    tester,
  ) async {
    final feed = await _open(tester, history: _history(1));
    feed.messages.add({
      'id': 'r1',
      'role': 'assistant',
      'text': _reply('alpha', 'omega'),
    });
    await _poll(tester);
    await _frames(tester, const Duration(milliseconds: 200));
    expect(_text('alpha'), findsOneWidget);
    expect(_text('omega'), findsNothing);

    // The same message written further: the reveal goes on from where it is.
    feed.messages.last = {
      'id': 'r1',
      'role': 'assistant',
      'text': '${_reply('alpha', 'omega')} tail',
    };
    await _poll(tester);
    expect(_text('alpha'), findsOneWidget);
    expect(_text('tail'), findsNothing);
    await _frames(tester, const Duration(milliseconds: 1400));
    expect(_text('omega tail'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('what the page opens with shows whole', (tester) async {
    await _open(
      tester,
      history: [
        {'id': 'u1', 'role': 'user', 'text': 'go'},
        {'id': 'r1', 'role': 'assistant', 'text': _reply('alpha', 'omega')},
      ],
    );
    expect(_text('omega'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a read that appends keeps the widgets of the rows above', (
    tester,
  ) async {
    final feed = await _open(tester, history: _history(2));
    Widget row(String key) => tester.widget(find.byKey(ValueKey('msg-$key')));
    final user = row('user:u0');
    final answer = row('assistant:a1');
    feed.messages.add({'id': 'r9', 'role': 'assistant', 'text': 'new chunk'});
    await _poll(tester);
    await _frames(tester, const Duration(milliseconds: 600));
    expect(_text('new chunk'), findsOneWidget);
    expect(identical(row('user:u0'), user), isTrue);
    expect(identical(row('assistant:a1'), answer), isTrue);
    await _close(tester);
  });

  testWidgets('the end stays in view while the reader is there', (
    tester,
  ) async {
    final feed = await _open(tester, history: _history(12));
    final position = _position(tester);
    expect(position.pixels, position.maxScrollExtent);
    final start = position.maxScrollExtent;
    feed.messages.add({
      'id': 'r1',
      'role': 'assistant',
      'text': _reply('alpha', 'omega'),
    });
    await _poll(tester);
    for (var i = 0; i < 6; i++) {
      await _frames(tester, const Duration(milliseconds: 200));
      expect(position.pixels, position.maxScrollExtent);
    }
    expect(position.maxScrollExtent, greaterThan(start + 100));
    await _close(tester);
  });

  testWidgets('a reader who scrolled up is not moved by new output', (
    tester,
  ) async {
    final feed = await _open(tester, history: _history(12));
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await _frames(tester, const Duration(seconds: 1));
    final position = _position(tester);
    final held = position.pixels;
    final start = position.maxScrollExtent;
    expect(held, lessThan(start - 200));
    feed.messages.add({
      'id': 'r1',
      'role': 'assistant',
      'text': _reply('alpha', 'omega'),
    });
    await _poll(tester);
    await _frames(tester, const Duration(milliseconds: 1500));
    expect(position.maxScrollExtent, greaterThan(start + 100));
    expect(position.pixels, held);
    await _close(tester);
  });

  testWidgets('a reply typed out inside a running fold is never clipped', (
    tester,
  ) async {
    final feed = await _open(
      tester,
      history: [
        {'id': 'u1', 'role': 'user', 'text': 'go'},
        {'id': 't1', 'role': 'tool', 'name': 'Read', 'summary': 'a.dart'},
        {'id': 't2', 'role': 'tool', 'name': 'Read', 'summary': 'b.dart'},
      ],
    );
    feed.messages.add({
      'id': 'r1',
      'role': 'assistant',
      'text': _reply('alpha', 'omega'),
    });
    await _poll(tester);
    await _frames(tester, const Duration(milliseconds: 1200));
    await tester.pump();
    final fold = tester.getRect(find.byType(StepsBlock));
    expect(
      fold.bottom,
      greaterThanOrEqualTo(tester.getRect(_text('omega')).bottom),
    );
    await _close(tester);
  });

  testWidgets('a working pane ends with a live caret, a quiet one does not', (
    tester,
  ) async {
    await _open(tester, history: _history(1));
    expect(find.byKey(const ValueKey('live-caret')), findsOneWidget);
    await _close(tester);
    await _open(tester, status: 'idle', history: _history(1));
    expect(find.byKey(const ValueKey('live-caret')), findsNothing);
    await _close(tester);
  });
}

void settledMarkdownTests() {
  test('a half-typed reply never ends in an open inline span', () {
    expect(settledMarkdown('The dial runs **'), 'The dial runs');
    expect(settledMarkdown('The dial runs **bef'), 'The dial runs');
    expect(settledMarkdown('runs **before** the'), 'runs **before** the');
    expect(settledMarkdown('2. [`'), '2.');
    expect(settledMarkdown('see [herdr.go](native/br'), 'see');
    expect(
      settledMarkdown('see [herdr.go](a.go) now'),
      'see [herdr.go](a.go) now',
    );
    expect(settledMarkdown('on *Runn'), 'on');
    expect(settledMarkdown('on *Running*.'), 'on *Running*.');
    expect(settledMarkdown('- [x] read'), '- [x] read');
    expect(settledMarkdown('* item'), '* item');
    expect(settledMarkdown('2 * 3'), '2 * 3');
    expect(settledMarkdown('**done**\nnext `co'), '**done**\nnext');
    expect(settledMarkdown('```go\nx := **p'), '```go\nx := **p');
  });
}
