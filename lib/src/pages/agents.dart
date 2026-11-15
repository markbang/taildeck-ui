import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../agents_phase.dart';
import '../backend.dart';
import '../data.dart';
import '../demo/demo.dart';
import '../glyphs.dart';
import '../herdr.dart';
import '../l10n.dart';
import '../motion.dart';
import '../native/bridge.dart';
import '../preview_env.dart';
import '../ssh_identities.dart';
import '../widgets/controls.dart';
import '../widgets/entry_row.dart';
import '../widgets/foundation.dart';
import '../widgets/net_loading.dart';
import '../widgets/select_row.dart';
import '../widgets/shape_badge.dart';
import 'agent_chat.dart';
import 'new_agent_sheet.dart';

class AgentsPage extends StatefulWidget {
  const AgentsPage({super.key});

  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  /// The last phase logged, so the smoke test can follow the page in logcat.
  AgentsPhase? _loggedPhase;
  /// Demo list: the web preview and hosts without the shared library.
  late final List<({String section, List<DemoAgent> items})> _demo = [
    for (final group in demoAgents)
      (section: group.section, items: [...group.items]),
  ];
  String _notice = '';

  Future<void> _addDemoAgent() async {
    final choice = await showNewAgentSheet(context);
    if (choice == null || !mounted) return;
    setState(() {
      final index = _demo.indexWhere((g) => g.section == choice.project);
      final item = DemoAgent(
        name: choice.harness,
        state: DemoAgentState.idle,
        task: choice.task,
        project: choice.project,
        window: 'w1:p1',
      );
      if (index == -1) {
        _demo.add((section: choice.project, items: [item]));
      } else {
        _demo[index].items.add(item);
      }
      _notice = AppLocalizations.of(context).agentCreated(choice.harness);
    });
  }

  Future<void> _addAgent(HerdrController herdr) async {
    final l10n = AppLocalizations.of(context);
    final workspaces = await _workspaces(herdr);
    if (!mounted) return;
    final created = await showNewAgentSheet(
      context,
      herdr: herdr,
      workspaces: workspaces,
    );
    if (created == null || !mounted) return;
    final promptError = created.promptError;
    setState(() {
      _notice = promptError.isNotEmpty
          ? l10n.agentPromptFailed(promptError)
          : l10n.agentCreated(created.harness);
    });
  }

  static Future<List<({String id, String label})>> _workspaces(
    HerdrController herdr,
  ) async {
    try {
      return await herdr.workspaces();
    } on Object {
      return const [];
    }
  }

  void _openAgent(HerdrController herdr, HerdrAgent agent) {
    BaseNavigator.push(context, AgentChatPage(agent: agent, herdr: herdr));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final backend = BackendScope.of(context);
    final herdr = backend.herdr;
    if (herdr == null) {
      return demoData ? _demoPage(l10n, backend) : _unavailablePage(l10n);
    }
    return ListenableBuilder(
      listenable: herdr,
      builder: (context, _) {
        final phase = _phaseOf(backend, herdr);
        if (phase != _loggedPhase) {
          _loggedPhase = phase;
          debugPrint('taildeck agents: ${phase.name}');
        }
        return Stack(
          children: [
            PageBody(
              title: l10n.agentsTitle,
              subtitle: herdr.node.isEmpty ? 'herdr' : 'herdr · ${herdr.node}',
              onRefresh: herdr.ready ? herdr.refresh : null,
              // The new-agent button floats at the foot; its rows stop above it.
              bottomExtra: 64,
              children: [
                if (_notice.isNotEmpty) ...[
                  InlineNotice(
                    text: _notice,
                    tint: context.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 14),
                ],
                ScaleFadeSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey(_phaseKey(phase, herdr)),
                    child: _body(context, l10n, backend, herdr, phase),
                  ),
                ),
              ],
            ),
            PositionedDirectional(
              end: 20,
              bottom: context.bottomInset + 20,
              child: _NewAgentFab(
                visible: phase == AgentsPhase.ready,
                label: l10n.newAgent,
                onPressed: () => unawaited(_addAgent(herdr)),
              ),
            ),
          ],
        );
      },
    );
  }

  /// What the page shows: the node comes up first, then herdr, and only a
  /// real failure gets an error.
  static AgentsPhase _phaseOf(TaildeckBackend backend, HerdrController herdr) =>
      agentsPhaseOf(
        herdrReady: herdr.ready,
        waking: backend.herdrWaking,
        link: herdr.link,
        tailnetReady: backend.tailnetReady,
        hasTarget: backend.herdrTarget.node.isNotEmpty,
      );

  /// Which of herdr's states the page is drawing, so the swap animates only
  /// when that changes (Kotlin's `AnimatedContent(state?.javaClass)`).
  static String _phaseKey(AgentsPhase phase, HerdrController herdr) {
    return switch (phase) {
      AgentsPhase.ready when herdr.agents.isEmpty => 'empty',
      AgentsPhase.ready =>
        'agents:${_groups(herdr.agents).map((g) => g.section).join('|')}',
      AgentsPhase.failed => 'failed:${herdr.failure.name}',
      _ => phase.name,
    };
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    TaildeckBackend backend,
    HerdrController herdr,
    AgentsPhase phase,
  ) {
    final node = herdr.node.isEmpty ? backend.herdrTarget.node : herdr.node;
    switch (phase) {
      case AgentsPhase.tailnet:
        return NetLoading(
          title: l10n.tailnetWaiting,
          caption: l10n.tailnetWaitingBody,
        );
      case AgentsPhase.connecting:
        return NetLoading(title: l10n.herdrConnecting(node));
      case AgentsPhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HerdrMessageCard(
              message: l10n.herdrFailure(node, herdr.failure),
              actionLabel: l10n.herdrRetry,
              onAction: () => unawaited(backend.retryHerdr()),
            ),
            const SizedBox(height: 12),
            _HerdrSettingsSection(backend: backend),
          ],
        );
      case AgentsPhase.idle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HerdrMessageCard(
              message: l10n.herdrIdle,
              actionLabel: l10n.reconnect,
              onAction: () => unawaited(backend.retryHerdr()),
            ),
            const SizedBox(height: 12),
            _HerdrSettingsSection(backend: backend),
          ],
        );
      case AgentsPhase.setup:
        return _HerdrSettingsSection(
          backend: backend,
          initiallyOpen: true,
          showToggle: false,
        );
      case AgentsPhase.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (herdr.agents.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 24, 6, 8),
                child: Text(
                  l10n.herdrNoAgents,
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              )
            else
              for (final (index, group) in _groups(herdr.agents).indexed) ...[
                Reveal(
                  key: ValueKey('agents-heading-${group.section}'),
                  index: index,
                  child: SectionLabel(
                    group.section == 'Needs you'
                        ? l10n.needsYou
                        : group.section,
                  ),
                ),
                Reveal(
                  key: ValueKey('agents-card-${group.section}'),
                  index: index,
                  child: AnimatedGroupCard(
                    dividerInset: 56,
                    children: [
                      for (final agent in group.items)
                        RowSemantics(
                          key: ValueKey(agent.paneId),
                          label: _liveAgentLabel(context, l10n, agent),
                          onTap: () => _openAgent(herdr, agent),
                          child: _LiveAgentRow(
                            agent: agent,
                            onTap: () => _openAgent(herdr, agent),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
          ],
        );
    }
  }

  Widget _demoPage(AppLocalizations l10n, TaildeckBackend backend) {
    final scheme = context.colorScheme;
    // `?tab=2&herdr=tailnet|connecting|error|connect` previews the startup
    // states on the web build, which has no node behind it.
    final preview = previewParam('herdr') ?? '';
    if (preview == 'tailnet' || preview == 'connecting' || preview == 'error') {
      return PageBody(
        title: l10n.agentsTitle,
        subtitle: preview == 'error' ? 'herdr · bangwu' : 'herdr · devbox',
        bottomExtra: 64,
        children: [
          if (preview == 'tailnet')
            NetLoading(
              title: l10n.tailnetWaiting,
              caption: l10n.tailnetWaitingBody,
            )
          else if (preview == 'connecting')
            NetLoading(title: l10n.herdrConnecting('devbox'))
          else ...[
            _HerdrMessageCard(
              message: l10n.herdrErrorNoHost('bangwu'),
              actionLabel: l10n.herdrRetry,
              onAction: () {},
            ),
            const SizedBox(height: 12),
            _HerdrSettingsSection(backend: backend, preview: true),
          ],
        ],
      );
    }
    final connect = preview == 'connect';
    return Stack(
      children: [
        PageBody(
          title: l10n.agentsTitle,
          subtitle: 'herdr · devbox',
          bottomExtra: 64,
          children: [
            InlineNotice(
              text: l10n.herdrNeedsBackend,
              tint: scheme.onSurfaceVariant,
            ),
            if (_notice.isNotEmpty) ...[
              const SizedBox(height: 6),
              InlineNotice(text: _notice, tint: scheme.onSurfaceVariant),
            ],
            if (connect) ...[
              const SizedBox(height: 14),
              _HerdrConnectCard(backend: backend, preview: true),
            ],
            const SizedBox(height: 6),
            for (final (index, group) in _demo.indexed) ...[
              Reveal(
                key: ValueKey('demo-heading-${group.section}'),
                index: index,
                child: SectionLabel(
                  group.section == 'Needs you' ? l10n.needsYou : group.section,
                ),
              ),
              Reveal(
                key: ValueKey('demo-card-${group.section}'),
                index: index,
                child: AnimatedGroupCard(
                  dividerInset: 56,
                  children: [
                    for (final agent in group.items)
                      RowSemantics(
                        key: ValueKey(
                          '${agent.project}/${agent.name}/${agent.task}',
                        ),
                        label: _demoAgentLabel(l10n, agent),
                        child: _DemoAgentRow(agent: agent),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
        PositionedDirectional(
          end: 20,
          bottom: context.bottomInset + 20,
          child: _NewAgentFab(
            visible: true,
            label: l10n.newAgent,
            onPressed: () => unawaited(_addDemoAgent()),
          ),
        ),
      ],
    );
  }

  /// A release build without the native library: no demo cards, just why.
  Widget _unavailablePage(AppLocalizations l10n) {
    return PageBody(
      title: l10n.agentsTitle,
      subtitle: 'herdr',
      children: [
        InlineNotice(
          text: l10n.herdrNeedsBackend,
          tint: context.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 24, 6, 8),
          child: Text(
            l10n.herdrNoAgents,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  static List<({String section, List<HerdrAgent> items})> _groups(
    List<HerdrAgent> all,
  ) {
    final needsYou =
        [
          for (final agent in all)
            if (agent.status == HerdrStatus.blocked ||
                agent.status == HerdrStatus.done)
              agent,
        ]..sort(
          (a, b) => (a.status == HerdrStatus.blocked ? 0 : 1).compareTo(
            b.status == HerdrStatus.blocked ? 0 : 1,
          ),
        );
    final projects = <String, List<HerdrAgent>>{};
    for (final agent in all) {
      if (needsYou.contains(agent)) continue;
      final section = agent.workspace.isEmpty ? 'herdr' : agent.workspace;
      projects.putIfAbsent(section, () => []).add(agent);
    }
    final keys = projects.keys.toList()..sort();
    return [
      if (needsYou.isNotEmpty) (section: 'Needs you', items: needsYou),
      for (final key in keys) (section: key, items: projects[key]!),
    ];
  }
}

/// Kotlin's badge polygons, per status: working spins, blocked bursts, done and
/// idle rest on a cookie (Expressive.kt `ShapeBadge`).
BlobShape _liveShape(HerdrStatus status) => switch (status) {
  HerdrStatus.working => BlobShape.cookie9,
  HerdrStatus.blocked => BlobShape.softBurst,
  HerdrStatus.done => BlobShape.cookie6,
  HerdrStatus.idle || HerdrStatus.unknown => BlobShape.cookie4,
};

BlobShape _demoShape(DemoAgentState state) => switch (state) {
  DemoAgentState.working => BlobShape.cookie9,
  DemoAgentState.done => BlobShape.cookie6,
  DemoAgentState.idle => BlobShape.cookie4,
};

/// The herdr action: fades and expands in once herdr is ready, as the Kotlin
/// page's `SmallExtendedFloatingActionButton` does.
class _NewAgentFab extends StatelessWidget {
  const _NewAgentFab({
    required this.visible,
    required this.label,
    required this.onPressed,
  });

  final bool visible;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return MotionVisibility(
      visible: visible,
      scaleFrom: 0.8,
      expand: true,
      alignment: AlignmentDirectional.bottomEnd,
      child: TapFeedback(
        onTap: onPressed,
        shape: AppShape.full,
        child: Semantics(
          button: true,
          label: label,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 18, 12),
            decoration: ShapeDecoration(
              color: scheme.primaryContainer,
              shape: AppShape.full,
              shadows: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlyphIcon(
                  Glyphs2.plus,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyle.body
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onPrimaryContainer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

(String, Color) _statusOf(BuildContext context, HerdrStatus status) {
  final l10n = AppLocalizations.of(context);
  final scheme = context.colorScheme;
  return switch (status) {
    HerdrStatus.working => (l10n.working, scheme.primary),
    HerdrStatus.blocked => (l10n.blocked, const Color(0xFFE3B341)),
    HerdrStatus.done => (l10n.done, const Color(0xFF3BB273)),
    HerdrStatus.idle => (l10n.idle, scheme.onSurfaceVariant),
    HerdrStatus.unknown => ('—', scheme.onSurfaceVariant),
  };
}

String _liveAgentLabel(
  BuildContext context,
  AppLocalizations l10n,
  HerdrAgent agent,
) => l10n.agentSemantics(
  agent.workspace.isEmpty ? 'herdr' : agent.workspace,
  agent.kind,
  _statusOf(context, agent.status).$1,
);

String _demoAgentLabel(AppLocalizations l10n, DemoAgent agent) =>
    l10n.agentSemantics(agent.project, agent.name, switch (agent.state) {
      DemoAgentState.working => l10n.working,
      DemoAgentState.idle => l10n.idle,
      DemoAgentState.done => l10n.done,
    });

/// Name, status, task and pane of one live agent.
class _LiveAgentRow extends StatelessWidget {
  const _LiveAgentRow({required this.agent, required this.onTap});

  final HerdrAgent agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, tint) = _statusOf(context, agent.status);
    final scheme = context.colorScheme;
    final detail = agent.title.isNotEmpty ? agent.title : agent.cwd;
    return TapFeedback(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShapeBadge(
              shape: _liveShape(agent.status),
              color: tint.withValues(alpha: 0.14),
              size: 34,
              spin: agent.status == HerdrStatus.working,
              child: Text(
                agent.label.characters.first.toUpperCase(),
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(color: tint),
              ),
            ),
            const SizedBox(width: 12),
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
                          style: AppTextStyle.body.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusPill(
                        label: label,
                        tint: tint,
                        dot: true,
                        pulse:
                            agent.status == HerdrStatus.working ||
                            agent.status == HerdrStatus.blocked,
                      ),
                    ],
                  ),
                  if (detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.listSubtitleStyle,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${agent.kind} · ${agent.paneId}',
                      style: context.listCaptionStyle,
                    ),
                  ),
                ],
              ),
            ),
            GlyphIcon(
              Glyphs.chevronForward,
              size: 14,
              color: scheme.onSurfaceVariant.opacity50,
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoAgentRow extends StatelessWidget {
  const _DemoAgentRow({required this.agent});

  final DemoAgent agent;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final (label, tint) = switch (agent.state) {
      DemoAgentState.working => (l10n.working, scheme.primary),
      DemoAgentState.idle => (l10n.idle, scheme.onSurfaceVariant),
      DemoAgentState.done => (l10n.done, const Color(0xFF3BB273)),
    };
    final task = agent.demoTask == null
        ? agent.task
        : demoTaskText(agent.demoTask, zh: l10n.isZh);
    return TapFeedback(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShapeBadge(
              shape: _demoShape(agent.state),
              color: tint.withValues(alpha: 0.14),
              size: 34,
              spin: agent.state == DemoAgentState.working,
              child: Text(
                agent.name.characters.first.toUpperCase(),
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(color: tint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        agent.name,
                        style: AppTextStyle.body.of(context, emphasized: true),
                      ),
                      const SizedBox(width: 6),
                      StatusPill(label: label, tint: tint, dot: true),
                    ],
                  ),
                  if (task.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        task,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.listSubtitleStyle,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${agent.project} · ${agent.window}',
                      style: context.listCaptionStyle,
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

/// One sentence about the connection and the action that helps, with no Go
/// error in sight.
class _HerdrMessageCard extends StatelessWidget {
  const _HerdrMessageCard({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      radius: AppCorner.xl,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(message, style: AppTextStyle.subheadline.of(context)),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: LoadingButton(
              label: actionLabel,
              glyph: Glyphs2.refresh,
              onPressed: onAction,
            ),
          ),
        ],
      ),
    );
  }
}

/// The connection form stays folded behind one row except on first setup.
class _HerdrSettingsSection extends StatefulWidget {
  const _HerdrSettingsSection({
    required this.backend,
    this.initiallyOpen = false,
    this.showToggle = true,
    this.preview = false,
  });

  final TaildeckBackend backend;
  final bool initiallyOpen;

  /// First setup: there is nothing else on the page, so the form is the page.
  final bool showToggle;
  final bool preview;

  @override
  State<_HerdrSettingsSection> createState() => _HerdrSettingsSectionState();
}

class _HerdrSettingsSectionState extends State<_HerdrSettingsSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = widget.backend.herdrTarget;
    final label = _open
        ? l10n.herdrHideConnectionSettings
        : l10n.herdrConnectionSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToggle)
          RowSemantics(
            label: label,
            onTap: () => setState(() => _open = !_open),
            child: TapFeedback(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    GlyphIcon(
                      Glyphs2.sliders,
                      size: 16,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    if (target.node.isNotEmpty && !_open)
                      Text(target.node, style: context.listCaptionStyle),
                    const SizedBox(width: 6),
                    GlyphIcon(
                      _open ? Glyphs2.arrowUp : Glyphs2.arrowDown,
                      size: 12,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_open) ...[
          if (widget.showToggle) const SizedBox(height: 6),
          _HerdrConnectCard(backend: widget.backend, preview: widget.preview),
        ],
      ],
    );
  }
}

/// Node, user and credentials for the herdr connection, prefilled from the
/// last successful one.
class _HerdrConnectCard extends StatefulWidget {
  const _HerdrConnectCard({required this.backend, this.preview = false});

  final TaildeckBackend backend;

  /// Web preview: no node behind the form, so it stays usable.
  final bool preview;

  @override
  State<_HerdrConnectCard> createState() => _HerdrConnectCardState();
}

class _HerdrConnectCardState extends State<_HerdrConnectCard> {
  late String _node = widget.backend.herdrTarget.node;
  late final _user = TextEditingController(text: _rememberedUser);
  late final _port = TextEditingController(text: '$_targetPort');
  late String _auth = widget.backend.herdrTarget.auth;
  late String _identity = widget.backend.herdrTarget.identity;
  String _userError = '';
  String _portError = '';
  final _password = TextEditingController();
  final _nodeInput = TextEditingController();
  List<SshIdentity> _identities = const [];
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _user.addListener(_validateUser);
    _port.addListener(_validatePort);
    if (widget.backend.available) unawaited(_loadKeys());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _validateUser();
    _validatePort();
  }

  void _validateUser() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final value = _user.text.trim();
    final error = value.isEmpty
        ? l10n.sshUserRequired
        : isValidSshUser(value)
        ? ''
        : l10n.sshUserInvalid;
    if (error != _userError) setState(() => _userError = error);
  }

  void _validatePort() {
    if (!mounted) return;
    final error = portValue(_port.text) == null
        ? AppLocalizations.of(context).portInvalid
        : '';
    if (error != _portError) setState(() => _portError = error);
  }

  Future<void> _loadKeys() async {
    try {
      final keys = await widget.backend.sshIdentities();
      if (!mounted) return;
      setState(() {
        _identities = keys;
        if (_identity.isEmpty && keys.isNotEmpty) {
          _identity = keys.first.id;
        }
      });
    } on Object {
      // The key list is filled in by the SSH sheet; connecting can still work.
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _port.dispose();
    _password.dispose();
    _nodeInput.dispose();
    super.dispose();
  }

  /// The login this node was last reached with, else the last herdr one.
  String get _rememberedUser {
    final saved = widget.backend.sshUserFor(_node);
    return saved.isEmpty ? widget.backend.herdrTarget.user : saved;
  }

  /// The port this node was last reached on, else the last herdr one.
  int get _targetPort {
    final saved = widget.backend.sshPortFor(_node);
    return saved == 22 ? widget.backend.herdrTarget.port : saved;
  }

  List<NodeItem> get _nodes =>
      widget.preview ? [demoSelfNode, ...demoPeers] : widget.backend.nodes;

  String get _selfName =>
      widget.preview ? demoSelfNode.name : (widget.backend.self?.name ?? '');

  String get _defaultNode {
    final self = _selfName;
    for (final node in _nodes) {
      if (node.name != self) return node.name;
    }
    return _nodes.isEmpty ? '' : _nodes.first.name;
  }

  /// Last login on this node, its tailnet login, then root.
  List<String> get _userSuggestions {
    final name = _node.isEmpty ? _defaultNode : _node;
    final item = _nodes.where((node) => node.name == name).firstOrNull;
    return widget.backend.sshUserSuggestions(
      name,
      login: item?.suggestedSshUser ?? '',
    );
  }

  Future<void> _connect() async {
    if (_busy) return;
    _validateUser();
    _validatePort();
    if (_userError.isNotEmpty || _portError.isNotEmpty) return;
    final l10n = AppLocalizations.of(context);
    final node = _node.isNotEmpty
        ? _node
        : (_defaultNode.isNotEmpty ? _defaultNode : _nodeInput.text.trim());
    if (node.isEmpty) {
      setState(() => _error = l10n.serviceNode);
      return;
    }
    final port = portValue(_port.text)!;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.backend.connectHerdr(
        node: node,
        user: _user.text.trim(),
        port: port,
        auth: _auth,
        identityId: _identity,
        password: _password.text,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is BridgeException ? error.message : '$error';
      final failure = HerdrFailure.of(message);
      setState(() {
        _error = failure == HerdrFailure.other
            ? message
            : l10n.herdrFailure(node, failure);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final names = [for (final node in _nodes) (node.name, node.name)];
    return Card(
      radius: AppCorner.xl,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.herdrConnectTitle,
                  style: AppTextStyle.body.of(context, emphasized: true),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.herdrConnectBody,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (names.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.serviceNode, style: context.listTitleStyle),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nodeInput,
                    style: context.listSubtitleStyle,
                    decoration: InputDecoration(
                      hintText: 'devbox',
                      hintStyle: context.listCaptionStyle,
                      filled: true,
                      fillColor: SurfaceLevel.block.colorOf(scheme),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SelectRow<String>(
              label: l10n.serviceNode,
              value: _node.isEmpty ? _defaultNode : _node,
              options: names,
              onChanged: (value) => setState(() => _node = value),
            ),
          const _RowDivider(),
          EntryRow(
            label: l10n.sshUser,
            controller: _user,
            hintText: 'root',
            errorText: _userError.isEmpty ? null : _userError,
            enabled: !_busy,
            autofillHints: const [AutofillHints.username],
            suggestions: _userSuggestions,
          ),
          const _RowDivider(),
          EntryRow(
            label: l10n.sshPort,
            controller: _port,
            hintText: '22',
            numeric: true,
            errorText: _portError.isEmpty ? null : _portError,
            enabled: !_busy,
          ),
          const _RowDivider(),
          SelectRow<String>(
            label: l10n.sshAuth,
            value: _auth,
            options: [
              ('tailscale', l10n.authTailscale),
              ('key', l10n.authKey),
              ('password', l10n.authPassword),
            ],
            onChanged: (value) => setState(() => _auth = value),
          ),
          if (_auth == 'password') ...[
            const _RowDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: TextField(
                controller: _password,
                obscureText: true,
                style: context.listTitleStyle,
                decoration: InputDecoration(
                  hintText: l10n.sshPasswordHint,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ],
          if (_auth == 'key' && _identities.isNotEmpty) ...[
            const _RowDivider(),
            SelectRow<String>(
              label: l10n.sshIdentity,
              value: _identity,
              options: [
                for (final key in _identities)
                  (key.id, key.builtin ? l10n.builtinKey : key.name),
              ],
              onChanged: (value) => setState(() => _identity = value),
            ),
          ],
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                _error,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: scheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: LoadingButton(
              label: l10n.connect,
              loading: _busy,
              onPressed:
                  (widget.backend.signedIn || widget.preview) &&
                      _userError.isEmpty &&
                      _portError.isEmpty
                  ? _connect
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 16),
      child: Divider(height: 0.5, thickness: 0.5),
    );
  }
}
