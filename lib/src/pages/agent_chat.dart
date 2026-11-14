import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
import '../herdr.dart';
import '../l10n.dart';
import '../widgets/foundation.dart';

/// One agent pane: its transcript, a prompt box, restart and model switching.
class AgentChatPage extends StatefulWidget {
  const AgentChatPage({super.key, required this.agent, required this.herdr});

  final HerdrAgent agent;
  final HerdrController herdr;

  @override
  State<AgentChatPage> createState() => _AgentChatPageState();
}

class _AgentChatPageState extends State<AgentChatPage> {
  static const _maxSuggestions = 6;

  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  HerdrTranscript? _transcript;
  String _error = '';
  String _notice = '';
  bool _loading = true;
  bool _sending = false;
  bool _restarting = false;
  Timer? _reload;
  List<HerdrCommand> _commands = const [];
  List<HerdrCommand> _suggestions = const [];
  int _suggestion = 0;
  bool _dismissed = false;
  bool _loadingCommands = false;
  bool _commandsLoaded = false;

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
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.herdr.removeListener(_onHerdr);
    _reload?.cancel();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
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

  static String _message(Object error) =>
      error is Exception ? error.toString() : '$error';

  Future<void> _load({bool more = false}) async {
    try {
      if (more) await widget.herdr.transcriptMore(_pane);
      final transcript = await widget.herdr.transcript(_pane);
      if (!mounted) return;
      setState(() {
        _transcript = transcript;
        _error = '';
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
    }
  }

  // ---- slash commands ----

  /// A leading `/word` with no whitespace asks for the command popup.
  void _onDraft() {
    final text = _input.text;
    final asking = text.startsWith('/') && !text.contains(RegExp(r'\s'));
    if (!asking) {
      if (_suggestions.isEmpty && !_dismissed) return;
      setState(() {
        _suggestions = const [];
        _dismissed = false;
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
      _dismissed = false;
      _suggestion = 0;
      _suggestions = matches.take(_maxSuggestions).toList();
    });
  }

  /// herdr's own commands come from the node; the harness's built-ins are
  /// always there, so the popup works before the first list arrives.
  Future<void> _loadCommands() async {
    if (_loadingCommands) return;
    _loadingCommands = true;
    final builtin = builtinCommands(_agent.kind);
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
      _suggestions = const [];
      _suggestion = 0;
    });
    _inputFocus.requestFocus();
  }

  void _dismissCommands() {
    if (_suggestions.isEmpty) return;
    setState(() {
      _suggestions = const [];
      _dismissed = true;
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
      _notice = '';
      _suggestions = const [];
    });
  }

  Future<void> _sendQueued(QueuedPrompt prompt) async {
    if (widget.herdr.dequeue(_pane, prompt.id) == null) return;
    await _sendText(prompt.text);
  }

  Future<void> _sendText(String text) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _notice = '';
    });
    try {
      await widget.herdr.prompt(_pane, text);
      if (mounted) _clearDraft();
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _notice = l10n.agentActionFailed(_message(error)));
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
      _notice = '';
    });
    try {
      await widget.herdr.restart(_pane);
      if (!mounted) return;
      setState(() => _notice = l10n.agentRestarted);
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _notice = l10n.agentRestartFailed(_message(error)));
      }
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  Future<void> _pickModel() async {
    final l10n = AppLocalizations.of(context);
    HerdrModels options;
    try {
      options = await widget.herdr.models(_agent.kind, _pane);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _notice = l10n.agentActionFailed(_message(error)));
      }
      return;
    }
    if (!mounted) return;
    if (options.models.isEmpty) {
      setState(() => _notice = l10n.agentModelEmpty);
      return;
    }
    final current = _transcript?.model ?? '';
    final chosen = await showFormSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.agentModel,
              style: AppTextStyle.title2.of(context, emphasized: true),
            ),
            const SizedBox(height: 10),
            GroupCard(
              dividerInset: 16,
              children: [
                for (final model in options.models)
                  PressRegion(
                    onTap: () => Navigator.of(context).pop(model.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(model.name)),
                          if (model.id == current)
                            GlyphIcon(
                              Glyphs.check,
                              size: 16,
                              color: context.colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await widget.herdr.setModel(_pane, chosen);
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _notice = l10n.agentActionFailed(_message(error)));
      }
    }
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
    return Surface(
      color: SurfaceLevel.page.colorOf(scheme),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              _header(context, l10n, agent, status, tint),
              if (_notice.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: InlineNotice(
                    text: _notice,
                    tint: scheme.onSurfaceVariant,
                  ),
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _body(context, l10n),
                  ),
                ),
              ),
              _composer(context, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    HerdrAgent agent,
    String status,
    Color tint,
  ) {
    final scheme = context.colorScheme;
    final model = _transcript?.model ?? '';
    final subtitle = [
      agent.kind,
      if (model.isNotEmpty) model,
      if (_transcript?.contextWindow != null && _transcript!.contextWindow > 0)
        '${_contextLabel(_transcript!.contextUsed)} / ${_contextLabel(_transcript!.contextWindow)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const GlyphIcon(Glyphs.chevronBack),
            tooltip: l10n.back,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        agent.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.title3.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(label: status, tint: tint),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _restarting ? null : () => unawaited(_pickModel()),
            icon: const GlyphIcon(Glyphs2.sliders),
            tooltip: l10n.agentModel,
          ),
          IconButton(
            onPressed: _restarting ? null : () => unawaited(_restart()),
            icon: _restarting
                ? const ActivityIndicator(size: 16)
                : const GlyphIcon(Glyphs2.refresh),
            tooltip: _restarting ? l10n.agentRestarting : l10n.agentRestart,
          ),
        ],
      ),
    );
  }

  static String _contextLabel(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).round()}k';
    return '$tokens';
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final scheme = context.colorScheme;
    if (_loading) {
      return const Center(child: ActivityIndicator(size: 20));
    }
    if (_error.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        children: [InlineNotice(text: _error)],
      );
    }
    final transcript = _transcript;
    if (transcript == null) return const SizedBox.shrink();
    if (transcript.screenMode) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
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
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
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
        for (final message in transcript.messages)
          _MessageBlock(
            message: message,
            herdr: widget.herdr,
            onOpenImage: _openImage,
            onOpenSubagent: _openSubagent,
          ),
      ],
    );
  }

  Widget _composer(BuildContext context, AppLocalizations l10n) {
    final scheme = context.colorScheme;
    final queue = _queue;
    final popup = _suggestions.isNotEmpty;
    final composer = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                    if (popup) {
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
              IconButton(
                onPressed: _sending ? null : () => unawaited(_send()),
                icon: _sending
                    ? const ActivityIndicator(size: 18)
                    : GlyphIcon(_working ? Glyphs2.schedule : Glyphs2.arrowUp),
                tooltip: _working ? l10n.agentQueued : l10n.agentSend,
              ),
            ],
          ),
        ),
      ],
    );
    // The wrapper stays in place so the input keeps its focus and text
    // connection; only the popup's keys are bound, and only while it is up.
    return CallbackShortcuts(
      bindings: popup
          ? {
              const SingleActivator(LogicalKeyboardKey.escape):
                  _dismissCommands,
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _moveSuggestion(-1),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _moveSuggestion(1),
            }
          : const {},
      child: composer,
    );
  }
}

/// Commands matching the draft, above the input: name, description, skill tag.
class _CommandPopup extends StatelessWidget {
  const _CommandPopup({
    required this.commands,
    required this.selected,
    required this.onPick,
  });

  final List<HerdrCommand> commands;
  final int selected;
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
            for (var i = 0; i < commands.length; i++)
              RowSemantics(
                label: l10n.agentCommandLabel(
                  commands[i].name,
                  commands[i].description,
                ),
                onTap: () => onPick(i),
                child: PressRegion(
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

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.message,
    required this.herdr,
    required this.onOpenImage,
    required this.onOpenSubagent,
  });

  final HerdrMessage message;
  final HerdrController herdr;
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
              child: PressRegion(
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
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SelectableText(
            message.text,
            style: caption.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      case 'system' || 'command' || 'output' || 'recap':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText(
            message.text,
            style: mono.copyWith(color: scheme.onSurfaceVariant),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: SelectableText(
            message.text,
            style: AppTextStyle.body
                .of(context)
                .copyWith(
                  color: message.error ? scheme.error : null,
                  height: 1.45,
                ),
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
        child: PressRegion(
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
          ? const ActivityIndicator(size: 18)
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const GlyphIcon(Glyphs.chevronBack),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.title3.of(
                              context,
                              emphasized: true,
                            ),
                          ),
                        ),
                        if (type.isNotEmpty)
                          Text(
                            type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.footnote
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label: finished
                        ? l10n.agentSubagentFinished
                        : l10n.agentSubagentRunning,
                    tint: finished ? const Color(0xFF3BB273) : scheme.primary,
                  ),
                ],
              ),
            ),
            Expanded(child: _body(context, l10n, subagent)),
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
            const ActivityIndicator(size: 20),
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
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
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
                child: SelectableText(
                  widget.task.output,
                  style: AppTextStyle.footnote.of(context),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Commands each harness takes by typing, with what they do.
List<HerdrCommand> builtinCommands(String kind) => switch (kind) {
  'claude' => const [
    ('compact', 'Compact the conversation'),
    ('clear', 'Start a new conversation'),
    ('context', 'Show context usage'),
    ('cost', 'Show usage and cost'),
    ('model', 'Switch model'),
    ('effort', 'Set thinking effort'),
    ('review', 'Review a pull request'),
    ('security-review', 'Review pending changes for security issues'),
    ('pr-comments', 'Fetch pull request comments'),
    ('init', 'Write CLAUDE.md for this project'),
  ],
  'codex' => const [
    ('compact', 'Summarize the conversation to free context'),
    ('recap', 'Summarize the conversation now'),
    ('review', 'Review current changes and find issues'),
    ('new', 'Start a new chat'),
    ('init', 'Create an AGENTS.md file'),
    ('diff', 'Show git diff, including untracked files'),
    ('status', 'Show session configuration and token usage'),
    ('model', 'Choose model and reasoning effort'),
    ('plan', 'Switch to Plan mode'),
    ('goal', 'Set or view the goal of a long task'),
    ('fork', 'Fork the current chat'),
    ('side', 'Start a side conversation'),
    ('rename', 'Rename the thread'),
    ('export', 'Export the conversation as Markdown'),
    ('ps', 'List background terminals'),
    ('stop', 'Stop all background terminals'),
    ('usage', 'View account usage'),
    ('mcp', 'List MCP tools'),
  ],
  'pi' || 'omp' => const [
    ('compact', 'Compact the session context'),
    ('new', 'Start a new session'),
    ('model', 'Switch model (provider/model)'),
    ('thinking', 'Set thinking level'),
    ('name', 'Set session display name'),
    ('session', 'Show session info and stats'),
    ('export', 'Export the session'),
    ('clone', 'Duplicate the session at this point'),
    ('reload', 'Reload extensions, skills and prompts'),
  ],
  _ => const [],
}.map((pair) => HerdrCommand(pair.$1, pair.$2, 'builtin')).toList();
