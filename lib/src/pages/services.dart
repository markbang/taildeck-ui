import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';
import '../glyphs.dart';
import '../widgets/foundation.dart';

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final nodes = <String>{for (final service in services) service.node};
    return PageBody(
      title: 'Services',
      trailing: IconButton(
        onPressed: () {},
        icon: const GlyphIcon(Glyphs2.plus),
        tooltip: 'Add service',
      ),
      children: [
        for (final nodeName in nodes) ...[
          _NodeHeading(name: nodeName),
          GroupCard(
            dividerInset: 62,
            children: [
              for (final service in services.where((s) => s.node == nodeName))
                ServiceTile(service),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _NodeHeading extends StatelessWidget {
  const _NodeHeading({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final node = [selfNode, ...peers].firstWhere(
      (item) => item.name == name,
      orElse: () => NodeItem(name: name, ip: '', os: 'Linux', online: true),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: Row(
      children: [
        Text(
          name,
          style: AppTextStyle.footnote
              .of(context, emphasized: true)
              .copyWith(color: context.colorScheme.onSurface),
        ),
        const SizedBox(width: 8),
        PathBadge(node: node, compact: true),
      ],
      ),
    );
  }
}
