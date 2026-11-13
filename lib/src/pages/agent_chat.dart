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
  final _scroll = ScrollController();
  final _input = TextEditingController();
  HerdrTranscript? _transcript;
  String _error = '';
  String _notice = '';
  bool _loading = true;
  bool _sending = false;
  bool _restarting = false;
  Timer? _reload;

  String get _pane => widget.agent.paneId;

  HerdrAgent get _agent {
    for (final agent in widget.herdr.agents) {
      if (agent.paneId == _pane) return agent;
    }
    return widget.agent;
  }

  @override
  void initState() {
    super.initState();
    widget.herdr.addListener(_onHerdr);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.herdr.removeListener(_onHerdr);
    _reload?.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  /// herdr events say that the pane moved; re-read once the burst settles.
  void _onHerdr() {
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 300), () => unawaited(_load()));
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _notice = '';
    });
    try {
      await widget.herdr.prompt(_pane, text);
      _input.clear();
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
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                        style: AppTextStyle.title3.of(context, emphasized: true),
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
                style: AppTextStyle.footnote.of(context).copyWith(
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
          _MessageBlock(message: message),
      ],
    );
  }

  Widget _composer(BuildContext context, AppLocalizations l10n) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => unawaited(_send()),
              style: AppTextStyle.body.of(context),
              decoration: InputDecoration(
                hintText: l10n.agentPromptHint,
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
                : const GlyphIcon(Glyphs2.arrowUp),
            tooltip: l10n.agentSend,
          ),
        ],
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({required this.message});

  final HerdrMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final caption = AppTextStyle.footnote
        .of(context)
        .copyWith(color: message.error ? scheme.error : scheme.onSurfaceVariant);
    final mono = AppTextStyle.footnote.of(context).copyWith(
      fontFamily: 'DejaVuSansMono',
      fontSize: 11.5,
      height: 1.45,
    );
    if (message.isTool) {
      final name = message.name.isNotEmpty ? message.name : 'tool';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          message.summary.isEmpty ? name : '$name · ${message.summary}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: mono.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    switch (message.role) {
      case 'user':
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 0, 6),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              shape: AppShape.all(AppCorner.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: SelectableText(
                message.text,
                style: AppTextStyle.body.of(context),
              ),
            ),
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
            style: AppTextStyle.body.of(context).copyWith(
              color: message.error ? scheme.error : null,
              height: 1.45,
            ),
          ),
        );
    }
  }
}
