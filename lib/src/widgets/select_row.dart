import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';

/// A card row that opens a popup menu of choices: the one select used for
/// every form value in the app.
class SelectRow<T> extends StatelessWidget {
  const SelectRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// A caption under the label, for what the choice means.
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final current = options.where((option) => option.$1 == value).firstOrNull;
    final shown = current?.$2 ?? '—';
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.listTitleStyle.copyWith(
                    color: enabled ? null : scheme.onSurfaceVariant,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: context.listCaptionStyle),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            shown,
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
    );
    final semantics = Semantics(
      container: true,
      button: true,
      label: '$label, $shown',
      hint: l10n.select,
      excludeSemantics: true,
      child: row,
    );
    if (!enabled) {
      return Opacity(opacity: 0.55, child: semantics);
    }
    return PopupAnchor(
      targetBuilder: (open) => PressRegion(
        onTap: open,
        overlay: PressRegion.pressOverlay,
        child: semantics,
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
