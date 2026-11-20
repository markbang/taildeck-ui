import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
import '../herdr.dart';
import '../l10n.dart';
import '../markdown/markdown_view.dart';
import '../motion.dart';
import '../widgets/controls.dart';
import '../widgets/foundation.dart';
import '../widgets/header.dart';
import '../widgets/snackbar.dart';
import '../widgets/loading.dart';
import 'agent_chat_layers.dart';
import 'agent_command_output.dart';
import 'agent_model.dart';
import 'agent_steps.dart';
import 'agent_stream.dart';

/// The session state a model pick was made against.
typedef _ModelMark = ({ModelSettings settings, String file, String turn});

/// One agent pane: its transcript, a prompt box, restart and model switching.
class AgentChatPage extends StatefulWidget {
  const AgentChatPage({
    super.key,
    required this.agent,
    required this.herdr,
    this.demoQueue = const [],
  });

  final HerdrAgent agent;
  final HerdrController herdr;

  /// `?queue=` on the preview build: prompts that start out queued.
  final List<String> demoQueue;

  @override
  State<AgentChatPage> createState() => _AgentChatPageState();
}

class _AgentChatPageState extends State<AgentChatPage> {
  static const _maxSuggestions = 6;

  /// While the agent works the session file is re-read this often, so a reply
  /// shows within half a second of being written; a quiet pane every 4 s, as
  /// the Kotlin chat does.
  static const livePoll = Duration(milliseconds: 400);
  static const idlePoll = Duration(seconds: 4);

  /// A prompt just sent keeps the fast pace until herdr reports the agent busy.
  static const _sentGrace = Duration(seconds: 8);

  final _scroll = ChatScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  HerdrTranscript? _transcript;
  String _error = '';
  bool _loading = true;
  bool _sending = false;
  bool _restarting = false;
  bool _switchingModel = false;
  String _switchTarget = '';
  bool _switchFailed = false;
  _ModelMark? _pickedFrom;
  ModelSettings? _picked;
  Timer? _reload;
  Timer? _poll;
  bool _fetching = false;
  bool _again = false;
  bool _againMore = false;
  DateTime? _sentAt;
  bool _hidden = false;
  late final AppLifecycleListener _lifecycle;
  final _reveal = RevealMemory();
  Map<String, (Object, Widget)> _rowCache = const {};
  List<HerdrCommand> _commands = const [];
  List<HerdrCommand> _suggestions = const [];
  int _suggestion = 0;
  bool _loadingCommands = false;
  bool _commandsLoaded = false;
  bool _popup = false;
  bool _nearBottom = true;
  final _steps = StepsFoldMemory();
  double _dock = 0;
  double _keyboard = 0;

  String get _pane => widget.agent.paneId;

  HerdrAgent get _agent {
    for (final agent in widget.herdr.agents) {
      if (agent.paneId == _pane) return agent;
    }
    return widget.agent;
  }

  bool get _working => _agent.status == HerdrStatus.working;

  List<QueuedPrompt> get _queue => widget.herdr.queued(_pane);

  @override
  void initState() {
    super.initState();
    widget.herdr.addListener(_onHerdr);
    _input.addListener(_onDraft);
    _scroll.addListener(_onScroll);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    for (final text in widget.demoQueue) {
      widget.herdr.enqueue(_pane, text);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.herdr.removeListener(_onHerdr);
    _lifecycle.dispose();
    _reload?.cancel();
    _poll?.cancel();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// The scroll-to-bottom button shows whenever the transcript is not at its
  /// end, as in the Kotlin chat.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final near = position.maxScrollExtent - position.pixels < 120;
    if (near != _nearBottom) setState(() => _nearBottom = near);
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    if (context.disableAnimations) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      return;
    }
    unawaited(
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: motionDuration(context, slowSpatial),
        curve: slowSpatial.curve,
      ),
    );
  }

  /// herdr events say that the pane moved; re-read once the burst settles.
  void _onHerdr() {
    if (mounted) setState(() {});
    _reload?.cancel();
    _reload = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_load()),
    );
  }

  /// Finished actions report in a snackbar, as the Kotlin chat does.
  void _say(String text) {
    if (!mounted || text.isEmpty) return;
    showMotionSnack(context, text);
  }

  static String _message(Object error) =>
      error is Exception ? error.toString() : '$error';

  /// A hidden app reads nothing; coming back reads at once.
  void _onLifecycle(AppLifecycleState state) {
    final hidden =
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (hidden == _hidden) return;
    _hidden = hidden;
    if (hidden) {
      _poll?.cancel();
    } else {
      unawaited(_load());
    }
  }

  bool get _live {
    final sent = _sentAt;
    return _working ||
        sent != null && DateTime.now().difference(sent) < _sentGrace;
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!mounted || _hidden) return;
    _poll = Timer(_live ? livePoll : idlePoll, () => unawaited(_load()));
  }

  /// One read at a time: a call that lands mid-read runs once after it.
  Future<void> _load({bool more = false}) async {
    if (_fetching) {
      _again = true;
      _againMore |= more;
      return;
    }
    _fetching = true;
    _poll?.cancel();
    try {
      await _read(more: more);
    } finally {
      _fetching = false;
      if (mounted) {
        if (_again) {
          final again = _againMore;
          _again = false;
          _againMore = false;
          unawaited(_load(more: again));
        } else {
          _schedulePoll();
        }
      }
    }
  }

  Future<void> _read({required bool more}) async {
    try {
      if (more) await widget.herdr.transcriptMore(_pane);
      final transcript = await widget.herdr.transcript(_pane);
      if (!mounted) return;
      if (transcript == _transcript && _error.isEmpty) return;
      final first = _transcript == null;
      final fresh = [
        for (final message in transcript.messages)
          if (message.key.isNotEmpty && !_reveal.knows(message.key)) message,
      ];
      // The opening read, earlier history, or a session swapped underneath
      // shows as it is; only a reply arriving now is typed out.
      final replies = fresh.where((m) => m.role == 'assistant').toList();
      final typed = !first && !more && replies.length <= 2;
      _reveal.settle(fresh);
      if (typed) {
        for (final reply in replies) {
          _reveal.arrive(reply.key);
        }
      }
      if (!more && _nearBottom) _scroll.follow();
      setState(() {
        _transcript = transcript;
        _error = '';
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      final message = _message(error);
      final failure = HerdrFailure.of(message);
      setState(() {
        _error = failure == HerdrFailure.other
            ? message
            : AppLocalizations.of(context)
                  .herdrFailure(widget.herdr.node, failure);
        _loading = false;
      });
    }
  }

  /// A reply being typed out keeps the end in view while the reader is there.
  void _onReveal() {
    if (_nearBottom) _scroll.follow();
  }

  // ---- slash commands ----

  /// A leading `/word` with no whitespace asks for the command popup.
  void _onDraft() {
    final text = _input.text;
    final asking = text.startsWith('/') && !text.contains(RegExp(r'\s'));
    if (!asking) {
      if (!_popup) return;
      setState(() {
        _popup = false;
        _suggestions = const [];
      });
      return;
    }
    if (!_commandsLoaded) unawaited(_loadCommands());
    final query = text.substring(1).toLowerCase();
    final matches =
        [
          for (final command in _commands)
            if (command.name.toLowerCase().contains(query)) command,
        ]..sort((a, b) {
          final as = a.name.toLowerCase().startsWith(query) ? 0 : 1;
          final bs = b.name.toLowerCase().startsWith(query) ? 0 : 1;
          return as != bs ? as - bs : a.name.compareTo(b.name);
        });
    setState(() {
      _popup = true;
      _suggestion = 0;
      _suggestions = matches.take(_maxSuggestions).toList();
    });
  }

  /// herdr's own commands come from the node; the harness's built-ins are
  /// always there, so the popup works before the first list arrives.
  Future<void> _loadCommands() async {
    if (_loadingCommands) return;
    _loadingCommands = true;
    final builtin = builtinCommands(_agent.kind, AppLocalizations.of(context));
    var own = const <HerdrCommand>[];
    try {
      own = await widget.herdr.commands(_agent.kind, _agent.cwd);
    } on Object {
      // Built-ins still answer; the node list returns on the next pane.
    }
    if (!mounted) return;
    _loadingCommands = false;
    _commandsLoaded = true;
    setState(() {
      _commands = [
        ...builtin,
        ...own.where((o) => builtin.every((b) => b.name != o.name)),
      ];
    });
    _onDraft();
  }

  void _pickCommand(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    final command = _suggestions[index];
    final text = '/${command.name} ';
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _popup = false;
      _suggestions = const [];
      _suggestion = 0;
    });
    _inputFocus.requestFocus();
  }

  void _dismissCommands() {
    if (!_popup) return;
    setState(() {
      _popup = false;
      _suggestions = const [];
    });
  }

  void _moveSuggestion(int delta) {
    if (_suggestions.isEmpty) return;
    setState(() {
      _suggestion = (_suggestion + delta) % _suggestions.length;
      if (_suggestion < 0) _suggestion += _suggestions.length;
    });
  }

  // ---- sending and the local queue ----

  Future<void> _send() async {
    if (_input.text.trim().isEmpty || _sending) return;
    final text = _input.text.trim();
    if (_working) {
      // The agent would drop or merge this; the phone holds it instead.
      widget.herdr.enqueue(_pane, text);
      _clearDraft();
      return;
    }
    await _sendText(text);
  }

  void _clearDraft() {
    _input.clear();
    setState(() {
      _popup = false;
      _suggestions = const [];
    });
  }

  /// Long-press on send bypasses the queue, as the Kotlin composer's send
  /// button does, and fires the same long-press haptic.
  Future<void> _sendNow() async {
    if (_input.text.trim().isEmpty || _sending) return;
    unawaited(HapticFeedback.mediumImpact());
    await _sendText(_input.text.trim());
  }

  Future<void> _sendQueued(QueuedPrompt prompt) async {
    if (widget.herdr.dequeue(_pane, prompt.id) == null) return;
    await _sendText(prompt.text);
  }

  Future<void> _sendText(String text) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
    });
    try {
      await widget.herdr.prompt(_pane, text);
      _sentAt = DateTime.now();
      if (mounted) _clearDraft();
      await _load();
    } on Object catch (error) {
      if (mounted) {
        _say(l10n.agentActionFailed(_message(error)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _restart() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: AlertDialog(
        title: l10n.agentRestart,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.agentRestart),
          ),
        ],
        child: Text(l10n.agentRestartBody),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _restarting = true;
    });
    try {
      await widget.herdr.restart(_pane);
      if (!mounted) return;
      _say(l10n.agentRestarted);
      await _load();
    } on Object catch (error) {
      if (mounted) {
        _say(l10n.agentRestartFailed(_message(error)));
      }
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  ModelSettings get _recorded =>
      (model: _transcript?.model ?? '', effort: _transcript?.effort ?? '');

  _ModelMark get _mark => (
    settings: _recorded,
    file: _transcript?.file ?? '',
    turn: _transcript?.turn ?? '',
  );

  /// A model or level just picked shows until the session records anything
  /// new: a change of settings, another session, or a turn the agent worked,
  /// which says what the conversation really runs on.
  ModelSettings get _shownSettings {
    final picked = _picked;
    return picked != null && _pickedFrom == _mark ? picked : _recorded;
  }

  /// pi would take a command typed mid-turn as a steering message.
  bool get _modelBusy =>
      _agent.status == HerdrStatus.blocked ||
      _working && const {'pi', 'omp'}.contains(_agent.kind);

  Future<void> _openModelPanel() async {
    if (_switchingModel || _restarting) return;
    final kind = _agent.kind;
    final pick = await showModelPanel(
      context,
      options: canSwitchModel(kind)
          ? widget.herdr.models(kind, _pane)
          : Future.value(const HerdrModels()),
      kind: kind,
      current: _shownSettings,
      busy: _modelBusy,
    );
    if (pick == null || !mounted) return;
    if (pick.restart) {
      await _restart();
      return;
    }
    await _switch(pick);
  }

  Future<void> _switch(ModelPick pick) async {
    final l10n = AppLocalizations.of(context);
    final kind = _agent.kind;
    final from = _mark;
    final shown = _shownSettings;
    final model = pick.model;
    final target = model != null
        ? modelShortName(model)
        : effortLabel(l10n, pick.effort ?? '');
    setState(() {
      _switchingModel = true;
      _switchFailed = false;
      _switchTarget = target;
    });
    try {
      if (model != null) {
        await widget.herdr.switchModel(_pane, kind, model, effort: pick.effort);
      } else {
        await widget.herdr.switchEffort(_pane, kind, pick.effort ?? '');
      }
      if (!mounted) return;
      setState(() {
        _pickedFrom = from;
        _picked = (
          model: model ?? shown.model,
          effort: pick.effort ?? shown.effort,
        );
      });
      _say(l10n.agentModelSwitched(target));
      unawaited(_load());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _switchFailed = true);
      _say(l10n.agentModelSwitchFailed(_message(error)));
    } finally {
      if (mounted) setState(() => _switchingModel = false);
    }
  }

  void _openModelDetails() {
    unawaited(
      showModelDetails(
        context,
        kind: _agent.kind,
        pane: _pane,
        recorded: _recorded,
        shown: _shownSettings,
        contextUsed: _transcript?.contextUsed ?? 0,
        contextWindow: _transcript?.contextWindow ?? 0,
      ),
    );
  }

  void _openSubagent(HerdrMessage message) {
    unawaited(
      showExtend<void>(
        context,
        builder: (context) =>
            _SubagentView(pane: _pane, herdr: widget.herdr, task: message),
      ),
    );
  }

  void _openImage(Uint8List bytes) {
    unawaited(
      BaseNavigator.push<void>(context, _ImageViewerPage(bytes: bytes)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final agent = _agent;
    final (status, tint) = switch (agent.status) {
      HerdrStatus.working => (l10n.working, scheme.primary),
      HerdrStatus.blocked => (l10n.blocked, const Color(0xFFE3B341)),
      HerdrStatus.done => (l10n.done, const Color(0xFF3BB273)),
      HerdrStatus.idle => (l10n.idle, scheme.onSurfaceVariant),
      HerdrStatus.unknown => ('—', scheme.onSurfaceVariant),
    };
    // Three layers float over the transcript on one frost: the header, and
    // at the foot the task strip with the composer. The list runs the page's
    // full height under them, padded by their measured heights; the keyboard
    // lifts the foot as one piece.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard != _keyboard) {
      _keyboard = keyboard;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _logLayers();
      });
    }
    // The system bars take the page's colour: Flutter's default status bar
    // lays a 25% black band over the header, and its black navigation bar
    // sits under the composer.
    final page = SurfaceLevel.page.colorOf(scheme);
    final dark = scheme.brightness == Brightness.dark;
    final icons = dark ? Brightness.light : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: const Color(0x00000000),
        statusBarIconBrightness: icons,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: page,
        systemNavigationBarIconBrightness: icons,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: _page(context, l10n, agent, status, tint, page, keyboard),
    );
  }

  Widget _page(
    BuildContext context,
    AppLocalizations l10n,
    HerdrAgent agent,
    String status,
    Color tint,
    Color page,
    double keyboard,
  ) {
    return Surface(
      color: page,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _body(context, l10n),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: _dock + 12,
                child: Center(
                  child: MotionVisibility(
                    visible: !_nearBottom,
                    scaleFrom: 0.8,
                    child: _ScrollToBottom(onPressed: _toBottom),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizeReport(
                  onSize: _onDock,
                  child: PageFooter(child: _composer(context, l10n)),
                ),
              ),
              PositionedDirectional(
                start: 0,
                end: 0,
                top: 0,
                child: PageHeader(
                  frosted: true,
                  child: PageBar(
                    title: agent.label,
                    onBack: () => Navigator.of(context).maybePop(),
                    maxWidth: 760,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeThrough(
                          child: StatusPill(
                            key: ValueKey(status),
                            label: status,
                            tint: tint,
                            dot: true,
                            pulse:
                                _agent.status == HerdrStatus.working ||
                                _agent.status == HerdrStatus.blocked,
                          ),
                        ),
                        const SizedBox(width: 6),
                        ModelCapsule(
                          settings: _shownSettings,
                          restarting: _restarting,
                          switchingTo: _switchingModel ? _switchTarget : null,
                          failed: _switchFailed,
                          onTap: () => unawaited(_openModelPanel()),
                          onLongPress: _openModelDetails,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The foot layer's height pads the list; a reader at the end stays there
  /// as the strip or the queue grows.
  void _onDock(Size size) {
    if (!mounted || size.height == _dock) return;
    if (_nearBottom) _scroll.follow();
    setState(() => _dock = size.height);
    _logLayers();
  }

  void _logLayers() {
    final view = MediaQuery.sizeOf(context);
    final top = context.contentTopPadding;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final footTop = view.height - keyboard - _dock;
    debugPrint(
      'taildeck chat layers: header=0-${(top - 12).round()} '
      'foot=${footTop.round()}-${(footTop + _dock).round()} '
      'keyboard=${keyboard.round()} list-pad=${top.round()}/${(_dock + 12).round()} '
      'screen=${view.height.round()}',
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final scheme = context.colorScheme;
    if (_loading) {
      return const Center(child: LoadingIndicator(size: 20));
    }
    if (_error.isNotEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          context.contentTopPadding,
          20,
          _dock + 12,
        ),
        children: [InlineNotice(text: _error)],
      );
    }
    final transcript = _transcript;
    if (transcript == null) return const SizedBox.shrink();
    if (transcript.screenMode) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          context.contentTopPadding,
          20,
          _dock + 12,
        ),
        children: [
          Text(
            l10n.agentScreenMode,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Card(
            radius: AppCorner.lg,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                transcript.screen,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      fontFamily: 'DejaVuSansMono',
                      fontSize: 12,
                      height: 1.5,
                    ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        20,
        context.contentTopPadding,
        20,
        _dock + 12,
      ),
      children: [
        if (transcript.truncated) ...[
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => unawaited(_load(more: true)),
              child: Text(l10n.agentLoadEarlier),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.agentTruncated,
              textAlign: TextAlign.center,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
        if (transcript.messages.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
            child: Text(
              l10n.agentNoMessages,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ..._rows(transcript.messages),
        if (_working) const LiveCaret(key: ValueKey('live-caret')),
      ],
    );
  }

  /// The transcript's rows. A row whose messages did not change since the
  /// last read keeps its widget instance, so a poll that appends a message
  /// rebuilds that message alone, not every row above it.
  List<Widget> _rows(List<HerdrMessage> messages) {
    final working = _working;
    final previous = _rowCache;
    final next = <String, (Object, Widget)>{};
    Widget cached(String key, Object signature, Widget Function() build) {
      var unique = key;
      for (var n = 1; next.containsKey(unique); n++) {
        unique = '$key#$n';
      }
      final hit = previous[unique];
      final widget = hit != null && hit.$1 == signature ? hit.$2 : build();
      next[unique] = (signature, widget);
      return widget;
    }

    final rows = <Widget>[];
    var index = 0;
    for (final row in chatRows(messages, working: working)) {
      index++;
      if (row is StepsFold) {
        rows.add(
          cached(
            'steps-${row.key}',
            _RowSignature([row.running, working, ...row.items]),
            () => StepsBlock(
              key: ValueKey('steps-${row.key}'),
              fold: row,
              memory: _steps,
              live: working,
              itemBuilder: _messageBlock,
            ),
          ),
        );
      } else if (row is List<HerdrMessage>) {
        final key =
            'tools-${row.first.call.isNotEmpty ? row.first.call : row.first.name}';
        rows.add(
          cached(
            key,
            _RowSignature([working, ...row]),
            () => _ToolGroup(
              key: ValueKey(key),
              messages: row,
              herdr: widget.herdr,
              live: working,
              onOpenImage: _openImage,
              onOpenSubagent: _openSubagent,
            ),
          ),
        );
      } else {
        final message = row as HerdrMessage;
        final key = message.key.isNotEmpty ? message.key : 'row-$index';
        rows.add(cached('msg-$key', message, () => _messageBlock(message)));
      }
    }
    _rowCache = next;
    return rows;
  }

  Widget _messageBlock(HerdrMessage message) => _MessageBlock(
    key: message.key.isEmpty ? null : ValueKey('msg-${message.key}'),
    message: message,
    herdr: widget.herdr,
    reveal: _reveal,
    onReveal: _onReveal,
    onOpenImage: _openImage,
    onOpenSubagent: _openSubagent,
  );

  /// What the agent is doing right now: its newest running tool call.
  String _activity(AppLocalizations l10n) {
    final messages = _transcript?.messages ?? const <HerdrMessage>[];
    for (final message in messages.reversed) {
      if (message.role == 'user') break;
      if (message.isTool && message.pending) {
        final name = message.name.isNotEmpty ? message.name : l10n.agentTool;
        return message.summary.isEmpty ? name : '$name · ${message.summary}';
      }
    }
    return l10n.agentWorking;
  }

  /// The question a blocked agent is waiting on: its last spoken line.
  String _lastAgentText() {
    for (final message
        in (_transcript?.messages ?? const <HerdrMessage>[]).reversed) {
      if (message.isTool) continue;
      if (message.text.trim().isNotEmpty) return message.text.trim();
    }
    final screen = _transcript?.screen.trim() ?? '';
    if (screen.isEmpty) return '';
    final lines = screen.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return lines.skip(lines.length > 6 ? lines.length - 6 : 0).join('\n');
  }

  List<HerdrMessage> get _runningSubagents => [
    for (final message in _transcript?.messages ?? const <HerdrMessage>[])
      if (message.isSubagent && message.pending) message,
  ];

  Widget _composer(BuildContext context, AppLocalizations l10n) {
    final scheme = context.colorScheme;
    final queue = _queue;
    final popup = _popup;
    // Kotlin wraps the panel's column in animateContentSize(Motion.slow()), so
    // the bar, todo track and queue grow in and out without a jump.
    final composer = AnimatedContentSize(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_working)
            _WorkingBar(
              activity: _activity(l10n),
              subagents: _runningSubagents.length,
              onStop: () => unawaited(widget.herdr.sendKeys(_pane, ['esc'])),
              onSubagents: () {
                final running = _runningSubagents;
                if (running.isNotEmpty) _openSubagent(running.first);
              },
            ),
          if (_transcript?.todos case final todos?)
            if (todos.any((todo) => !todo.done)) _TodoTrack(todos: todos),
          if (widget.herdr.queueError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: InlineNotice(
                text: l10n.agentActionFailed(widget.herdr.queueError),
                tint: scheme.onSurfaceVariant,
              ),
            ),
          if (queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.agentQueuedCount(queue.length),
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  for (final prompt in queue)
                    _QueuedChip(
                      prompt: prompt,
                      onCancel: () => widget.herdr.dequeue(_pane, prompt.id),
                      onSendNow: () => unawaited(_sendQueued(prompt)),
                    ),
                ],
              ),
            ),
          if (popup)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: _CommandPopup(
                commands: _suggestions,
                selected: _suggestion,
                loading: !_commandsLoaded,
                onPick: _pickCommand,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) {
                      if (popup && _suggestions.isNotEmpty) {
                        _pickCommand(_suggestion);
                      } else {
                        unawaited(_send());
                      }
                    },
                    style: AppTextStyle.body.of(context),
                    decoration: InputDecoration(
                      hintText: _working
                          ? l10n.agentQueueHint
                          : l10n.agentPromptHint,
                      hintStyle: AppTextStyle.body
                          .of(context)
                          .copyWith(color: scheme.onSurfaceVariant),
                      filled: true,
                      fillColor: SurfaceLevel.block.colorOf(scheme),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onLongPress: _working ? () => unawaited(_sendNow()) : null,
                  child: IconButton(
                    onPressed: _sending ? null : () => unawaited(_send()),
                    icon: _sending
                        ? const LoadingIndicator(size: 18)
                        : GlyphIcon(
                            _working ? Glyphs2.schedule : Glyphs2.arrowUp,
                          ),
                    tooltip: _working ? l10n.agentQueued : l10n.agentSend,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // A blocked agent takes the composer away and slides its prompt panel in
    // from a third of the height (Kotlin's `AnimatedContent(blocked)`).
    final blocked = _agent.status == HerdrStatus.blocked;
    final panel = SlideFadeSwitcher(
      slide: 1 / 3,
      alignment: Alignment.bottomCenter,
      child: blocked
          ? KeyedSubtree(
              key: const ValueKey('blocked'),
              child: _BlockedPanel(
                question: _lastAgentText(),
                screen: _transcript?.screen ?? '',
                onKeys: (keys) => unawaited(widget.herdr.sendKeys(_pane, keys)),
              ),
            )
          : KeyedSubtree(key: const ValueKey('composer'), child: composer),
    );
    // The wrapper stays in place so the input keeps its focus and text
    // connection; only the popup's keys are bound, and only while it is up.
    return CallbackShortcuts(
      bindings: popup && !blocked
          ? {
              const SingleActivator(LogicalKeyboardKey.escape):
                  _dismissCommands,
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _moveSuggestion(-1),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _moveSuggestion(1),
            }
          : const {},
      child: panel,
    );
  }
}

/// Commands matching the draft, above the input: name, description, skill tag.
class _CommandPopup extends StatelessWidget {
  const _CommandPopup({
    required this.commands,
    required this.selected,
    required this.loading,
    required this.onPick,
  });

  final List<HerdrCommand> commands;
  final int selected;
  final bool loading;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return Semantics(
      container: true,
      label: l10n.agentCommandsHint,
      child: Card(
        radius: AppCorner.lg,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (commands.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: loading
                    ? const LoadingIndicator(size: 16)
                    : Text(
                        l10n.agentCommandsEmpty,
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
              ),
            for (var i = 0; i < commands.length; i++)
              RowSemantics(
                label: l10n.agentCommandLabel(
                  commands[i].name,
                  commands[i].description,
                ),
                onTap: () => onPick(i),
                child: TapFeedback(
                  onTap: () => onPick(i),
                  child: Container(
                    color: i == selected
                        ? scheme.primary.withValues(alpha: 0.10)
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '/${commands[i].name}',
                          style: AppTextStyle.footnote
                              .of(context)
                              .copyWith(
                                fontFamily: 'DejaVuSansMono',
                                fontSize: 13,
                              ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            commands[i].description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        if (commands[i].source == 'skill')
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              l10n.agentCommandSkill,
                              style: AppTextStyle.caption2
                                  .of(context)
                                  .copyWith(color: scheme.primary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A prompt the phone holds while the agent works, with cancel and send now.
class _QueuedChip extends StatelessWidget {
  const _QueuedChip({
    required this.prompt,
    required this.onCancel,
    required this.onSendNow,
  });

  final QueuedPrompt prompt;
  final VoidCallback onCancel;
  final VoidCallback onSendNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
        decoration: ShapeDecoration(
          color: SurfaceLevel.block.colorOf(scheme),
          shape: AppShape.all(AppCorner.md),
        ),
        child: Row(
          children: [
            GlyphIcon(
              Glyphs2.schedule,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                prompt.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote.of(context),
              ),
            ),
            IconButton(
              onPressed: onSendNow,
              icon: const GlyphIcon(Glyphs2.arrowUp, size: 16),
              tooltip: l10n.agentQueueSendNow,
            ),
            IconButton(
              onPressed: onCancel,
              icon: const GlyphIcon(Glyphs.close, size: 15),
              tooltip: l10n.agentQueueCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// What a transcript row was built from; equal signatures reuse the widget.
class _RowSignature {
  const _RowSignature(this.parts);

  final List<Object> parts;

  @override
  bool operator ==(Object other) =>
      other is _RowSignature && listEquals(other.parts, parts);

  @override
  int get hashCode => Object.hashAll(parts);
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    super.key,
    required this.message,
    required this.herdr,
    required this.onOpenImage,
    required this.onOpenSubagent,
    this.reveal,
    this.onReveal,
  });

  final HerdrMessage message;
  final HerdrController herdr;

  /// Types out a reply that just arrived; null shows every message whole.
  final RevealMemory? reveal;
  final VoidCallback? onReveal;
  final ValueChanged<Uint8List> onOpenImage;
  final ValueChanged<HerdrMessage> onOpenSubagent;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final caption = AppTextStyle.footnote
        .of(context)
        .copyWith(
          color: message.error ? scheme.error : scheme.onSurfaceVariant,
        );
    final mono = AppTextStyle.footnote
        .of(context)
        .copyWith(fontFamily: 'DejaVuSansMono', fontSize: 11.5, height: 1.45);
    if (message.isTool) {
      final name = message.name.isNotEmpty ? message.name : l10n.agentTool;
      final line = Text(
        message.summary.isEmpty ? name : '$name · ${message.summary}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: mono.copyWith(color: scheme.onSurfaceVariant),
      );
      final images = _ImageStrip(
        refs: message.images,
        herdr: herdr,
        onOpen: onOpenImage,
      );
      if (message.isSubagent) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RowSemantics(
              label:
                  '${l10n.agentSubagent}, '
                  '${message.summary.isEmpty ? name : message.summary}',
              onTap: () => onOpenSubagent(message),
              child: TapFeedback(
                onTap: () => onOpenSubagent(message),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      GlyphIcon(
                        Glyphs2.agents,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: line),
                      GlyphIcon(
                        Glyphs.chevronForward,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            images,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: line,
          ),
          images,
        ],
      );
    }
    switch (message.role) {
      case 'user':
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 0, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _ImageStrip(
                refs: message.images,
                herdr: herdr,
                onOpen: onOpenImage,
              ),
              if (message.text.isNotEmpty)
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    shape: AppShape.all(AppCorner.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: SelectableText(
                      message.text,
                      style: AppTextStyle.body.of(context),
                    ),
                  ),
                ),
              if (message.queued)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlyphIcon(
                        Glyphs2.schedule,
                        size: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.agentSentWhileWorking,
                        style: AppTextStyle.caption2
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'thinking':
        return _ThinkingCard(
          text: message.text,
          style: caption.copyWith(fontStyle: FontStyle.italic),
        );
      case 'output':
        return CommandOutput(text: message.text, style: mono);
      case 'system' || 'command' || 'recap':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText(
            message.text,
            style: mono.copyWith(color: scheme.onSurfaceVariant),
          ),
        );
      default:
        final style = AppTextStyle.body
            .of(context)
            .copyWith(color: message.error ? scheme.error : null, height: 1.45);
        Widget markdown(String text) => MarkdownView(
          text,
          style: style,
          loadImage: herdr.image,
          onOpenImage: onOpenImage,
        );
        final memory = reveal;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: memory == null || message.key.isEmpty
              ? markdown(message.text)
              : RevealText(
                  id: message.key,
                  text: message.text,
                  memory: memory,
                  onGrow: onReveal,
                  builder: (context, visible) => markdown(visible),
                ),
        );
    }
  }
}

/// Transcript image refs in a row; each one loads on its own.
class _ImageStrip extends StatelessWidget {
  const _ImageStrip({
    required this.refs,
    required this.herdr,
    required this.onOpen,
  });

  final List<String> refs;
  final HerdrController herdr;
  final ValueChanged<Uint8List> onOpen;

  @override
  Widget build(BuildContext context) {
    final unique = <String>[];
    for (final ref in refs) {
      if (!unique.contains(ref)) unique.add(ref);
    }
    if (unique.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final ref in unique)
            _RemoteImage(ref: ref, herdr: herdr, onOpen: onOpen),
        ],
      ),
    );
  }
}

class _RemoteImage extends StatefulWidget {
  const _RemoteImage({
    required this.ref,
    required this.herdr,
    required this.onOpen,
  });

  final String ref;
  final HerdrController herdr;
  final ValueChanged<Uint8List> onOpen;

  @override
  State<_RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<_RemoteImage> {
  static const _size = Size(132, 96);

  Uint8List? _bytes;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!widget.ref.startsWith('img:')) {
      // A path on the node: this layer cannot read it, so say so.
      if (mounted) setState(() => _error = '');
      return;
    }
    try {
      final bytes = await widget.herdr.image(widget.ref);
      if (mounted) setState(() => _bytes = bytes);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final bytes = _bytes;
    if (bytes != null) {
      return Semantics(
        button: true,
        label: l10n.agentImageOpen,
        child: TapFeedback(
          onTap: () => widget.onOpen(bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              width: _size.width,
              height: _size.height,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, _, _) => _placeholder(
                context,
                icon: Glyphs2.photo,
                text: l10n.agentImageUnavailable,
              ),
            ),
          ),
        ),
      );
    }
    return _placeholder(
      context,
      icon: Glyphs2.photo,
      text: _error.isNotEmpty || !widget.ref.startsWith('img:')
          ? l10n.agentImageUnavailable
          : l10n.agentImageLoading,
      busy: _error.isEmpty && widget.ref.startsWith('img:'),
      tint: scheme.onSurfaceVariant,
    );
  }

  Widget _placeholder(
    BuildContext context, {
    required Glyph icon,
    required String text,
    bool busy = false,
    Color? tint,
  }) {
    final scheme = context.colorScheme;
    return Container(
      width: _size.width,
      height: _size.height,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: SurfaceLevel.block.colorOf(scheme),
        shape: AppShape.all(AppCorner.md),
      ),
      child: busy
          ? const LoadingIndicator(size: 18)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlyphIcon(icon, size: 18, color: tint),
                const SizedBox(height: 4),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: tint),
                ),
              ],
            ),
    );
  }
}

/// A transcript image at full size, with the usual way back.
class _ImageViewerPage extends StatelessWidget {
  const _ImageViewerPage({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Surface(
      color: const Color(0xFF000000),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                child: Center(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const GlyphIcon(Glyphs.close),
                tooltip: l10n.agentImageClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A subagent's own steps, read from the pane's session while it runs.
class _SubagentView extends StatefulWidget {
  const _SubagentView({
    required this.pane,
    required this.herdr,
    required this.task,
  });

  final String pane;
  final HerdrController herdr;
  final HerdrMessage task;

  @override
  State<_SubagentView> createState() => _SubagentViewState();
}

class _SubagentViewState extends State<_SubagentView> {
  HerdrSubagent? _subagent;
  String _error = '';
  Timer? _timer;

  bool get _live => widget.task.pending || widget.task.background;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    if (_live) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 2500),
        (_) => unawaited(_load()),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _openSubagent(HerdrMessage message) {
    unawaited(
      showExtend<void>(
        context,
        builder: (context) => _SubagentView(
          pane: widget.pane,
          herdr: widget.herdr,
          task: message,
        ),
      ),
    );
  }

  void _openImage(Uint8List bytes) {
    unawaited(
      BaseNavigator.push<void>(context, _ImageViewerPage(bytes: bytes)),
    );
  }

  Future<void> _load() async {
    try {
      final subagent = await widget.herdr.subagent(
        widget.pane,
        widget.task.call,
      );
      if (!mounted) return;
      setState(() {
        _subagent = subagent;
        _error = '';
      });
      if (subagent.finished && _timer != null) {
        _timer?.cancel();
        _timer = null;
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final subagent = _subagent;
    final title = widget.task.summary.isNotEmpty
        ? widget.task.summary
        : l10n.agentSubagent;
    final type = widget.task.text.isNotEmpty
        ? widget.task.text
        : (subagent?.type.isNotEmpty == true ? subagent!.type : '');
    final finished = subagent?.finished ?? !_live;
    return Surface(
      color: SurfaceLevel.page.colorOf(scheme),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(child: _body(context, l10n, subagent)),
            PositionedDirectional(
              start: 0,
              end: 0,
              top: 0,
              child: PageHeader(
                child: PageBar(
                  title: title,
                  subtitle: type.isEmpty ? null : type,
                  onBack: () => Navigator.of(context).maybePop(),
                  trailing: StatusPill(
                    label: finished
                        ? l10n.agentSubagentFinished
                        : l10n.agentSubagentRunning,
                    tint: finished ? const Color(0xFF3BB273) : scheme.primary,
                    dot: true,
                    pulse: !finished,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    HerdrSubagent? subagent,
  ) {
    final scheme = context.colorScheme;
    if (_error.isNotEmpty && subagent == null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(20, context.contentTopPadding, 20, 20),
        children: [
          InlineNotice(text: l10n.agentSubagentFailed(_error)),
          if (widget.task.output.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                widget.task.output,
                style: AppTextStyle.body.of(context),
              ),
            ),
        ],
      );
    }
    if (subagent == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingIndicator(size: 20),
            const SizedBox(height: 10),
            Text(
              l10n.agentSubagentLoading,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final messages = subagent.transcript.messages;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, context.contentTopPadding, 20, 24),
      children: [
        if (messages.isEmpty)
          Text(
            l10n.agentNoMessages,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        for (final message in messages)
          _MessageBlock(
            message: message,
            herdr: widget.herdr,
            onOpenImage: _openImage,
            onOpenSubagent: _openSubagent,
          ),
        if (subagent.finished && widget.task.output.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              radius: AppCorner.lg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MarkdownView(
                  widget.task.output,
                  style: AppTextStyle.footnote.of(context),
                  loadImage: widget.herdr.image,
                  onOpenImage: _openImage,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Commands each harness takes by typing; the description comes from l10n.
List<HerdrCommand> builtinCommands(String kind, AppLocalizations l10n) =>
    switch (kind) {
          'claude' => const [
            'compact',
            'clear',
            'context',
            'cost',
            'model',
            'effort',
            'review',
            'security-review',
            'pr-comments',
            'init',
          ],
          'codex' => const [
            'compact',
            'recap',
            'review',
            'new',
            'init',
            'diff',
            'status',
            'model',
            'plan',
            'goal',
            'fork',
            'side',
            'rename',
            'export',
            'ps',
            'stop',
            'usage',
            'mcp',
          ],
          'pi' || 'omp' => const [
            'compact',
            'new',
            'model',
            'thinking',
            'name',
            'session',
            'export',
            'clone',
            'reload',
          ],
          _ => const [],
        }
        .map(
          (name) =>
              HerdrCommand(name, l10n.agentBuiltinHelp(kind, name), 'builtin'),
        )
        .toList();

/// The jump-to-bottom action the Kotlin chat floats over a scrolled transcript.
class _ScrollToBottom extends StatelessWidget {
  const _ScrollToBottom({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    return TapFeedback(
      onTap: onPressed,
      shape: AppShape.full,
      semanticsLabel: l10n.agentScrollBottom,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: scheme.surfaceContainerHighest,
          shape: AppShape.full,
          shadows: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: GlyphIcon(
          Glyphs2.arrowDown,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Dots, what the agent is doing, a stop button and how many subagents are out.
class _WorkingBar extends StatelessWidget {
  const _WorkingBar({
    required this.activity,
    required this.subagents,
    required this.onStop,
    required this.onSubagents,
  });

  final String activity;
  final int subagents;
  final VoidCallback onStop;
  final VoidCallback onSubagents;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
              decoration: ShapeDecoration(
                color: scheme.surfaceContainerHigh,
                shape: AppShape.full,
              ),
              child: Row(
                children: [
                  const InkDots(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      activity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1.of(context),
                    ),
                  ),
                  TextButton(onPressed: onStop, child: Text(l10n.agentStop)),
                ],
              ),
            ),
          ),
          MotionVisibility(
            visible: subagents > 0,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TapFeedback(
                onTap: onSubagents,
                shape: AppShape.full,
                semanticsLabel: l10n.agentSubagentsRunning,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: ShapeDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: AppShape.full,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlyphIcon(
                        Glyphs2.agents,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$subagents',
                        style: AppTextStyle.caption1.of(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The agent's task list above the composer: the progress line stays, the list
/// expands with the chevron.
class _TodoTrack extends StatefulWidget {
  const _TodoTrack({required this.todos});

  final List<HerdrTodo> todos;

  @override
  State<_TodoTrack> createState() => _TodoTrackState();
}

class _TodoTrackState extends State<_TodoTrack> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final done = widget.todos.where((todo) => todo.done).length;
    final current =
        widget.todos.where((todo) => todo.current).firstOrNull ??
        widget.todos.where((todo) => !todo.done).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: AnimatedContentSize(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TapFeedback(
              onTap: () => setState(() => _open = !_open),
              shape: AppShape.all(AppCorner.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    GlyphIcon(
                      Glyphs2.checklist,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.agentTodoProgress(done, widget.todos.length),
                      style: AppTextStyle.caption1
                          .of(context, emphasized: true)
                          .copyWith(color: scheme.primary),
                    ),
                    const SizedBox(width: 8),
                    if (!_open)
                      Expanded(
                        child: Text(
                          current?.text ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption2
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      )
                    else
                      const Spacer(),
                    RotatingChevron(
                      open: _open,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final todo in widget.todos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 8),
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: todo.done
                                      ? scheme.primary
                                      : todo.current
                                      ? scheme.primary.withValues(alpha: 0.4)
                                      : scheme.onSurfaceVariant.withValues(
                                          alpha: 0.3,
                                        ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                todo.text,
                                style: AppTextStyle.caption1
                                    .of(context)
                                    .copyWith(
                                      color: todo.done
                                          ? scheme.onSurfaceVariant
                                          : scheme.onSurface,
                                      decoration: todo.done
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A blocked agent's question, its screen and the keys it is waiting for.
class _BlockedPanel extends StatefulWidget {
  const _BlockedPanel({
    required this.question,
    required this.screen,
    required this.onKeys,
  });

  final String question;
  final String screen;
  final ValueChanged<List<String>> onKeys;

  @override
  State<_BlockedPanel> createState() => _BlockedPanelState();
}

class _BlockedPanelState extends State<_BlockedPanel> {
  bool _screen = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: ShapeDecoration(
          color: const Color(0xFFE3B341).withValues(alpha: 0.12),
          shape: AppShape.all(AppCorner.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const PulsingDot(
                  color: Color(0xFFE3B341),
                  size: 7,
                  pulse: true,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.agentBlocked,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: const Color(0xFFE3B341)),
                ),
              ],
            ),
            if (widget.question.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.question,
                  maxLines: _screen ? 12 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.body.of(context),
                ),
              ),
            if (_screen && widget.screen.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: ShapeDecoration(
                    color: scheme.surface,
                    shape: AppShape.all(AppCorner.sm),
                  ),
                  child: SelectableText(
                    widget.screen,
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(
                          fontFamily: 'DejaVuSansMono',
                          fontSize: 11,
                          height: 1.4,
                        ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (label, key) in [
                    (l10n.keyEnter, 'enter'),
                    (l10n.keyEscape, 'esc'),
                    ('1', '1'),
                    ('2', '2'),
                    ('3', '3'),
                  ])
                    TextButton(
                      onPressed: () => widget.onKeys([key]),
                      child: Text(label),
                    ),
                  TextButton(
                    onPressed: () => setState(() => _screen = !_screen),
                    child: Text(l10n.agentReadScreen),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Consecutive tool calls under one row: the summary stays, the calls expand.
class _ToolGroup extends StatefulWidget {
  const _ToolGroup({
    super.key,
    required this.messages,
    required this.herdr,
    required this.live,
    required this.onOpenImage,
    required this.onOpenSubagent,
  });

  final List<HerdrMessage> messages;
  final HerdrController herdr;
  final bool live;
  final ValueChanged<Uint8List> onOpenImage;
  final ValueChanged<HerdrMessage> onOpenSubagent;

  @override
  State<_ToolGroup> createState() => _ToolGroupState();
}

class _ToolGroupState extends State<_ToolGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final messages = widget.messages;
    final running = widget.live
        ? messages.reversed.where((m) => m.pending).firstOrNull
        : null;
    final names = <String>[];
    for (final message in messages) {
      if (message.name.isNotEmpty && !names.contains(message.name)) {
        names.add(message.name);
      }
    }
    final summary = running != null
        ? _label(l10n, running)
        : [
            l10n.agentToolSteps(messages.length),
            if (names.isNotEmpty) names.take(3).join(', '),
          ].join(' · ');
    final shown = _open
        ? messages
        : running != null
        ? [running]
        : const <HerdrMessage>[];
    return AnimatedContentSize(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TapFeedback(
            onTap: () => setState(() => _open = !_open),
            shape: AppShape.all(AppCorner.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: Row(
                children: [
                  if (running != null)
                    const LoadingIndicator(size: 16)
                  else
                    GlyphIcon(
                      Glyphs2.doc,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context, emphasized: true)
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  RotatingChevron(
                    open: _open,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedContentSize(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final message in shown)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: _MessageBlock(
                      message: message,
                      herdr: widget.herdr,
                      onOpenImage: widget.onOpenImage,
                      onOpenSubagent: widget.onOpenSubagent,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _label(AppLocalizations l10n, HerdrMessage message) {
    final name = message.name.isNotEmpty ? message.name : l10n.agentTool;
    return message.summary.isEmpty ? name : '$name · ${message.summary}';
  }
}

/// The agent's reasoning, folded under a chevron: the summary stays, the body
/// expands and the card resizes with it (Kotlin's `Expandable`).
class _ThinkingCard extends StatefulWidget {
  const _ThinkingCard({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<_ThinkingCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final firstLine = widget.text
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AnimatedContentSize(
        child: Container(
          decoration: ShapeDecoration(
            color: scheme.surfaceContainerHigh,
            shape: AppShape.all(AppCorner.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TapFeedback(
                onTap: () => setState(() => _open = !_open),
                shape: AppShape.all(AppCorner.md),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  child: Row(
                    children: [
                      GlyphIcon(
                        Glyphs2.bolt,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.agentThinking,
                        style: AppTextStyle.caption1.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!_open)
                        Expanded(
                          child: Text(
                            firstLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.caption2
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        )
                      else
                        const Spacer(),
                      RotatingChevron(
                        open: _open,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedContentSize(
                child: _open
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: SelectableText(widget.text, style: widget.style),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
