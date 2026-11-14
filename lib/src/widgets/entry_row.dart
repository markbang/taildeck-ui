import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';

/// A form row whose value the user types: a caption over a field.
///
/// With [suggestions] the row is a combobox — the field stays free text and
/// the chevron opens the values that repeat for it.
class EntryRow extends StatefulWidget {
  const EntryRow({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.errorText,
    this.onChanged,
    this.enabled = true,
    this.numeric = false,
    this.suggestions = const [],
    this.autofillHints = const [],
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Digits only, for a port or another bounded count.
  final bool numeric;

  /// Values offered in a popup; empty leaves a plain field.
  final List<String> suggestions;
  final List<String> autofillHints;
  final int maxLines;

  @override
  State<EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<EntryRow> {
  static final _digits = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(5),
  ];

  /// The anchor's open callback, so the field can offer it as an action.
  VoidCallback? _openSuggestions;

  void _pick(String value) {
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged?.call(value);
  }

  Widget _suggestions() {
    final l10n = AppLocalizations.of(context);
    return PopupAnchor(
      targetBuilder: (open) {
        _openSuggestions = open;
        return IconButton(
          onPressed: widget.enabled ? open : null,
          icon: const GlyphIcon(Glyphs.chevronDown),
          iconSize: 16,
          padding: EdgeInsets.zero,
          tooltip: l10n.suggestions,
        );
      },
      popupBuilder: (context) {
        final typed = widget.controller.text.trim().toLowerCase();
        // Filter while the user types; an exact value is not a filter.
        final filtering =
            typed.isNotEmpty &&
            !widget.suggestions.any((value) => value.toLowerCase() == typed);
        final shown = [
          if (filtering)
            for (final value in widget.suggestions)
              if (value.toLowerCase().contains(typed)) value
          else
            ...widget.suggestions,
        ];
        return PopupMenu(
          items: [
            for (final value in shown.isEmpty ? widget.suggestions : shown)
              PopupMenuItem(
                label: value,
                checked: value == widget.controller.text.trim(),
                onPressed: () => _pick(value),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final hasSuggestions = widget.suggestions.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: context.listCaptionStyle.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: widget.label,
            hint: hasSuggestions ? l10n.suggestions : null,
            customSemanticsActions: hasSuggestions && widget.enabled
                ? {
                    CustomSemanticsAction(label: l10n.suggestions): () =>
                        _openSuggestions?.call(),
                  }
                : null,
            child: TextField(
              controller: widget.controller,
              enabled: widget.enabled,
              keyboardType: widget.numeric ? TextInputType.number : null,
              inputFormatters: widget.numeric ? _digits : null,
              autocorrect: !widget.numeric,
              enableSuggestions: !widget.numeric,
              autofillHints: widget.autofillHints,
              maxLines: widget.maxLines,
              minLines: widget.maxLines > 1 ? widget.maxLines : null,
              onChanged: widget.onChanged,
              style: context.listTitleStyle,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: context.listCaptionStyle,
                errorText: widget.errorText,
                filled: true,
                fillColor: SurfaceLevel.block.colorOf(scheme),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                suffixIcon: hasSuggestions ? _suggestions() : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The port typed in [text], or null when it is not 1–65535.
int? portValue(String text) {
  final port = int.tryParse(text.trim());
  return port == null || port < 1 || port > 65535 ? null : port;
}
