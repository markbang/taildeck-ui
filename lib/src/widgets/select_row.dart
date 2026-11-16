import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';
import 'select_value_button.dart';

/// A card row that picks one of [options] from a menu, as FlClash's
/// `ListItem.options` rows do: the current value and a picker glyph at the
/// row's end, the menu opening out of that value and returning into it.
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
    final l10n = AppLocalizations.of(context);
    final current = widget.options
        .where((option) => option.$1 == widget.value)
        .firstOrNull;
    final shown = current?.$2 ?? '—';
    final row = DecorationListItem(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      leading: widget.glyph == null ? null : GlyphIcon(widget.glyph!),
      title: Text(widget.label),
      subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
      onPressed: () => _openMenu?.call(),
      trailing: PopupAnchor(
        targetBuilder: (open) {
          _openMenu = open;
          return SelectValueButton(
            label: shown,
            onPressed: widget.enabled ? open : null,
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
