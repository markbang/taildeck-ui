import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../terminal_appearance.dart';
import '../widgets/bottom_sheet.dart';
import '../widgets/foundation.dart';

/// The Compose sheet: a multiline field for a long command or an IME that
/// needs room. Sending writes the text through the terminal's send path, so
/// Enter follows it unless the user keeps insert-only on.
Future<String?> showTerminalComposeSheet(
  BuildContext context, {
  required TaildeckBackend backend,
  String initialText = '',
}) {
  return showMotionSheet<String>(
    context: context,
    builder: (context) =>
        _ComposeSheet(backend: backend, initialText: initialText),
  );
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.backend, required this.initialText});

  final TaildeckBackend backend;
  final String initialText;

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text;
    _text.clear();
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final backend = widget.backend;
    final palette = terminalPaletteOf(
      backend.terminalTheme,
      Theme.of(context).brightness,
    );
    final mono = TextStyle(
      fontFamily: terminalFontFamily(backend.terminalFont),
      fontFamilyFallback: terminalFontFallback,
      fontSize: 14,
      height: 1.5,
      color: palette.foreground,
      decoration: TextDecoration.none,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(Glyphs2.compose),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.terminalCompose,
                  style: AppTextStyle.title2.of(context, emphasized: true),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const GlyphIcon(Glyphs.close),
                tooltip: l10n.close,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 260),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: ShapeDecoration(
              color: palette.surface,
              shape: AppShape.all(12),
            ),
            child: TextField(
              controller: _text,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              cursorColor: palette.accent,
              style: mono,
              decoration: InputDecoration.collapsed(
                hintText: l10n.terminalComposeHint,
                hintStyle: mono.copyWith(
                  color: palette.dim.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Switch(
                      value: backend.terminalSendEnter,
                      semanticLabel: l10n.a11ySwitch(
                        l10n.snippetAppendEnter,
                        backend.terminalSendEnter,
                      ),
                      onChanged: (value) =>
                          backend.setTerminalSendEnter(value),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        backend.terminalSendEnter
                            ? l10n.terminalSendEnterOn
                            : l10n.terminalSendInsertOnly,
                        style: AppTextStyle.footnote.of(context).copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _send,
                child: Text(l10n.terminalSend),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
