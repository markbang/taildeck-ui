import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';


/// A card row that opens a popup menu of choices.
class SelectRow<T> extends StatelessWidget {
  const SelectRow({
    super.key,
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
    final current = options.where((o) => o.$1 == value).firstOrNull;
    return PopupAnchor(
      targetBuilder: (open) => PressRegion(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(child: Text(label, style: context.listTitleStyle)),
              Text(
                current?.$2 ?? '—',
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
