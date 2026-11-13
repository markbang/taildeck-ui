import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';
import '../l10n.dart';
import '../services.dart';

/// Adds a service, or edits [initial]. Returns null when dismissed.
Future<Service?> showServiceSheet(
  BuildContext context, {
  required List<NodeItem> nodes,
  Service? initial,
  String? initialNode,
  int? initialPort,
}) {
  return showFormSheet<Service>(
    context: context,
    builder: (context) => _ServiceSheet(
      nodes: nodes,
      initial: initial,
      initialNode: initialNode,
      initialPort: initialPort,
    ),
  );
}

class _ServiceSheet extends StatefulWidget {
  const _ServiceSheet({
    required this.nodes,
    this.initial,
    this.initialNode,
    this.initialPort,
  });

  final List<NodeItem> nodes;
  final Service? initial;
  final String? initialNode;
  final int? initialPort;

  @override
  State<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<_ServiceSheet> {
  late List<String> _nodes;
  late String _node;
  late String _scheme;
  late final TextEditingController _name;
  late final TextEditingController _port;
  late final TextEditingController _path;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final seedPort = widget.initialPort;
    _nodes = [for (final node in widget.nodes) node.name];
    _node = initial?.node ?? widget.initialNode ?? _firstNode();
    if (!_nodes.contains(_node) && _node.isNotEmpty) _nodes.insert(0, _node);
    _scheme =
        initial?.scheme ??
        (seedPort != null && httpsPorts.contains(seedPort) ? 'https' : 'http');
    _name = TextEditingController(text: initial?.name ?? '');
    _port = TextEditingController(
      text: initial == null
          ? (seedPort?.toString() ?? '')
          : initial.port.toString(),
    );
    _path = TextEditingController(text: initial == null ? '/' : _pathOf(initial));
  }

  String _firstNode() {
    for (final node in widget.nodes) {
      if (node.online && !node.isSelf) return node.name;
    }
    for (final node in widget.nodes) {
      if (node.online) return node.name;
    }
    return widget.nodes.isEmpty ? '' : widget.nodes.first.name;
  }

  static String _pathOf(Service service) {
    final uri = service.uri;
    if (uri == null) return '/';
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }

  @override
  void dispose() {
    _name.dispose();
    _port.dispose();
    _path.dispose();
    super.dispose();
  }

  int? get _parsedPort {
    final value = int.tryParse(_port.text.trim());
    return value != null && value >= 1 && value <= 65535 ? value : null;
  }

  void _save() {
    final port = _parsedPort;
    if (port == null || _node.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      Service(
        id: widget.initial?.id ?? ServiceStore.newId(),
        node: _node,
        name: _name.text.trim().isEmpty ? '$port' : _name.text.trim(),
        url: serviceUrl(
          node: _node,
          scheme: _scheme,
          port: port,
          path: _path.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final editing = widget.initial != null;
    final portText = _port.text.trim();
    final portError = portText.isNotEmpty && _parsedPort == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing ? l10n.editService : l10n.addService,
                        style: AppTextStyle.title2.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _node,
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const GlyphIcon(Glyphs.close),
                  tooltip: l10n.close,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              radius: AppCorner.xl,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SelectRow<String>(
                    label: l10n.serviceNode,
                    value: _node,
                    options: [for (final node in _nodes) (node, node)],
                    onChanged: (value) => setState(() => _node = value),
                  ),
                  const _RowDivider(),
                  _FieldRow(
                    label: l10n.serviceName,
                    controller: _name,
                    hintText: l10n.serviceNameHint,
                  ),
                  const _RowDivider(),
                  _SelectRow<String>(
                    label: l10n.serviceScheme,
                    value: _scheme,
                    options: const [('http', 'http'), ('https', 'https')],
                    onChanged: (value) => setState(() => _scheme = value),
                  ),
                  const _RowDivider(),
                  _FieldRow(
                    label: l10n.servicePort,
                    controller: _port,
                    hintText: '3000',
                    number: true,
                    errorText: portError ? l10n.servicePortInvalid : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const _RowDivider(),
                  _FieldRow(
                    label: l10n.servicePath,
                    controller: _path,
                    hintText: l10n.servicePathHint,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _parsedPort == null || _node.isEmpty ? null : _save,
              child: Text(l10n.save),
            ),
          ],
        ),
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

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.controller,
    this.hintText,
    this.number = false,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool number;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.listCaptionStyle.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            inputFormatters: number ? const [_Digits()] : null,
            onChanged: onChanged,
            style: context.listTitleStyle,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: context.listCaptionStyle,
              errorText: errorText,
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
    );
  }
}

class _Digits extends TextInputFormatter {
  const _Digits();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final text = digits.length > 5 ? digits.substring(0, 5) : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _SelectRow<T> extends StatelessWidget {
  const _SelectRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final current = options
        .firstWhere(
          (option) => option.$1 == value,
          orElse: () => (value, '$value'),
        )
        .$2;
    return PopupAnchor(
      targetBuilder: (open) => PressRegion(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(child: Text(label, style: context.listTitleStyle)),
              Text(
                current,
                style: AppTextStyle.body.of(
                  context,
                ).copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              GlyphIcon(
                Glyphs.chevronDown,
                size: 14,
                color: scheme.onSurfaceVariant.opacity50,
              ),
            ],
          ),
        ),
      ),
      popupBuilder: (context) => PopupMenu(
        items: [
          for (final (option, text) in options)
            PopupMenuItem(
              label: text,
              checked: option == value,
              onPressed: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}
