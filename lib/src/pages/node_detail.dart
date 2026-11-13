import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';
import '../glyphs.dart';
import '../widgets/foundation.dart';

class NodeDetailPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final mono = AppTextStyle.body.of(context).copyWith(
      fontFamily: 'DejaVuSansMono',
      fontSize: 14.5,
      height: 1.5,
    );
    return PageBody(
      title: node.name,
      subtitle: '${node.os} · ${node.online ? 'Online' : 'Offline'}',
      leading: Padding(
        padding: const EdgeInsets.only(top: 6, right: 6),
        child: IconButton(
          onPressed: onBack,
          icon: const GlyphIcon(Glyphs.arrowBack),
          tooltip: 'Back',
        ),
      ),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionPill(
              label: 'SSH',
              glyph: Glyphs2.terminal,
              selected: true,
              onPressed: onOpenSsh,
            ),
            ActionPill(label: 'Web', glyph: Glyphs2.globe, onPressed: () {}),
            ActionPill(label: 'Ping', glyph: Glyphs2.ping, onPressed: () {}),
          ],
        ),
        const SizedBox(height: 14),
        PressRegion(
          onTap: onOpenAgents,
          shape: AppShape.all(AppCorner.xxl),
          child: Card(
            radius: AppCorner.xxl,
            onPressed: onOpenAgents,
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
                          'Agents',
                          style: AppTextStyle.body.of(context, emphasized: true),
                        ),
                        const SizedBox(height: 2),
                        Text('4 agents · 2 working', style: context.listCaptionStyle),
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
        SectionLabel('Details'),
        GroupCard(
          dividerInset: 0,
          children: [
            _DetailRow(
              label: 'Addresses',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.dns.isEmpty ? node.name : node.dns, style: mono),
                  const SizedBox(height: 2),
                  Text(node.ip, style: mono),
                  const SizedBox(height: 2),
                  Text('fd7a:115c:a1e0::9', style: mono),
                ],
              ),
            ),
            _DetailRow(label: 'Owner', child: Text(node.owner, style: context.listTitleStyle)),
            _DetailRow(
              label: 'Connection',
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: PathBadge(node: node),
              ),
            ),
            _DetailRow(
              label: 'Tags',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in (node.tags.isEmpty ? ['tag:dev'] : node.tags))
                    Chip(label: tag, onPressed: () {}),
                ],
              ),
            ),
            _DetailRow(label: 'Key expiry', child: Text(node.expiry, style: context.listTitleStyle)),
            _DetailRow(label: 'Traffic', child: TrafficLabel(node: node)),
          ],
        ),
      ],
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
