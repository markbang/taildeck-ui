import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';
import '../glyphs.dart';
import '../widgets/foundation.dart';
import 'package:prism_ui/icons/icons.dart';

class AgentsPage extends StatelessWidget {
  const AgentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Agents',
      subtitle: 'herdr · devbox',
      trailing: IconButton(
        onPressed: () {},
        icon: const GlyphIcon(Glyphs2.plus),
        tooltip: 'New agent',
      ),
      children: [
        for (final group in agents) ...[
          SectionLabel(group.section),
          GroupCard(
            dividerInset: 56,
            children: [for (final agent in group.items) _AgentRow(agent: agent)],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent});

  final AgentItem agent;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final (label, tint) = switch (agent.state) {
      AgentState.working => ('Working', scheme.primary),
      AgentState.idle => ('Idle', scheme.onSurfaceVariant),
      AgentState.done => ('Done', const Color(0xFF3BB273)),
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
                  if (agent.task.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        agent.task,
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
