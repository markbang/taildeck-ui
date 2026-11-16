import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';

/// A card row that picks one of [options] from a menu, as FlClash's option
/// rows do: the current value and a picker chevron at the row's end, the menu
/// opening out of the value, the selected item checked.
class SelectRow<T> extends StatefulWidget {
  const SelectRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.glyph,
    this.subtitle,
    this.enabled = true,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final Glyph? glyph;

  /// A caption under the label, for what the choice means.
  final String? subtitle;
  final bool enabled;

  @override
  State<SelectRow<T>> createState() => _SelectRowState<T>();
}

class _SelectRowState<T> extends State<SelectRow<T>> {
  /// Where the menu opens from, set by the anchor below.
  PopupOpen? _openMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final current = widget.options
        .where((option) => option.$1 == widget.value)
        .firstOrNull;
    final shown = current?.$2 ?? '—';
    final row = DecorationListItem(
      leading: widget.glyph == null ? null : GlyphIcon(widget.glyph!),
      title: Text(widget.label),
      subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
      onPressed: () => _openMenu?.call(),
      trailing: PopupAnchor(
        targetBuilder: (open) {
          _openMenu = open;
          return TextButton(
            onPressed: widget.enabled ? open : null,
            style: ButtonStyle.from(
              foregroundColor: scheme.onSurfaceVariant,
              textStyle: context.listTitleStyle,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: PopupValueText(
                    shown,
                    alignment: AlignmentDirectional.centerEnd,
                  ),
                ),
                const GlyphIcon(Glyphs.picker),
              ],
            ),
          );
        },
        popupBuilder: (_) => PopupMenu(
          items: [
            for (final (option, text) in widget.options)
              PopupMenuItem(
                label: text,
                checked: option == widget.value,
                onPressed: () => widget.onChanged(option),
              ),
          ],
        ),
      ),
    );
    if (!widget.enabled) {
      return Opacity(opacity: 0.55, child: row);
    }
    return Semantics(
      container: true,
      button: true,
      label: '${widget.label}, $shown',
      hint: l10n.select,
      excludeSemantics: true,
      child: row,
    );
  }
}
