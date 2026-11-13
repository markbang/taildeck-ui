import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../data.dart';
import '../glyphs.dart';
import '../herdr.dart';
import '../l10n.dart';
import '../native/bridge.dart';
import '../ssh_identities.dart';
import '../widgets/foundation.dart';
import '../widgets/select_row.dart';
import 'agent_chat.dart';
import 'new_agent_sheet.dart';

class AgentsPage extends StatefulWidget {
  const AgentsPage({super.key});

  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  /// Demo list: the web preview and hosts without the shared library.
  late final List<({String section, List<AgentItem> items})> _demo = [
    for (final group in agents)
      (section: group.section, items: [...group.items]),
  ];
  String _notice = '';

  Future<void> _addDemoAgent() async {
    final choice = await showNewAgentSheet(context);
    if (choice == null || !mounted) return;
    setState(() {
      final index = _demo.indexWhere((g) => g.section == choice.project);
      final item = AgentItem(
        name: choice.harness,
        state: AgentState.idle,
        task: choice.task,
        project: choice.project,
        window: 'w1:p1',
      );
      if (index == -1) {
        _demo.add((section: choice.project, items: [item]));
      } else {
        _demo[index].items.add(item);
      }
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
    if (promptError.isNotEmpty) {
      setState(() => _notice = l10n.agentPromptFailed(promptError));
    }
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
    if (herdr == null) return _demoPage(l10n);
    return ListenableBuilder(
      listenable: herdr,
      builder: (context, _) => PageBody(
        title: l10n.agentsTitle,
        subtitle: herdr.node.isEmpty ? 'herdr' : 'herdr · ${herdr.node}',
        trailing: IconButton(
          onPressed: herdr.ready ? () => unawaited(_addAgent(herdr)) : null,
          icon: const GlyphIcon(Glyphs2.plus),
          tooltip: herdr.ready ? l10n.newAgent : l10n.herdrNotConnected,
        ),
        children: [
          if (!backend.signedIn) ...[
            InlineNotice(
              text: l10n.herdrNeedsNode,
              tint: context.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
          ],
          if (_notice.isNotEmpty) ...[
            InlineNotice(text: _notice, tint: context.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
          ],
          if (!herdr.ready) ...[
            _linkNotice(context, l10n, herdr),
            _HerdrConnectCard(backend: backend, herdr: herdr),
          ] else if (herdr.agents.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 24, 6, 8),
              child: Text(
                l10n.herdrNoAgents,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            ) else
          for (final group in _groups(herdr.agents))
            ...[
              SectionLabel(
                group.section == 'Needs you' ? l10n.needsYou : group.section,
              ),
              GroupCard(
                dividerInset: 56,
                children: [
                  for (final agent in group.items)
                    RowSemantics(
                      label: _liveAgentLabel(context, l10n, agent),
                      onTap: () => _openAgent(herdr, agent),
                      child: _LiveAgentRow(
                        agent: agent,
                        onTap: () => _openAgent(herdr, agent),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }

  Widget _linkNotice(
    BuildContext context,
    AppLocalizations l10n,
    HerdrController herdr,
  ) {
    final scheme = context.colorScheme;
    final text = switch (herdr.link) {
      HerdrLink.notInstalled => l10n.herdrNotInstalled,
      HerdrLink.notRunning => l10n.herdrNotRunning,
      HerdrLink.failed => herdr.detail,
      HerdrLink.idle when herdr.detail.isNotEmpty => l10n.herdrDropped,
      _ => '',
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineNotice(
            text: text,
            tint: herdr.link == HerdrLink.failed
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
          if (herdr.link == HerdrLink.notInstalled ||
              herdr.link == HerdrLink.notRunning)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Text(
                herdr.detail,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _demoPage(AppLocalizations l10n) {
    final scheme = context.colorScheme;
    return PageBody(
      title: l10n.agentsTitle,
      subtitle: 'herdr · devbox',
      trailing: IconButton(
        onPressed: () => unawaited(_addDemoAgent()),
        icon: const GlyphIcon(Glyphs2.plus),
        tooltip: l10n.newAgent,
      ),
      children: [
        InlineNotice(
          text: l10n.herdrNeedsBackend,
          tint: scheme.onSurfaceVariant,
        ),
        const SizedBox(height: 6),
        for (final group in _demo) ...[
          SectionLabel(
            group.section == 'Needs you' ? l10n.needsYou : group.section,
          ),
          GroupCard(
            dividerInset: 56,
            children: [
              for (final agent in group.items)
                RowSemantics(
                  label: _demoAgentLabel(l10n, agent),
                  child: _DemoAgentRow(agent: agent),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  static List<({String section, List<HerdrAgent> items})> _groups(
    List<HerdrAgent> all,
  ) {
    final needsYou = [
      for (final agent in all)
        if (agent.status == HerdrStatus.blocked || agent.status == HerdrStatus.done)
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

String _demoAgentLabel(AppLocalizations l10n, AgentItem agent) =>
    l10n.agentSemantics(agent.project, agent.name, switch (agent.state) {
      AgentState.working => l10n.working,
      AgentState.idle => l10n.idle,
      AgentState.done => l10n.done,
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
    return PressRegion(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: scheme.onSurface.withValues(alpha: 0.12),
                shape: AppShape.all(10),
              ),
              child: Text(
                agent.label.characters.first.toUpperCase(),
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(color: scheme.onSurfaceVariant),
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
                          style: AppTextStyle.body.of(context, emphasized: true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusPill(label: label, tint: tint),
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

  final AgentItem agent;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final (label, tint) = switch (agent.state) {
      AgentState.working => (l10n.working, scheme.primary),
      AgentState.idle => (l10n.idle, scheme.onSurfaceVariant),
      AgentState.done => (l10n.done, const Color(0xFF3BB273)),
    };
    final task = switch (agent.demoTask) {
      DemoTask.grafanaAlerts => l10n.demoTaskGrafana,
      DemoTask.releaseWorkflow => l10n.demoTaskRelease,
      DemoTask.headscaleBump => l10n.demoTaskHeadscale,
      null => agent.task,
    };
    return PressRegion(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: scheme.onSurface.withValues(alpha: 0.12),
                shape: AppShape.all(10),
              ),
              child: Text(
                agent.name.characters.first.toUpperCase(),
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(color: scheme.onSurfaceVariant),
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
                      StatusPill(label: label, tint: tint),
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

/// Node, user and credentials for the herdr connection, prefilled from the
/// last successful one.
class _HerdrConnectCard extends StatefulWidget {
  const _HerdrConnectCard({required this.backend, required this.herdr});

  final TaildeckBackend backend;
  final HerdrController herdr;

  @override
  State<_HerdrConnectCard> createState() => _HerdrConnectCardState();
}

class _HerdrConnectCardState extends State<_HerdrConnectCard> {
  late String _node = widget.backend.herdrTarget.node;
  late String _user = widget.backend.herdrTarget.user;
  late int _port = widget.backend.herdrTarget.port;
  late String _auth = widget.backend.herdrTarget.auth;
  late String _identity = widget.backend.herdrTarget.identity;
  final _password = TextEditingController();
  final _nodeInput = TextEditingController();
  List<SshIdentity> _identities = const [];
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.backend.available) unawaited(_loadKeys());
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
    _password.dispose();
    _nodeInput.dispose();
    super.dispose();
  }

  String get _defaultNode {
    final nodes = widget.backend.nodes;
    final self = widget.backend.self?.name;
    for (final node in nodes) {
      if (node.name != self) return node.name;
    }
    return nodes.isEmpty ? '' : nodes.first.name;
  }

  Future<void> _connect() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final node = _node.isNotEmpty
        ? _node
        : (_defaultNode.isNotEmpty ? _defaultNode : _nodeInput.text.trim());
    if (node.isEmpty) {
      setState(() => _error = l10n.serviceNode);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.backend.connectHerdr(
        node: node,
        user: _user,
        port: _port,
        auth: _auth,
        identityId: _identity,
        password: _password.text,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is BridgeException ? error.message : '$error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final nodes = widget.backend.nodes;
    final names = [for (final node in nodes) (node.name, node.name)];
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
          SelectRow<String>(
            label: l10n.sshUser,
            value: _user,
            options: const [('root', 'root'), ('ubuntu', 'ubuntu'), ('pi', 'pi')],
            onChanged: (value) => setState(() => _user = value),
          ),
          const _RowDivider(),
          SelectRow<int>(
            label: l10n.sshPort,
            value: _port,
            options: const [(22, '22'), (2222, '2222'), (2200, '2200')],
            onChanged: (value) => setState(() => _port = value),
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
            child: FilledButton(
              onPressed: _busy || !widget.backend.signedIn ? null : _connect,
              child: Text(_busy ? l10n.connecting : l10n.connect),
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
