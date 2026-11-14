import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../data.dart';
import '../l10n.dart';
import '../glyphs.dart';
import '../herdr.dart';
import '../motion.dart';
import '../native/bridge.dart';
import '../service_open.dart';
import '../services.dart';
import '../terminal_store.dart';
import '../webview/web_page.dart';
import '../widgets/controls.dart';
import '../widgets/foundation.dart';
import '../widgets/shape_badge.dart';
import 'service_sheet.dart';
import '../widgets/loading.dart';

class NodeDetailPage extends StatefulWidget {
  const NodeDetailPage({
    super.key,
    required this.node,
    required this.onBack,
    required this.onOpenAgents,
    required this.onOpenSsh,
    this.session,
    this.onDisconnectSsh,
    this.previewPing = false,
  });

  final NodeItem node;
  final VoidCallback onBack;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenSsh;

  /// A shell still running on this node, left open by the terminal page.
  final SshTerminal? session;
  final VoidCallback? onDisconnectSsh;

  /// `?ping=1` runs the Ping button on open, so the Android smoke test can
  /// exercise the FFI path without tapping through uiautomator.
  final bool previewPing;

  @override
  State<NodeDetailPage> createState() => _NodeDetailPageState();
}

class _NodeDetailPageState extends State<NodeDetailPage> {
  final _focus = FocusNode(debugLabel: 'node detail');
  bool _pinging = false;
  TaildeckBackend? _backend;

  @override
  void initState() {
    super.initState();
    // Takes focus on open, so Esc leaves the page before a click.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        if (widget.previewPing) unawaited(_runPing(fromPreview: true));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backend = BackendScope.of(context);
  }

  @override
  void dispose() {
    // Leaving the page frees the node instead of waiting out the ping timeout.
    _backend?.pingCancel(widget.node.ip);
    _focus.dispose();
    super.dispose();
  }

  PingResult? _ping;
  bool _scanning = false;
  List<int>? _ports;
  String _scanError = '';
  String _notice = '';

  Future<void> _openService(Service service) async {
    final l10n = AppLocalizations.of(context);
    final fallback =
        BackendScope.of(context).openInApp && !inAppWebViewSupported;
    final result = await openService(context, service);
    if (!mounted) return;
    setState(() {
      _notice = switch (result) {
        ServiceOpen.needsGateway =>
          fallback ? l10n.inAppDesktopOnlyNoGateway : l10n.serviceNeedsGateway,
        ServiceOpen.openFailed => l10n.serviceOpenFailed,
        ServiceOpen.fallbackToBrowser => l10n.inAppDesktopOnly,
        _ => '',
      };
    });
  }

  Future<void> _runPing({bool fromPreview = false}) async {
    if (_pinging) return;
    final backend = _backend ?? BackendScope.of(context);
    if (!backend.available) return;
    setState(() {
      _pinging = true;
      _ping = null;
    });
    if (fromPreview) debugPrint('taildeck ping: start ${widget.node.ip}');
    final result = fromPreview
        ? await backend.previewPing(widget.node.ip)
        : await backend.ping(widget.node.ip);
    if (fromPreview) {
      final answer = result.ok
          ? 'ok ${result.latencyMs?.round()}ms '
                '${(result.derp ?? '').isEmpty ? 'direct' : 'derp ${result.derp}'}'
          : 'failed ${result.error}';
      debugPrint('taildeck ping: done $answer');
    }
    if (!mounted) return;
    setState(() {
      _pinging = false;
      _ping = result;
    });
  }

  Future<void> _scan() async {
    if (_scanning) return;
    final l10n = AppLocalizations.of(context);
    final backend = BackendScope.of(context);
    if (!widget.node.online) {
      setState(() {
        _ports = null;
        _scanError = l10n.scanOffline;
      });
      return;
    }
    if (!backend.available) {
      setState(() {
        _ports = null;
        _scanError = l10n.scanNeedsBackend;
      });
      return;
    }
    if (!backend.signedIn) {
      setState(() {
        _ports = null;
        _scanError = l10n.nodeNotRunning;
      });
      return;
    }
    setState(() {
      _scanning = true;
      _ports = null;
      _scanError = '';
    });
    try {
      final ports = await backend.probe(widget.node.name, commonPorts);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _ports = ports;
      });
    } on BridgeException catch (error) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanError = l10n.scanFailed(error.message);
      });
    }
  }

  Future<void> _addScanned(int port) async {
    final store = ServicesScope.of(context);
    final service = await showServiceSheet(
      context,
      nodes: [widget.node],
      initialNode: widget.node.name,
      initialPort: port,
      onSave: store.upsert,
    );
    if (service == null || !mounted) return;
    setState(() => _notice = AppLocalizations.of(context).serviceSaved);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final services = ServicesScope.of(context).forNode(node.name);
    final mono = AppTextStyle.body
        .of(context)
        .copyWith(fontFamily: 'DejaVuSansMono', fontSize: 14.5, height: 1.5);
    final body = PageBody(
      title: node.name,
      subtitle: '${node.os} · ${node.online ? l10n.online : l10n.offline}',
      leading: Padding(
        padding: const EdgeInsets.only(top: 6, right: 6),
        child: IconButton(
          onPressed: widget.onBack,
          icon: const GlyphIcon(Glyphs.arrowBack),
          tooltip: l10n.back,
        ),
      ),
      children: [
        Focus(focusNode: _focus, child: const SizedBox.shrink()),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionPill(
              label: l10n.ssh,
              glyph: Glyphs2.terminal,
              selected: true,
              onPressed: widget.onOpenSsh,
            ),
            ActionPill(label: l10n.web, glyph: Glyphs2.globe, onPressed: () {}),
            ActionPill(
              label: l10n.ping,
              glyph: Glyphs2.ping,
              onPressed: () => unawaited(_runPing()),
              loading: _pinging,
            ),
            ActionPill(
              label: l10n.scanPorts,
              glyph: Glyphs2.radar,
              onPressed: _scan,
              loading: _scanning,
            ),
          ],
        ),
        if (widget.session case final session?) ...[
          const SizedBox(height: 12),
          _SessionCard(
            session: session,
            onResume: widget.onOpenSsh,
            onDisconnect: widget.onDisconnectSsh,
          ),
        ],
        if (_notice.isNotEmpty) ...[
          const SizedBox(height: 12),
          InlineNotice(text: _notice, tint: scheme.onSurfaceVariant),
        ],
        Builder(
          builder: (context) {
            final herdr = BackendScope.of(context).herdr;
            if (herdr == null) return const SizedBox.shrink();
            return ListenableBuilder(
              listenable: herdr,
              builder: (context, _) => _HerdrSummary(
                herdr: herdr,
                node: node.name,
                onOpen: widget.onOpenAgents,
              ),
            );
          },
        ),
        ExpandVisibility(
          visible: _pinging || _ping != null,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _PingLabel(
              pinging: _pinging,
              result: _ping,
              onRetry: () => unawaited(_runPing()),
            ),
          ),
        ),
        // The scan block joins the list as Kotlin's `animateItem()` row does,
        // and resizes with `animateContentSize(Motion.slow())`.
        PlacementVisibility(
          visible: _scanning || _ports != null || _scanError.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: AnimatedContentSize(
              child: _ScanResult(
                scanning: _scanning,
                ports: _ports,
                error: _scanError,
                onAdd: (port) => unawaited(_addScanned(port)),
              ),
            ),
          ),
        ),
        if (services.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionLabel(l10n.tabServices),
          GroupCard(
            dividerInset: 62,
            children: [
              for (final service in services)
                ServiceTile(
                  service,
                  muted: !node.online,
                  onPressed: () => unawaited(_openService(service)),
                  trailing: GlyphIcon(
                    Glyphs2.globe,
                    size: 18,
                    color: scheme.onSurfaceVariant.opacity50,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        TapFeedback(
          onTap: widget.onOpenAgents,
          shape: AppShape.all(AppCorner.xxl),
          child: Card(
            radius: AppCorner.xxl,
            onPressed: widget.onOpenAgents,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: scheme.primary.withValues(alpha: 0.16),
                      shape: AppShape.all(14),
                    ),
                    child: GlyphIcon(
                      Glyphs2.agents,
                      size: 22,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.agentsTitle,
                          style: AppTextStyle.body.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.agentsSummary(4, 2),
                          style: context.listCaptionStyle,
                        ),
                      ],
                    ),
                  ),
                  GlyphIcon(
                    Glyphs.chevronForward,
                    size: 16,
                    color: scheme.onSurfaceVariant.opacity50,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        SectionLabel(l10n.details),
        GroupCard(
          dividerInset: 0,
          children: [
            _DetailRow(
              label: l10n.addresses,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (node.dns.isNotEmpty) ...[
                    Text(node.dns, style: mono),
                    const SizedBox(height: 2),
                  ],
                  for (final ip in node.addresses) ...[
                    Text(ip, style: mono),
                    const SizedBox(height: 2),
                  ],
                ],
              ),
            ),
            _DetailRow(
              label: l10n.owner,
              child: Text(
                node.owner.isEmpty ? '—' : node.owner,
                style: context.listTitleStyle,
              ),
            ),
            _DetailRow(
              label: l10n.connection,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: PathBadge(node: node),
              ),
            ),
            _DetailRow(
              label: l10n.tags,
              child: node.tags.isEmpty
                  ? Text('—', style: context.listTitleStyle)
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in node.tags)
                          Chip(label: tag, onPressed: () {}),
                      ],
                    ),
            ),
            if (node.expiryAt case final expiry?)
              _DetailRow(
                label: l10n.keyExpiry,
                child: Text(
                  l10n.shortDate(expiry.toLocal()),
                  style: context.listTitleStyle,
                ),
              ),
            _DetailRow(
              label: l10n.traffic,
              child: TrafficLabel(node: node),
            ),
          ],
        ),
      ],
    );
    return Reveal(key: ValueKey('node-${node.name}'), child: body);
  }
}

/// The SSH shell keeps running after its page closes; this reopens it.
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onResume,
    required this.onDisconnect,
  });

  final SshTerminal session;
  final VoidCallback onResume;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Card(
      radius: AppCorner.xxl,
      onPressed: onResume,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                shape: AppShape.all(12),
              ),
              child: GlyphIcon(
                Glyphs2.terminal,
                size: 20,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sshSessionRunning,
                    style: AppTextStyle.body.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${session.user}@${session.node.name}:${session.port}',
                    style: context.listCaptionStyle,
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onResume, child: Text(l10n.resume)),
            IconButton(
              onPressed: onDisconnect,
              icon: const GlyphIcon(Glyphs.close, size: 18),
              tooltip: l10n.disconnect,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanResult extends StatelessWidget {
  const _ScanResult({
    required this.scanning,
    required this.ports,
    required this.error,
    required this.onAdd,
  });

  final bool scanning;
  final List<int>? ports;
  final String error;
  final ValueChanged<int> onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final ports = this.ports;
    if (scanning) {
      return Row(
        children: [
          const SizedBox(width: 4),
          const LoadingIndicator(size: 16),
          const SizedBox(width: 10),
          Text(
            l10n.scanning,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }
    if (error.isNotEmpty) return InlineNotice(text: error);
    if (ports == null || ports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          l10n.scanNone,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l10n.scanFound(ports.length)),
        GroupCard(
          dividerInset: 0,
          children: [
            for (final port in ports)
              ListRow(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                title: Text(
                  '$port',
                  style: AppTextStyle.body
                      .of(context, emphasized: true)
                      .copyWith(fontFamily: 'DejaVuSansMono'),
                ),
                subtitle: Text(
                  httpsPorts.contains(port) ? 'https' : 'http',
                  style: context.listCaptionStyle,
                ),
                trailing: IconButton(
                  onPressed: () => onAdd(port),
                  icon: const GlyphIcon(Glyphs2.plus),
                  tooltip: l10n.addService,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PingLabel extends StatelessWidget {
  const _PingLabel({
    required this.pinging,
    required this.result,
    required this.onRetry,
  });

  final bool pinging;
  final PingResult? result;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final result = this.result;
    final failed = result != null && !pinging && !result.ok;
    final String text;
    if (pinging || result == null) {
      text = l10n.pinging;
    } else if (failed) {
      text = l10n.pingFailed(result.error ?? '');
    } else {
      final latency = result.latencyMs;
      final derp = result.derp ?? '';
      // A disco ping reports an endpoint for direct UDP and a region code when
      // it had to go through DERP.
      final endpoint = result.endpoint ?? '';
      final path = derp.isNotEmpty
          ? l10n.pingRelay(derp)
          : endpoint.isNotEmpty
          ? '${l10n.pingDirect} · $endpoint'
          : '';
      text = [
        if (latency != null) '${latency.toStringAsFixed(1)} ms',
        if (path.isNotEmpty) path,
      ].join(' · ');
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Flexible(
            child: FadeThrough(
              child: Text(
                key: ValueKey(text),
                text,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      color: failed ? scheme.error : scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          if (failed) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 5),
          child,
        ],
      ),
    );
  }
}

/// The herdr card on the node page: how many agents are out, who is blocked,
/// and a badge that spins while one of them works (Kotlin's `HerdrSummary`).
class _HerdrSummary extends StatelessWidget {
  const _HerdrSummary({
    required this.herdr,
    required this.node,
    required this.onOpen,
  });

  final HerdrController herdr;
  final String node;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final agents = herdr.ready && herdr.node == node
        ? herdr.agents
        : const <HerdrAgent>[];
    final blocked = agents.where((a) => a.status == HerdrStatus.blocked).length;
    final working = agents.where((a) => a.status == HerdrStatus.working).length;
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final tint = blocked > 0 ? scheme.tertiary : scheme.secondary;
    return MotionVisibility(
      visible: agents.isNotEmpty,
      expand: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TapFeedback(
          onTap: onOpen,
          shape: AppShape.all(AppCorner.xl),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: ShapeDecoration(
              color: blocked > 0
                  ? scheme.tertiaryContainer
                  : scheme.secondaryContainer,
              shape: AppShape.all(AppCorner.xl),
            ),
            child: Row(
              children: [
                ShapeBadge(
                  shape: blocked > 0 ? BlobShape.softBurst : BlobShape.cookie9,
                  color: tint.withValues(alpha: 0.18),
                  size: 44,
                  spin: working > 0,
                  child: GlyphIcon(
                    Glyphs2.agents,
                    size: 20,
                    color: blocked > 0
                        ? scheme.onTertiaryContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.agentsTitle,
                        style: AppTextStyle.body
                            .of(context, emphasized: true)
                            .copyWith(
                              color: blocked > 0
                                  ? scheme.onTertiaryContainer
                                  : scheme.onSecondaryContainer,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          l10n.agentsCount(agents.length),
                          if (working > 0) l10n.agentsWorkingCount(working),
                          if (blocked > 0) l10n.agentsBlockedCount(blocked),
                        ].join(' · '),
                        style: AppTextStyle.caption1
                            .of(context)
                            .copyWith(
                              color: blocked > 0
                                  ? scheme.onTertiaryContainer
                                  : scheme.onSecondaryContainer,
                            ),
                      ),
                    ],
                  ),
                ),
                GlyphIcon(
                  Glyphs.chevronForward,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
