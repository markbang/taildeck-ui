import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';
import '../l10n.dart';

typedef SshChoice = ({String user, int port});

Future<SshChoice?> showSshSheet(BuildContext context, NodeItem node) {
  return showFormSheet<SshChoice>(
    context: context,
    builder: (context) => _SshSheet(node: node),
  );
}

class _SshSheet extends StatefulWidget {
  const _SshSheet({required this.node});

  final NodeItem node;

  @override
  State<_SshSheet> createState() => _SshSheetState();
}

class _SshSheetState extends State<_SshSheet> {
  String _user = 'root';
  int _port = 22;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
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
                      l10n.ssh,
                      style: AppTextStyle.title2.of(context, emphasized: true),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.node.name} · ${widget.node.ip}',
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
                  label: l10n.sshUser,
                  value: _user,
                  options: const [
                    ('root', 'root'),
                    ('ubuntu', 'ubuntu'),
                    ('pi', 'pi'),
                  ],
                  onChanged: (value) => setState(() => _user = value),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(height: 0.5, thickness: 0.5),
                ),
                _SelectRow<int>(
                  label: l10n.sshPort,
                  value: _port,
                  options: const [
                    (22, '22'),
                    (2222, '2222'),
                    (2200, '2200'),
                  ],
                  onChanged: (value) => setState(() => _port = value),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(height: 0.5, thickness: 0.5),
                ),
                _SelectRow<String>(
                  label: l10n.sshAuth,
                  value: 'tailscale',
                  options: [
                    ('tailscale', l10n.authTailscale),
                    ('password', l10n.authPassword),
                    ('key', l10n.authKey),
                  ],
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              (user: _user, port: _port),
            ),
            child: Text(l10n.connect),
          ),
        ],
      ),
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
    final current = options.firstWhere((o) => o.$1 == value).$2;
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
                style: AppTextStyle.body
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
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
