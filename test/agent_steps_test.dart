import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/herdr.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/pages/agent_steps.dart';

const _user = HerdrMessage(role: 'user', text: 'fix the dial');
HerdrMessage _tool(String name, String summary, {bool pending = false}) =>
    HerdrMessage(
      role: 'tool',
      kind: 'shell',
      name: name,
      summary: summary,
      call: 'call-$summary',
      pending: pending,
    );
const _reply = HerdrMessage(role: 'assistant', text: 'Done.');

final _turn = [
  _user,
  const HerdrMessage(role: 'thinking', text: 'look first'),
  _tool('Bash', 'rg dial'),
  _tool('Read', 'herdr.go'),
  const HerdrMessage(role: 'assistant', text: 'Found it, fixing.'),
  _tool('Bash', 'go test'),
  _tool('Bash', 'flutter test'),
  _reply,
];

StepsFold _fold(List<HerdrMessage> messages, {required bool working}) =>
    chatRows(messages, working: working).whereType<StepsFold>().single;

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: const [Locale('en'), Locale('zh')],
  home: Scaffold(body: child),
);

Widget _item(HerdrMessage m) => SizedBox(
  height: 60,
  child: Text(m.isTool ? 'tool ${m.summary}' : 'text ${m.text}'),
);

Widget _list({
  required List<HerdrMessage> messages,
  required bool working,
  required StepsFoldMemory memory,
  ScrollController? controller,
  int before = 0,
}) => _app(
  ListView(
    controller: controller,
    children: [
      for (var i = 0; i < before; i++)
        SizedBox(height: 100, child: Text('filler $i')),
      for (final row in chatRows(messages, working: working))
        if (row is StepsFold)
          StepsBlock(
            key: ValueKey(row.key),
            fold: row,
            memory: memory,
            live: working,
            itemBuilder: _item,
          )
        else if (row is HerdrMessage)
          _item(row),
      const SizedBox(height: 80, child: Text('marker')),
      for (var i = 0; i < 12; i++)
        SizedBox(height: 100, child: Text('after $i')),
    ],
  ),
);

void main() {
  test('a finished turn folds its work and leaves the reply below', () {
    final rows = chatRows(_turn, working: false);
    expect(rows.first, same(_user));
    final fold = rows[1] as StepsFold;
    expect(fold.running, isFalse);
    expect(fold.items.length, 6);
    expect(fold.tools.length, 4);
    expect(fold.dominantTool('tool'), 'Bash');
    expect(rows.last, same(_reply));
    expect(rows.length, 3);
  });

  test('the running turn folds everything, reply or not', () {
    final fold = _fold(_turn, working: true);
    expect(fold.running, isTrue);
    expect(fold.items.length, 7);
  });

  test('a turn with one call keeps the old rows', () {
    final rows = chatRows([_user, _tool('Read', 'a'), _reply], working: false);
    expect(rows.whereType<StepsFold>(), isEmpty);
    expect(rows[1], isA<List<HerdrMessage>>());
  });

  test('a fold keeps its key as the turn grows and ends', () {
    final running = _fold(_turn.sublist(0, 4), working: true);
    final done = _fold(_turn, working: false);
    expect(done.key, running.key);
  });

  testWidgets('a running turn opens by default, a finished one is closed', (
    tester,
  ) async {
    final memory = StepsFoldMemory();
    final live = [
      ..._turn.sublist(0, 6),
      _tool('Bash', 'flutter test', pending: true),
    ];
    await tester.pumpWidget(
      _list(messages: live, working: true, memory: memory),
    );
    expect(find.text('4 steps · Bash'), findsOneWidget);
    expect(find.text('tool rg dial'), findsOneWidget);
    expect(find.text('text Found it, fixing.'), findsOneWidget);

    await tester.pumpWidget(
      _list(messages: _turn, working: false, memory: memory),
    );
    await tester.pumpAndSettle();
    expect(find.text('4 steps · Bash'), findsOneWidget);
    expect(find.text('tool rg dial'), findsNothing);
  });

  testWidgets('a chosen state survives rebuilds and scrolling away', (
    tester,
  ) async {
    final memory = StepsFoldMemory();
    final controller = ScrollController();
    await tester.pumpWidget(
      _list(
        messages: _turn,
        working: false,
        memory: memory,
        controller: controller,
      ),
    );
    await tester.tap(find.text('4 steps · Bash'));
    await tester.pumpAndSettle();
    expect(find.text('tool rg dial'), findsOneWidget);

    // A reload builds new rows for the same turn.
    await tester.pumpWidget(
      _list(
        messages: [..._turn],
        working: false,
        memory: memory,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('tool rg dial'), findsOneWidget);

    // Far enough that the list drops the block, then back.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byType(StepsBlock), findsNothing);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('tool rg dial'), findsOneWidget);

    // A new session is a new page, and with it a new memory.
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pumpWidget(
      _list(messages: _turn, working: false, memory: StepsFoldMemory()),
    );
    await tester.pumpAndSettle();
    expect(find.text('tool rg dial'), findsNothing);
  });

  testWidgets('opening and closing keeps the header and the offset', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      _list(
        messages: _turn,
        working: false,
        memory: StepsFoldMemory(),
        controller: controller,
        before: 6,
      ),
    );
    controller.jumpTo(350);
    await tester.pump();
    final header = find.text('4 steps · Bash');
    final top = tester.getTopLeft(header).dy;
    for (var i = 0; i < 2; i++) {
      await tester.tap(header);
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, 350);
        expect(tester.getTopLeft(header).dy, top);
      }
      await tester.pumpAndSettle();
    }
    expect(find.text('tool rg dial'), findsNothing);
  });

  testWidgets('a fold closing above the viewport does not move the screen', (
    tester,
  ) async {
    final memory = StepsFoldMemory();
    final controller = ScrollController();
    await tester.pumpWidget(
      _list(
        messages: _turn,
        working: true,
        memory: memory,
        controller: controller,
        before: 4,
      ),
    );
    // The whole fold is above the top edge; its reply and the marker show.
    controller.jumpTo(850);
    await tester.pump();
    final marker = tester.getTopLeft(find.text('marker')).dy;
    expect(marker, greaterThan(0));

    await tester.pumpWidget(
      _list(
        messages: _turn,
        working: false,
        memory: memory,
        controller: controller,
        before: 4,
      ),
    );
    expect(tester.getTopLeft(find.text('marker')).dy, marker);
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getTopLeft(find.text('marker')).dy, marker);
    }
    expect(find.text('tool rg dial'), findsNothing);
  });
}
