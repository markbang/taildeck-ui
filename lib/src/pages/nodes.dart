import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';
import '../glyphs.dart';
import '../widgets/foundation.dart';

class NodesPage extends StatelessWidget {
  const NodesPage({
    super.key,
    required this.onOpenNode,
    required this.onToggleTheme,
  });

  final ValueChanged<NodeItem> onOpenNode;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final online = peers.where((node) => node.online).toList();
    return PageBody(
      title: tailnet,
      trailing: IconButton(
        onPressed: onToggleTheme,
        icon: const GlyphIcon(Glyphs2.sun),
        tooltip: 'Theme',
      ),
      children: [
        SearchField(
          hintText: 'Search nodes',
          fill: SurfaceLevel.card.colorOf(scheme),
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        _SelfCard(node: selfNode, peers: online),
        const SizedBox(height: 14),
        GroupCard(
          dividerInset: 60,
          children: [
            for (final node in peers)
              PressRegion(
                onTap: () => onOpenNode(node),
                child: _PeerRow(node: node),
              ),
          ],
        ),
      ],
    );
  }
}

class _SelfCard extends StatelessWidget {
  const _SelfCard({required this.node, required this.peers});

  final NodeItem node;
  final List<NodeItem> peers;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Card(
      radius: AppCorner.xxl,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NodeBadge(node, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: AppTextStyle.title3.of(context, emphasized: true),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'This device · ${node.ip}',
                      style: context.listCaptionStyle,
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: 'Online',
                tint: const Color(0xFF3BB273),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Column(
              children: [
                for (var i = 0; i < peers.length; i++)
                  PressRegion(
                    onTap: () {},
                    child: SizedBox(
                      height: 38,
                      child: Row(
                        children: [
                          Connector(isFirst: i == 0),
                          const SizedBox(width: 12),
                          Text(
                            peers[i].name,
                            style: AppTextStyle.subheadline
                                .of(context, emphasized: true),
                          ),
                          const Spacer(),
                          Text(
                            '↓ ${peers[i].rx}',
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.node});

  final NodeItem node;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          NodeBadge(node),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.name,
                  style: AppTextStyle.body.of(context, emphasized: true),
                ),
                const SizedBox(height: 1),
                Text(
                  node.online ? node.ip : '${node.ip} · Nov 5, 2026',
                  style: context.listCaptionStyle,
                ),
              ],
            ),
          ),
          if (node.online)
            PathBadge(node: node)
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.onSurfaceVariant.opacity50, width: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}
