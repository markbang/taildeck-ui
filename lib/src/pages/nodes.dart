import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../data.dart';
import '../l10n.dart';
import '../glyphs.dart';
import '../widgets/controls.dart';
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
    final backend = BackendScope.of(context);
    final live = backend.available && backend.self != null;
    final self = live ? backend.self! : selfNode;
    final nodes = live ? backend.peers : peers;
    final online = nodes.where((node) => node.online).toList();
    return PageBody(
      title: live ? backend.tailnet : tailnet,
      trailing: IconButton(
        onPressed: onToggleTheme,
        icon: const GlyphIcon(Glyphs2.sun),
        tooltip: AppLocalizations.of(context).theme,
      ),
      children: [
        if (!backend.available && !kIsWeb) ...[
          InlineNotice(text: AppLocalizations.of(context).backendUnavailable),
          const SizedBox(height: 14),
        ],
        SearchField(
          hintText: AppLocalizations.of(context).searchNodes,
          fill: SurfaceLevel.card.colorOf(scheme),
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        Reveal(
          key: const ValueKey('self-card'),
          child: _SelfCard(node: self, peers: online, onOpenNode: onOpenNode),
        ),
        const SizedBox(height: 14),
        Reveal(
          key: const ValueKey('peer-list'),
          index: 1,
          child: AnimatedGroupCard(
            dividerInset: 60,
            children: [
              for (final node in nodes)
                _PeerRow(
                  key: ValueKey(node.name),
                  node: node,
                  onTap: () => onOpenNode(node),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelfCard extends StatelessWidget {
  const _SelfCard({
    required this.node,
    required this.peers,
    required this.onOpenNode,
  });

  final NodeItem node;
  final List<NodeItem> peers;
  final ValueChanged<NodeItem> onOpenNode;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Card(
      radius: AppCorner.xxl,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RowSemantics(
            label: AppLocalizations.of(context).nodeSemantics(
              node.name,
              online: node.online,
              ip: node.ip,
              direct: node.direct,
              relay: node.relay,
            ),
            child: Row(
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
                        AppLocalizations.of(context).thisDevice(node.ip),
                        style: context.listCaptionStyle,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: AppLocalizations.of(context).online,
                  tint: const Color(0xFF3BB273),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Column(
              children: [
                for (var i = 0; i < peers.length; i++)
                  RowSemantics(
                    label: AppLocalizations.of(context).nodeSemantics(
                      peers[i].name,
                      online: peers[i].online,
                      ip: peers[i].ip,
                      direct: peers[i].direct,
                      relay: peers[i].relay,
                    ),
                    onTap: () => onOpenNode(peers[i]),
                    child: TapFeedback(
                      onTap: () => onOpenNode(peers[i]),
                      child: SizedBox(
                        height: 44,
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
                            GlyphIcon(
                              Glyphs2.arrowDown,
                              size: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              peers[i].rx,
                              style: AppTextStyle.caption1
                                  .of(context)
                                  .copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
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
  const _PeerRow({super.key, required this.node, required this.onTap});

  final NodeItem node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final seenAt = node.online ? null : node.lastSeenAt;
    final seen = seenAt == null ? null : l10n.lastSeen(seenAt, now);
    final label = l10n.nodeSemantics(
      node.name,
      online: node.online,
      ip: node.ip,
      direct: node.direct,
      relay: node.relay,
      lastSeen: seenAt == null ? null : l10n.lastSeenSpoken(seenAt, now),
    );
    final caption = Text(
      seen == null ? node.ip : '${node.ip} · $seen',
      style: context.listCaptionStyle,
    );
    return RowSemantics(
      label: label,
      onTap: onTap,
      child: TapFeedback(
        onTap: onTap,
        child: Padding(
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
                    caption,
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
                    border: Border.all(
                      color: scheme.onSurfaceVariant.opacity50,
                      width: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
