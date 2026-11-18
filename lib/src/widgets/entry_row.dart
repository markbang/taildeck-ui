import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';

/// A grouped form row whose value the user types: the label at the start,
/// the value editable inline at the end, as an iOS grouped form lays out a
/// text cell. Tapping anywhere on the row focuses the value.
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
    this.obscure = false,
    this.monospace = false,
    this.autofocus = false,
    this.suggestions = const [],
    this.autofillHints = const [],
    this.maxLines = 1,
    this.minLines,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Digits only, for a port or another bounded count.
  final bool numeric;
  final bool obscure;
  final bool monospace;
  final bool autofocus;

  /// Values offered in a popup; empty leaves a plain field.
  final List<String> suggestions;
  final List<String> autofillHints;

  /// Above one line the value moves under the label, full width.
  final int maxLines;
  final int? minLines;

  @override
  State<EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<EntryRow> {
  static final _digits = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(5),
  ];
  static const _labelMaxWidth = 160.0;

  late final _focus = FocusNode()..addListener(_handleFocus);
  bool _focused = false;

  void _handleFocus() {
    if (_focus.hasFocus != _focused) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

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
              if (value.toLowerCase().contains(typed))
                value
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
    final multiline = widget.maxLines > 1;
    final style = widget.monospace
        ? AppTextStyle.footnote
              .of(context)
              .copyWith(
                fontFamily: 'DejaVuSansMono',
                fontSize: 12,
                color: scheme.onSurface,
              )
        : context.listTitleStyle;
    final field = Semantics(
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
        focusNode: _focus,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        keyboardType: widget.numeric
            ? TextInputType.number
            : multiline
            ? TextInputType.multiline
            : null,
        inputFormatters: widget.numeric ? _digits : null,
        autocorrect: !widget.numeric && !widget.obscure && !widget.monospace,
        enableSuggestions:
            !widget.numeric && !widget.obscure && !widget.monospace,
        obscureText: widget.obscure,
        autofillHints: widget.autofillHints,
        maxLines: widget.maxLines,
        minLines: multiline ? (widget.minLines ?? widget.maxLines) : null,
        textAlign: multiline ? TextAlign.start : TextAlign.end,
        onChanged: widget.onChanged,
        style: style,
        decoration: InputDecoration.collapsed(
          hintText: widget.hintText,
          hintStyle: style.copyWith(color: scheme.onSurfaceVariant.opacity50),
        ),
      ),
    );
    final label = ExcludeSemantics(
      child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final error = widget.errorText;
    return DecorationListItem(
      contentPadding: EdgeInsets.only(left: 16, right: hasSuggestions ? 4 : 16),
      horizontalTitleGap: hasSuggestions ? 0 : null,
      title: multiline
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [label, const SizedBox(height: 8), field],
              ),
            )
          : Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _labelMaxWidth),
                  child: label,
                ),
                const SizedBox(width: 16),
                Expanded(child: field),
              ],
            ),
      subtitle: error == null
          ? null
          : Text(
              error,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: scheme.error),
            ),
      trailing: hasSuggestions ? _suggestions() : null,
      focused: _focused,
      onPressed: widget.enabled ? _focus.requestFocus : null,
    );
  }
}

/// The port typed in [text], or null when it is not 1–65535.
int? portValue(String text) {
  final port = int.tryParse(text.trim());
  return port == null || port < 1 || port > 65535 ? null : port;
}
