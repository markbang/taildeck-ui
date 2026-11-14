import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../data.dart';
import '../l10n.dart';
import '../glyphs.dart';
import '../service_open.dart';
import '../services.dart';
import '../webview/web_page.dart';
import '../widgets/controls.dart';
import '../widgets/foundation.dart';
import 'service_sheet.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  String _notice = '';
  String _deleting = '';

  Future<void> _addService(ServiceStore store, List<NodeItem> nodes) async {
    final service = await showServiceSheet(
      context,
      nodes: nodes,
      onSave: store.upsert,
    );
    if (service == null || !mounted) return;
    setState(() => _notice = AppLocalizations.of(context).serviceSaved);
  }

  Future<void> _editService(ServiceStore store, List<NodeItem> nodes, Service service) async {
    final edited = await showServiceSheet(
      context,
      nodes: nodes,
      initial: service,
      onSave: store.upsert,
    );
    if (edited == null || !mounted) return;
    setState(() => _notice = AppLocalizations.of(context).serviceSaved);
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
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = service.id);
    try {
      await store.remove(service.id);
      if (mounted) {
        setState(() => _notice = AppLocalizations.of(context).serviceDeleted);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) setState(() => _deleting = '');
    }
  }

  Future<void> _openService(Service service) async {
    final l10n = AppLocalizations.of(context);
    final fallback = BackendScope.of(context).openInApp && !inAppWebViewSupported;
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
        for (final (index, nodeName) in store.nodes.indexed) ...[
          Reveal(
            key: ValueKey('services-heading-$nodeName'),
            index: index,
            child: _NodeHeading(name: nodeName, node: byName[nodeName]),
          ),
          Reveal(
            key: ValueKey('services-card-$nodeName'),
            index: index,
            child: AnimatedGroupCard(
              dividerInset: 62,
              children: [
                for (final service in store.forNode(nodeName))
                  ServiceTile(
                    key: ValueKey(service.id),
                    service,
                    muted: byName[nodeName]?.online == false,
                    onPressed: _deleting == service.id
                        ? null
                        : () => unawaited(_openService(service)),
                    trailing: _deleting == service.id
                        ? const SizedBox.square(
                            dimension: 18,
                            child: ActivityIndicator(size: 18),
                          )
                        : PopupAnchor(
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
                                  onPressed: () => unawaited(
                                    _deleteService(store, service),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
              ],
            ),
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
