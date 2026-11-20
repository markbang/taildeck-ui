import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/herdr.dart';
import 'package:taildeck_ui/src/native/bridge.dart';
import 'package:taildeck_ui/src/pages/agent_chat.dart';

import 'golden/golden_harness.dart';

final _capsule = find.byKey(const ValueKey('model-capsule'));

/// One agent session as the Go bridge renders it.
class _Session {
  _Session(this.file, {this.model = '', this.effort = ''});

  final String file;
  String model;
  String effort;
  final messages = <Map<String, Object>>[];

  /// The agent answers a turn; [model] is what the turn ran on.
  void turn(String question, String answer, {String? model}) {
    final n = messages.length;
    messages
      ..add({'id': 'u$n', 'role': 'user', 'text': question})
      ..add({'id': 'a$n', 'role': 'assistant', 'text': answer});
    if (model != null) this.model = model;
  }

  String render() => jsonEncode({
    'mode': 'transcript',
    'file': file,
    'model': model,
    'settings': {'model': model, 'effort': effort},
    'messages': messages,
  });
}

/// A herdr node: one session per pane, tabs created on demand.
class _Node implements NativeBridge {
  final sessions = <String, _Session>{};

  /// The session a new agent reports; empty until it has worked.
  _Session Function(String pane) newSession = (pane) => _Session('');

  /// How the agent takes `/model`: recorded at once (Claude) or not until the
  /// next turn (Codex).
  bool recordsSwitch = true;
  final typed = <String>[];

  @override
  Future<Map<String, dynamic>> herdrConnect({
    required String host,
    int port = 22,
    String user = 'root',
    String password = '',
    String keyPath = '',
    String passphrase = '',
    String certPath = '',
  }) async => {'id': 1};

  @override
  Future<String> herdrCall(String method, [String paramsJSON = '{}']) async {
    final params = jsonDecode(paramsJSON) as Map<String, dynamic>;
    switch (method) {
      case 'agent.list':
        return jsonEncode({
          'agents': [
            for (final pane in sessions.keys)
              {
                'pane_id': pane,
                'agent': 'claude',
                'name': pane,
                'agent_status': 'idle',
                'workspace_id': 'w1',
                'cwd': '/srv/app',
              },
          ],
        });
      case 'tab.create':
        final pane = 'w1:p${sessions.length + 1}';
        sessions[pane] = newSession(pane);
        return jsonEncode({
          'root_pane': {'pane_id': pane},
        });
      case 'agent.prompt':
        final text = params['text'] as String;
        typed.add(text);
        final session = sessions[params['target']]!;
        if (recordsSwitch && text.startsWith('/model ')) {
          session.model = switch (text.substring(7)) {
            'sonnet' => 'claude-sonnet-4-5-20250929',
            final other => other,
          };
        }
        return '{}';
    }
    return '{}';
  }

  @override
  Future<String> herdrTranscript(String pane) async => sessions[pane]!.render();

  @override
  Future<bool> herdrTranscriptMore(String pane) async => false;

  @override
  Future<String> herdrModels(String kind, String pane) async => jsonEncode({
    'models': [
      {'id': 'opus', 'name': 'Opus'},
      {'id': 'sonnet', 'name': 'Sonnet'},
    ],
    'efforts': ['low', 'medium', 'high'],
  });

  @override
  Future<String> herdrCommands(String kind, String cwd) async => '[]';

  @override
  Future<Uint8List> herdrImage(String ref) async => Uint8List(0);

  @override
  Future<void> herdrClose() async {}

  @override
  Stream<BridgeEvent> get events => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

Future<HerdrController> _connect(WidgetTester tester, _Node node) async {
  final herdr = HerdrController(node);
  await herdr.connect(node: 'devbox');
  return herdr;
}

Future<void> _open(
  WidgetTester tester,
  HerdrController herdr,
  String pane,
) async {
  usePhone(tester);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  final agent = herdr.agents.firstWhere((a) => a.paneId == pane);
  await tester.pumpWidget(
    goldenApp(
      home: AgentChatPage(key: ValueKey(pane), agent: agent, herdr: herdr),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// herdr says the pane moved; the page re-reads it.
Future<void> _changed(WidgetTester tester, HerdrController herdr) async {
  await herdr.refresh();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pick(WidgetTester tester, String row) async {
  await tester.tap(_capsule);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text(row));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

String _capsuleLabel(WidgetTester tester) =>
    tester.getSemantics(_capsule).getSemanticsData().label;

void main() {
  testWidgets('a new session starts empty and names its own model', (
    tester,
  ) async {
    final node = _Node();
    node.sessions['w1:p1'] = _Session('/s/old.jsonl', effort: 'high')
      ..turn('old question', 'old answer', model: 'claude-opus-4-1-20250805');
    node.newSession = (pane) => _Session(
      '/s/$pane.jsonl',
      model: 'claude-sonnet-4-5-20250929',
      effort: 'low',
    );
    final herdr = await _connect(tester, node);

    await _open(tester, herdr, 'w1:p1');
    expect(find.text('old answer'), findsOneWidget);
    expect(_capsuleLabel(tester), 'Model: Opus 4.1, thinking high');
    await _close(tester);

    final created = await herdr.createAgent(
      kind: 'claude',
      name: 'second',
      workspaceId: 'w1',
    );
    expect(created.paneId, isNot('w1:p1'));
    await _open(tester, herdr, created.paneId);
    expect(find.text('No messages yet.'), findsOneWidget);
    expect(find.text('old answer'), findsNothing);
    expect(_capsuleLabel(tester), 'Model: Sonnet 4.5, thinking low');
    await _close(tester);

    await _open(tester, herdr, 'w1:p1');
    expect(find.text('old answer'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a switch shows on the capsule and in what the session reports', (
    tester,
  ) async {
    final node = _Node();
    node.sessions['w1:p1'] = _Session('/s/a.jsonl', effort: 'high')
      ..turn('q', 'a', model: 'claude-opus-4-1-20250805');
    final herdr = await _connect(tester, node);
    await _open(tester, herdr, 'w1:p1');

    await _pick(tester, 'Sonnet');
    expect(node.typed, ['/model sonnet']);
    final reported = await herdr.transcript('w1:p1');
    expect(reported.model, 'claude-sonnet-4-5-20250929');
    expect(_capsuleLabel(tester), startsWith('Model: Sonnet 4.5'));
    await _close(tester);
  });

  testWidgets('a pick holds until the next turn, which names the real model', (
    tester,
  ) async {
    final node = _Node()..recordsSwitch = false;
    final session = _Session('/s/a.jsonl', effort: 'high')
      ..turn('q', 'a', model: 'claude-opus-4-1-20250805');
    node.sessions['w1:p1'] = session;
    final herdr = await _connect(tester, node);
    await _open(tester, herdr, 'w1:p1');

    await _pick(tester, 'Sonnet');
    await _changed(tester, herdr);
    expect(_capsuleLabel(tester), startsWith('Model: Sonnet'));

    session.turn('q2', 'a2', model: 'claude-sonnet-4-5-20250929');
    await _changed(tester, herdr);
    expect(_capsuleLabel(tester), startsWith('Model: Sonnet 4.5'));
    await _close(tester);
  });

  testWidgets('a pick the agent ignored gives way to the model it ran on', (
    tester,
  ) async {
    final node = _Node()..recordsSwitch = false;
    final session = _Session('/s/a.jsonl', effort: 'high')
      ..turn('q', 'a', model: 'claude-opus-4-1-20250805');
    node.sessions['w1:p1'] = session;
    final herdr = await _connect(tester, node);
    await _open(tester, herdr, 'w1:p1');

    await _pick(tester, 'Sonnet');
    expect(_capsuleLabel(tester), startsWith('Model: Sonnet'));

    session.turn('q2', 'a2');
    await _changed(tester, herdr);
    expect(_capsuleLabel(tester), startsWith('Model: Opus 4.1'));
    await _close(tester);
  });
}
