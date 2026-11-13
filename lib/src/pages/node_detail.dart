import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../data.dart';
import '../l10n.dart';
import '../glyphs.dart';
import '../native/bridge.dart';
import '../services.dart';
import '../widgets/foundation.dart';
import 'service_sheet.dart';

class NodeDetailPage extends StatefulWidget {
  const NodeDetailPage({
    super.key,
    required this.node,
    required this.onBack,
    required this.onOpenAgents,
    required this.onOpenSsh,
  });

  final NodeItem node;
  final VoidCallback onBack;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenSsh;

  @override
  State<NodeDetailPage> createState() => _NodeDetailPageState();
}

class _NodeDetailPageState extends State<NodeDetailPage> {
  bool _pinging = false;
  PingResult? _ping;
  bool _scanning = false;
  List<int>? _ports;
  String _scanError = '';

  Future<void> _runPing() async {
    if (_pinging) return;
    final backend = BackendScope.of(context);
    if (!backend.available) return;
    setState(() {
      _pinging = true;
      _ping = null;
    });
    final result = await backend.ping(widget.node.ip);
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
    );
    if (service == null) return;
    await store.upsert(service);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final mono = AppTextStyle.body.of(context).copyWith(
      fontFamily: 'DejaVuSansMono',
      fontSize: 14.5,
      height: 1.5,
    );
    return PageBody(
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
              onPressed: _runPing,
            ),
            ActionPill(
              label: l10n.scanPorts,
              glyph: Glyphs2.radar,
              onPressed: _scan,
            ),
          ],
        ),
        if (_pinging || _ping != null) ...[
          const SizedBox(height: 10),
          _PingLabel(pinging: _pinging, result: _ping),
        ],
        if (_scanning || _ports != null || _scanError.isNotEmpty) ...[
          const SizedBox(height: 14),
          _ScanResult(
            scanning: _scanning,
            ports: _ports,
            error: _scanError,
            onAdd: (port) => unawaited(_addScanned(port)),
          ),
        ],
        const SizedBox(height: 14),
        PressRegion(
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
                    child: GlyphIcon(Glyphs2.agents, size: 22, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.agentsTitle,
                          style: AppTextStyle.body.of(context, emphasized: true),
                        ),
                        const SizedBox(height: 2),
                        Text(l10n.agentsSummary(4, 2), style: context.listCaptionStyle),
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
            if (node.expiry.isNotEmpty)
              _DetailRow(
                label: l10n.keyExpiry,
                child: Text(node.expiry, style: context.listTitleStyle),
              ),
            _DetailRow(label: l10n.traffic, child: TrafficLabel(node: node)),
          ],
        ),
      ],
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
          const ActivityIndicator(size: 16),
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
  const _PingLabel({required this.pinging, required this.result});

  final bool pinging;
  final PingResult? result;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final result = this.result;
    final String text;
    if (pinging || result == null) {
      text = l10n.pinging;
    } else if (!result.ok) {
      text = l10n.pingFailed(result.error ?? '');
    } else {
      final latency = result.latencyMs;
      final parts = [
        if (latency != null) '${latency.toStringAsFixed(1)} ms',
        if ((result.endpoint ?? '').isNotEmpty) result.endpoint!,
        if ((result.derp ?? '').isNotEmpty) 'DERP ${result.derp}',
      ];
      text = parts.join(' · ');
    }
    final failed = result != null && !pinging && !result.ok;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: AppTextStyle.footnote.of(context).copyWith(
          color: failed ? scheme.error : scheme.onSurfaceVariant,
        ),
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
            style: AppTextStyle.caption1.of(context).copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          child,
        ],
      ),
    );
  }
}
