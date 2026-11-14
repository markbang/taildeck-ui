import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'native/bridge.dart';

enum HerdrStatus {
  working,
  blocked,
  done,
  idle,
  unknown;

  static HerdrStatus of(String value) => switch (value) {
    'working' => working,
    'blocked' => blocked,
    'done' => done,
    'idle' => idle,
    _ => unknown,
  };

  bool get settled => this == done || this == idle;
}

enum HerdrLink {
  /// No native backend (web or the shared library is missing).
  unavailable,
  idle,
  connecting,
  ready,
  notInstalled,
  notRunning,
  failed,
}

/// One agent pane as herdr reports it.
class HerdrAgent {
  const HerdrAgent({
    required this.paneId,
    required this.kind,
    required this.label,
    required this.status,
    required this.workspace,
    this.name = '',
    this.title = '',
    this.cwd = '',
    this.focused = false,
  });

  final String paneId;
  final String kind;
  final String label;
  final HerdrStatus status;
  final String workspace;
  final String name;
  final String title;
  final String cwd;
  final bool focused;

  static HerdrAgent? fromJson(
    Map<String, dynamic> json,
    Map<String, String> workspaces,
  ) {
    final pane = json['pane_id'] as String? ?? '';
    if (pane.isEmpty) return null;
    final kind = (json['agent'] as String?)?.isNotEmpty == true
        ? json['agent'] as String
        : 'agent';
    final name = json['name'] as String? ?? '';
    final display = json['display_agent'] as String? ?? '';
    final workspaceId = json['workspace_id'] as String? ?? '';
    String pick(String key) => json[key] as String? ?? '';
    return HerdrAgent(
      paneId: pane,
      kind: kind,
      label: name.isNotEmpty ? name : (display.isNotEmpty ? display : kind),
      status: HerdrStatus.of(json['agent_status'] as String? ?? ''),
      workspace: workspaces[workspaceId] ?? workspaceId,
      name: name,
      title: pick('terminal_title_stripped').isNotEmpty
          ? pick('terminal_title_stripped')
          : pick('title'),
      cwd: pick('foreground_cwd').isNotEmpty
          ? pick('foreground_cwd')
          : pick('cwd'),
      focused: json['focused'] == true,
    );
  }
}

/// A prompt the page queues while the agent is busy.
class HerdrMessage {
  const HerdrMessage({
    required this.role,
    this.text = '',
    this.name = '',
    this.summary = '',
    this.output = '',
    this.error = false,
    this.pending = false,
    this.kind = '',
    this.call = '',
    this.images = const [],
    this.queued = false,
    this.background = false,
  });

  final String role;
  final String text;
  final String name;
  final String summary;

  /// Tool output, when the agent recorded one.
  final String output;
  final bool error;
  final bool pending;
  final String kind;

  /// The agent's own tool call id; a `task` call names a subagent transcript.
  final String call;

  /// `img:<id>` refs (see [HerdrController.image]) or file paths on the node.
  final List<String> images;

  /// The agent took this prompt while it was working.
  final bool queued;
  final bool background;

  bool get isTool => role == 'tool' || kind.isNotEmpty && text.isEmpty;

  /// A subagent call: its own transcript can be read from the pane's session.
  bool get isSubagent => kind == 'task' && call.isNotEmpty;
}

/// The conversation herdr can read for a pane: a parsed session file, or the
/// pane's screen text when the agent keeps no readable session.
class HerdrTranscript {
  const HerdrTranscript({
    this.screenMode = false,
    this.screen = '',
    this.messages = const [],
    this.truncated = false,
    this.model = '',
    this.effort = '',
    this.contextUsed = 0,
    this.contextWindow = 0,
  });

  final bool screenMode;
  final String screen;
  final List<HerdrMessage> messages;
  final bool truncated;
  final String model;
  final String effort;
  final int contextUsed;
  final int contextWindow;

  bool get isEmpty => screenMode ? screen.trim().isEmpty : messages.isEmpty;

  static HerdrTranscript parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const HerdrTranscript();
    final context = decoded['context'];
    final settings = decoded['settings'];
    final messages = <HerdrMessage>[
      for (final item in decoded['messages'] as List? ?? const [])
        if (item is Map<String, dynamic>)
          HerdrMessage(
            role: item['role'] as String? ?? 'assistant',
            text: item['text'] as String? ?? item['output'] as String? ?? '',
            name: item['name'] as String? ?? '',
            summary: item['summary'] as String? ?? item['input'] as String? ?? '',
            output: item['output'] as String? ?? '',
            error: item['error'] == true,
            pending: item['pending'] == true,
            kind: item['kind'] as String? ?? '',
            call: item['call'] as String? ?? '',
            images: [
              for (final ref in item['images'] as List? ?? const [])
                if (ref is String && ref.isNotEmpty) ref,
            ],
            queued: item['queued'] == true,
            background: item['background'] == true,
          ),
    ];
    return HerdrTranscript(
      screenMode: decoded['mode'] == 'screen',
      screen: decoded['screen'] as String? ?? '',
      messages: messages,
      truncated: decoded['truncated'] == true,
      model: (settings is Map ? settings['model'] as String? : null) ??
          decoded['model'] as String? ??
          '',
      effort: (settings is Map ? settings['effort'] as String? : null) ?? '',
      contextUsed: context is Map ? (context['used'] as num?)?.toInt() ?? 0 : 0,
      contextWindow: context is Map
          ? (context['window'] as num?)?.toInt() ?? 0
          : 0,
    );
  }
}

/// A prompt command or skill the agent takes by typing.
class HerdrCommand {
  const HerdrCommand(this.name, this.description, this.source);

  final String name;
  final String description;

  /// `builtin`, `command`, `prompt` or `skill`.
  final String source;

  static List<HerdrCommand> listOf(String raw) {
    if (raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map && (item['name'] as String? ?? '').isNotEmpty)
          HerdrCommand(
            item['name'] as String,
            item['description'] as String? ?? '',
            item['source'] as String? ?? '',
          ),
    ];
  }
}

/// A subagent's own transcript, with who it was and whether it finished.
class HerdrSubagent {
  const HerdrSubagent({
    required this.transcript,
    this.type = '',
    this.description = '',
    this.finished = false,
  });

  final HerdrTranscript transcript;
  final String type;
  final String description;
  final bool finished;

  static HerdrSubagent parse(String raw) {
    final decoded = jsonDecode(raw);
    final agent = decoded is Map<String, dynamic> ? decoded['agent'] : null;
    return HerdrSubagent(
      transcript: HerdrTranscript.parse(raw),
      type: agent is Map ? agent['type'] as String? ?? '' : '',
      description: agent is Map ? agent['description'] as String? ?? '' : '',
      finished: agent is Map && agent['finished'] == true,
    );
  }
}

/// A prompt the phone holds until its agent stops working.
class QueuedPrompt {
  const QueuedPrompt(this.id, this.text);

  final int id;
  final String text;
}

class HerdrModel {
  const HerdrModel(this.id, this.name);

  final String id;
  final String name;
}

class HerdrModels {
  const HerdrModels({this.models = const [], this.custom = false});

  final List<HerdrModel> models;

  /// The agent accepts model ids that are not listed.
  final bool custom;
}

class CreatedAgent {
  const CreatedAgent(this.paneId, {this.promptError = ''});

  final String paneId;
  final String promptError;
}

/// Owns the herdr connection: link state, the agent list and pane calls.
/// The Go side re-reads state on every event; this class does the same.
class HerdrController extends ChangeNotifier {
  HerdrController(this._bridge);

  final NativeBridge? _bridge;

  /// Called when a pane turns blocked or done; the backend decides whether the
  /// user has to be told.
  void Function(HerdrAgent agent)? onAttention;

  HerdrLink _link = HerdrLink.idle;
  String _detail = '';
  String _node = '';
  List<HerdrAgent> _agents = const [];
  int _connId = 0;
  bool _refreshing = false;
  Timer? _debounce;

  final Map<String, List<HerdrCommand>> _commands = {};
  final Map<String, DateTime> _commandsAt = {};
  final Map<String, Uint8List> _images = {};
  final Map<String, List<QueuedPrompt>> _queues = {};
  final Set<String> _flushing = {};
  int _queueSeq = 0;
  String _queueError = '';

  HerdrLink get link => _link;
  String get detail => _detail;
  String get node => _node;
  List<HerdrAgent> get agents => List.unmodifiable(_agents);
  bool get available => _bridge != null;
  bool get ready => _link == HerdrLink.ready;

  /// Why the last queued prompt could not be sent; empty once one lands.
  String get queueError => _queueError;

  /// Prompts held for [pane], oldest first.
  List<QueuedPrompt> queued(String pane) =>
      List.unmodifiable(_queues[pane] ?? const <QueuedPrompt>[]);

  Future<void> connect({
    required String node,
    int port = 22,
    String user = 'root',
    String password = '',
    String keyPath = '',
    String passphrase = '',
  }) async {
    final bridge = _bridge;
    if (bridge == null) {
      _link = HerdrLink.unavailable;
      notifyListeners();
      return;
    }
    _link = HerdrLink.connecting;
    _detail = '';
    _node = node;
    notifyListeners();
    try {
      final reply = await bridge.herdrConnect(
        host: node,
        port: port,
        user: user,
        password: password,
        keyPath: keyPath,
        passphrase: passphrase,
      );
      _connId = (reply['id'] as num?)?.toInt() ?? 0;
      _link = HerdrLink.ready;
      _detail = '';
      await refresh();
    } on Object catch (error) {
      _agents = const [];
      _detail = _message(error);
      _link = _classify(_detail);
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _debounce?.cancel();
    _connId = 0;
    _link = HerdrLink.idle;
    _agents = const [];
    _detail = '';
    _queues.clear();
    _flushing.clear();
    _queueError = '';
    _images.clear();
    _commands.clear();
    _commandsAt.clear();
    notifyListeners();
    await _bridge?.herdrClose();
  }

  /// Re-reads workspaces and agents; events only say that something moved.
  Future<void> refresh() async {
    final bridge = _bridge;
    if (bridge == null || _link != HerdrLink.ready || _refreshing) return;
    _refreshing = true;
    try {
      final workspaces = <String, String>{};
      try {
        final list = await _call(bridge, 'workspace.list', const {});
        for (final item in list['workspaces'] as List? ?? const []) {
          if (item is! Map) continue;
          final id = item['workspace_id'] as String? ?? '';
          final label = item['label'] as String? ?? '';
          if (id.isNotEmpty) workspaces[id] = label.isEmpty ? id : label;
        }
      } on BridgeException {
        // Workspace labels are a nicety; agent.list still succeeds.
      }
      final reply = await _call(bridge, 'agent.list', const {});
      final before = {for (final agent in _agents) agent.paneId: agent.status};
      _agents = [
        for (final item in reply['agents'] as List? ?? const [])
          if (item is Map<String, dynamic>)
            ?HerdrAgent.fromJson(item, workspaces),
      ]..sort((a, b) => a.workspace.compareTo(b.workspace));
      _detail = '';
      notifyListeners();
      for (final agent in _agents) {
        final was = before[agent.paneId];
        final needsYou =
            agent.status == HerdrStatus.blocked ||
            agent.status == HerdrStatus.done;
        if (needsYou && was != null && was != agent.status) {
          onAttention?.call(agent);
        }
        if (agent.status.settled && queued(agent.paneId).isNotEmpty) {
          unawaited(_flush(agent.paneId));
        }
      }
    } on Object catch (error) {
      _detail = _message(error);
      if (_link == HerdrLink.ready && _detail.contains('not connected')) {
        _connId = 0;
        _link = HerdrLink.idle;
      }
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  /// herdr only signals; re-read after a short quiet period so a burst of
  /// streaming updates costs one list request.
  void onEvent(BridgeEvent event) {
    if (_connId == 0 || (event.herdrId != 0 && event.herdrId != _connId)) return;
    switch (event.event) {
      case 'changed':
        _debounce?.cancel();
        _debounce = Timer(
          const Duration(milliseconds: 200),
          () => unawaited(refresh()),
        );
      case 'closed':
        _debounce?.cancel();
        _connId = 0;
        _agents = const [];
        _link = HerdrLink.idle;
        _detail = event.reason;
        notifyListeners();
    }
  }

  Future<HerdrTranscript> transcript(String pane) async {
    final bridge = _need();
    return HerdrTranscript.parse(await bridge.herdrTranscript(pane));
  }

  /// Reads further back; true when the next [transcript] call shows more.
  Future<bool> transcriptMore(String pane) => _need().herdrTranscriptMore(pane);

  Future<void> prompt(String pane, String text) async {
    final bridge = _need();
    await _call(bridge, 'agent.prompt', {'target': pane, 'text': text});
  }

  Future<String> restart(String pane, {String prompt = ''}) =>
      _need().herdrRestart(pane, thenPrompt: prompt);

  Future<HerdrModels> models(String kind, String pane) async {
    final bridge = _need();
    final raw = jsonDecode(await bridge.herdrModels(kind, pane));
    if (raw is! Map<String, dynamic>) return const HerdrModels();
    return HerdrModels(
      custom: raw['custom'] == true,
      models: [
        for (final item in raw['models'] as List? ?? const [])
          if (item is Map)
            HerdrModel(
              item['id'] as String? ?? '',
              item['name'] as String? ?? item['id'] as String? ?? '',
            ),
      ],
    );
  }

  /// Switches the agent's model by sending its own `/model` command.
  Future<void> setModel(String pane, String model) =>
      prompt(pane, '/model $model');

  /// Commands herdr reads from the node, cached for a minute per kind + cwd.
  Future<List<HerdrCommand>> commands(String kind, String cwd) async {
    final key = '$kind|$cwd';
    final at = _commandsAt[key];
    final cached = _commands[key];
    if (at != null &&
        cached != null &&
        DateTime.now().difference(at) < const Duration(minutes: 1)) {
      return cached;
    }
    final list = HerdrCommand.listOf(await _need().herdrCommands(kind, cwd));
    _commands[key] = list;
    _commandsAt[key] = DateTime.now();
    return list;
  }

  /// Image bytes for a transcript ref; the last few refs stay in memory.
  Future<Uint8List> image(String ref) async {
    final cached = _images[ref];
    if (cached != null) return cached;
    final bytes = await _need().herdrImage(ref);
    if (_images.length >= 24) _images.remove(_images.keys.first);
    _images[ref] = bytes;
    return bytes;
  }

  /// Copies a picked or dropped file to the node; the prompt references the
  /// returned path.
  Future<String> upload(String name, Uint8List data) =>
      _need().herdrUpload(name, data);

  Future<HerdrSubagent> subagent(String pane, String callId) async =>
      HerdrSubagent.parse(await _need().herdrSubagent(pane, callId));

  /// Holds [text] until [pane]'s agent settles. Sends right away when it
  /// already has.
  void enqueue(String pane, String text) {
    final list = [...?_queues[pane], QueuedPrompt(++_queueSeq, text)];
    _queues[pane] = list;
    _queueError = '';
    notifyListeners();
    if (_statusOf(pane)?.settled == true) unawaited(_flush(pane));
  }

  QueuedPrompt? dequeue(String pane, int id) {
    final list = _queues[pane] ?? const <QueuedPrompt>[];
    final found = list.where((item) => item.id == id).firstOrNull;
    if (found == null) return null;
    final left = list.where((item) => item.id != id).toList();
    if (left.isEmpty) {
      _queues.remove(pane);
    } else {
      _queues[pane] = left;
    }
    notifyListeners();
    return found;
  }

  /// One prompt per settle: the agent starts working again, the next waits.
  Future<void> _flush(String pane) async {
    if (_link != HerdrLink.ready || !_flushing.add(pane)) return;
    try {
      final next = queued(pane).firstOrNull;
      if (next == null) return;
      await prompt(pane, next.text);
      dequeue(pane, next.id);
      _queueError = '';
    } on Object catch (error) {
      _queueError = _message(error);
    } finally {
      _flushing.remove(pane);
      notifyListeners();
    }
  }

  HerdrStatus? _statusOf(String pane) {
    for (final agent in _agents) {
      if (agent.paneId == pane) return agent.status;
    }
    return null;
  }

  Future<List<({String id, String label})>> workspaces() async {
    final bridge = _need();
    final reply = await _call(bridge, 'workspace.list', const {});
    return [
      for (final item in reply['workspaces'] as List? ?? const [])
        if (item is Map && (item['workspace_id'] as String? ?? '').isNotEmpty)
          (
            id: item['workspace_id'] as String,
            label: (item['label'] as String? ?? '').isNotEmpty
                ? item['label'] as String
                : item['workspace_id'] as String,
          ),
    ];
  }

  /// Opens a tab (or a workspace) and starts [kind] in it. A non-empty
  /// [prompt] is sent once the agent accepts it.
  Future<CreatedAgent> createAgent({
    required String kind,
    required String name,
    required String workspaceId,
    String cwd = '',
    String prompt = '',
  }) async {
    final bridge = _need();
    final params = <String, dynamic>{'label': name};
    if (cwd.trim().isNotEmpty) params['cwd'] = cwd.trim();
    final created = workspaceId.isEmpty
        ? await _call(bridge, 'workspace.create', params)
        : await _call(bridge, 'tab.create', {
            ...params,
            'workspace_id': workspaceId,
          });
    final pane = created['root_pane'] is Map
        ? (created['root_pane'] as Map)['pane_id'] as String? ?? ''
        : '';
    if (pane.isEmpty) {
      throw const BridgeException('herdr returned no pane for the new agent');
    }
    try {
      await _call(bridge, 'agent.start', {
        'name': name,
        'kind': kind,
        'pane_id': pane,
      });
    } on Object {
      try {
        await _call(bridge, 'pane.close', {'pane_id': pane});
      } on Object {
        // The empty tab is left behind if herdr refuses to close it.
      }
      rethrow;
    }
    var promptError = '';
    if (prompt.trim().isNotEmpty) {
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          // herdr settles launch readiness when the agent is read.
          await _call(bridge, 'agent.get', {'target': pane});
          await _call(bridge, 'agent.prompt', {
            'target': pane,
            'text': prompt.trim(),
          });
          promptError = '';
          break;
        } on Object catch (error) {
          promptError = _message(error);
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
    await refresh();
    return CreatedAgent(pane, promptError: promptError);
  }

  NativeBridge _need() {
    final bridge = _bridge;
    if (bridge == null) {
      throw const BridgeException('native backend is unavailable');
    }
    if (_link != HerdrLink.ready) {
      throw const BridgeException('herdr is not connected');
    }
    return bridge;
  }

  Future<Map<String, dynamic>> _call(
    NativeBridge bridge,
    String method,
    Map<String, dynamic> params,
  ) async {
    final raw = await bridge.herdrCall(method, jsonEncode(params));
    if (raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  static String _message(Object error) =>
      error is BridgeException ? error.message : '$error';

  static HerdrLink _classify(String message) {
    if (message.startsWith('HERDR_NOT_INSTALLED')) {
      return HerdrLink.notInstalled;
    }
    if (message.startsWith('HERDR_NOT_RUNNING')) return HerdrLink.notRunning;
    return HerdrLink.failed;
  }

  @override
  void dispose() {
    // The Go side closes the socket on td_stop / td_logout; closing it from
    // here would race the event callback teardown.
    _debounce?.cancel();
    super.dispose();
  }
}
