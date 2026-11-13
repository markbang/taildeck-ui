import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend.dart';
import '../data.dart';
import '../l10n.dart';
import '../glyphs.dart';
import '../services.dart';
import '../widgets/foundation.dart';
import 'service_sheet.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  String _notice = '';

  Future<void> _addService(ServiceStore store, List<NodeItem> nodes) async {
    final service = await showServiceSheet(context, nodes: nodes);
    if (service == null) return;
    await store.upsert(service);
  }

  Future<void> _editService(ServiceStore store, List<NodeItem> nodes, Service service) async {
    final edited = await showServiceSheet(
      context,
      nodes: nodes,
      initial: service,
    );
    if (edited == null) return;
    await store.upsert(edited);
  }

  Future<void> _deleteService(ServiceStore store, Service service) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: AlertDialog(
        title: l10n.deleteService,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
        child: Text(l10n.deleteServiceBody(service.name)),
      ),
    );
    if (confirmed == true) await store.remove(service.id);
  }

  Future<void> _openService(Service service) async {
    final backend = BackendScope.of(context);
    final l10n = AppLocalizations.of(context);
    final url = gatewayUrl(service, backend.gatewayPort);
    if (url == null) {
      setState(() => _notice = l10n.serviceNeedsGateway);
      return;
    }
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) setState(() => _notice = l10n.serviceOpenFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = ServicesScope.of(context);
    final backend = BackendScope.of(context);
    final nodes = backend.available ? backend.nodes : [selfNode, ...peers];
    final byName = {for (final node in nodes) node.name: node};
    return PageBody(
      title: l10n.tabServices,
      trailing: IconButton(
        onPressed: () => unawaited(_addService(store, nodes)),
        icon: const GlyphIcon(Glyphs2.plus),
        tooltip: l10n.addService,
      ),
      children: [
        if (_notice.isNotEmpty) ...[
          InlineNotice(
            text: _notice,
            tint: context.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
        ],
        if (store.all.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 24, 6, 8),
            child: Text(
              l10n.noServicesAll,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ),
        for (final nodeName in store.nodes) ...[
          _NodeHeading(name: nodeName, node: byName[nodeName]),
          GroupCard(
            dividerInset: 62,
            children: [
              for (final service in store.forNode(nodeName))
                ServiceTile(
                  service,
                  muted: byName[nodeName]?.online == false,
                  onPressed: () => unawaited(_openService(service)),
                  trailing: PopupAnchor(
                    targetBuilder: (open) => IconButton(
                      onPressed: open,
                      icon: const GlyphIcon(Glyphs.more),
                      tooltip: l10n.more,
                    ),
                    popupBuilder: (context) => PopupMenu(
                      items: [
                        PopupMenuItem(
                          label: l10n.edit,
                          glyph: Glyphs2.sliders,
                          onPressed: () => unawaited(
                            _editService(store, nodes, service),
                          ),
                        ),
                        PopupMenuItem(
                          label: l10n.delete,
                          danger: true,
                          onPressed: () =>
                              unawaited(_deleteService(store, service)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _NodeHeading extends StatelessWidget {
  const _NodeHeading({required this.name, this.node});

  final String name;
  final NodeItem? node;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final node = this.node;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: Row(
        children: [
          Text(
            name,
            style: AppTextStyle.footnote.of(context, emphasized: true).copyWith(
              color: node?.online == false
                  ? scheme.onSurfaceVariant
                  : scheme.onSurface,
            ),
          ),
          if (node != null) ...[
            const SizedBox(width: 8),
            PathBadge(node: node, compact: true),
          ],
        ],
      ),
    );
  }
}
