import 'dart:convert';
import 'dart:typed_data';

import '../herdr.dart';
import '../native/bridge.dart';

/// `?chat=<pane>&herdr=demo`: a herdr that answers from memory, so the chat
/// page can be reviewed (and recorded on an emulator) without a node running
/// herdr. Only the herdr calls answer.
class DemoHerdrBridge implements NativeBridge {
  DemoHerdrBridge({this.agentStatus = 'working', this.failModel = false});

  final String agentStatus;

  /// `?modelfail=1`: the agent refuses a model switch, for the error state.
  final bool failModel;

  String _model = 'claude-opus-4-1-20250805';
  String _effort = 'high';

  static const pane = 'w1:p1';

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
    switch (method) {
      case 'agent.list':
        return jsonEncode({
          'agents': [
            {
              'pane_id': pane,
              'agent': 'claude',
              'name': 'deck',
              'agent_status': agentStatus,
              'workspace_id': 'w1',
              'cwd': '/srv/taildeck-ui',
            },
          ],
        });
      case 'workspace.list':
        return '{"workspaces":[{"workspace_id":"w1","label":"taildeck-ui"}]}';
      case 'agent.prompt':
        final params = jsonDecode(paramsJSON) as Map<String, dynamic>;
        final text = params['text'] as String? ?? '';
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (text.startsWith('/model ') || text.startsWith('/effort ')) {
          if (failModel) {
            throw const BridgeException('agent.prompt: pane w1:p1 is busy');
          }
          final value = text.substring(text.indexOf(' ') + 1).trim();
          if (text.startsWith('/model ')) {
            // What Claude Code records once it runs the alias.
            _model = switch (value) {
              'opus' => 'claude-opus-4-1-20250805',
              'sonnet' => 'claude-sonnet-4-5-20250929',
              'haiku' => 'claude-haiku-4-5-20251001',
              _ => value,
            };
          } else {
            _effort = value;
          }
        }
        return '{}';
    }
    return '{}';
  }

  @override
  Future<String> herdrTranscript(String pane) async => jsonEncode({
    'settings': {'model': _model, 'effort': _effort},
    'context': {'used': 58400, 'window': 200000},
    'todos': [
      {'text': '读一遍 agent_chat.dart 的布局', 'status': 'completed'},
      {'text': '三层吸顶各自量高度', 'status': 'in_progress'},
      {'text': '键盘弹出时一起上移', 'status': 'pending'},
    ],
    'messages': _messages,
  });

  static const _messages = <Map<String, Object>>[
    {'role': 'user', 'text': '看一下 taildeck-ui 这个项目的结构，讲讲主要内容'},
    {'role': 'tool', 'name': 'Bash', 'input': 'ls lib/src'},
    {'role': 'tool', 'name': 'Read', 'input': 'lib/src/shell.dart'},
    {'role': 'tool', 'name': 'Read', 'input': 'lib/src/herdr.dart'},
    {
      'role': 'assistant',
      'text':
          '主要内容：\n'
          '1. lib/src/pages 是各个页面：节点、服务、Agents、设置和终端。\n'
          '2. lib/src/widgets 是公共组件：页头、分组卡片、选择行和加载状态。\n'
          '3. native/bridge 是 Go 写的 tsnet 节点，通过 FFI 接进来。\n'
          '4. third_party/prism_ui 是 vendored 的 UI 库，玻璃效果和动效都在这里。\n'
          '\n'
          '整体是一个 Shell 管四个 tab，二级页面用 BaseNavigator 推入；'
          'herdr 的会话通过 SSH 连到节点上读取。',
    },
    {'role': 'user', 'text': 'Agent 会话页的吸顶层是怎么叠的？'},
    {'role': 'tool', 'name': 'Grep', 'input': 'PageHeader lib/src/pages'},
    {
      'role': 'thinking',
      'text':
          'The header floats over the list; the composer sits below it in a '
          'Column, so the list is clipped at its top edge.',
    },
    {
      'role': 'assistant',
      'text':
          '会话页有三层固定在屏幕上：\n'
          '- 顶栏：返回、标题、状态和模型。\n'
          '- 运行中的任务条：当前工具、停止按钮和子任务数。\n'
          '- 输入框：草稿、排队和命令提示。\n'
          '\n'
          '正文应该从这三层下面滚过去，而不是在输入框上沿被切掉。'
          '键盘弹出时任务条和输入框一起上移，最后一条消息仍然能滚到。',
    },
    {
      'role': 'user',
      'text': 'Fix it, and keep the body readable under the bars in dark mode.',
    },
    {'role': 'tool', 'name': 'Edit', 'input': 'lib/src/pages/agent_chat.dart'},
    {
      'role': 'assistant',
      'text':
          'The list now runs the full height of the page. Its top and bottom '
          'padding equal the measured header and dock, and both layers draw '
          'the page colour with a soft edge, so a line scrolls under them '
          'instead of being cut.',
    },
    {'role': 'user', 'text': '再跑一下 analyze 和 golden'},
    {
      'role': 'tool',
      'name': 'Bash',
      'input': 'tool/golden.sh',
      'pending': true,
    },
  ];

  @override
  Future<bool> herdrTranscriptMore(String pane) async => false;

  @override
  Future<String> herdrRestart(String pane, {String thenPrompt = ''}) async =>
      'deck';

  /// What herdr's ModelOptions reports for claude (native/bridge/agentops.go).
  @override
  Future<String> herdrModels(String kind, String pane) async => jsonEncode({
    'models': [
      {'id': 'fable', 'name': 'Fable'},
      {'id': 'opus', 'name': 'Opus'},
      {'id': 'sonnet', 'name': 'Sonnet'},
      {'id': 'haiku', 'name': 'Haiku'},
    ],
    'efforts': ['low', 'medium', 'high', 'xhigh', 'max', 'auto'],
    'custom': false,
  });

  @override
  Future<String> herdrCommands(String kind, String cwd) async => '[]';

  @override
  Future<Uint8List> herdrImage(String ref) async => Uint8List(0);

  @override
  Future<String> herdrUpload(String name, Uint8List data) async => '';

  @override
  Future<String> herdrSubagent(String pane, String callId) async => '{}';

  @override
  Future<void> herdrClose() async {}

  @override
  Stream<BridgeEvent> get events => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('the demo herdr only answers herdr calls');
}

/// A herdr connected to [DemoHerdrBridge].
HerdrController demoHerdr({String status = 'working', bool failModel = false}) {
  final herdr = HerdrController(
    DemoHerdrBridge(agentStatus: status, failModel: failModel),
  );
  herdr.connect(node: 'devbox');
  return herdr;
}
