import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../l10n.dart';
import '../terminal_keys.dart';
import '../widgets/controls.dart';

/// Edits which keys each page of the terminal's extra key row shows.
Future<void> showTerminalKeysSheet(
  BuildContext context,
  TaildeckBackend backend,
) {
  return showFormSheet<void>(
    context: context,
    builder: (context) => _TerminalKeysSheet(backend: backend),
  );
}

class _TerminalKeysSheet extends StatefulWidget {
  const _TerminalKeysSheet({required this.backend});

  final TaildeckBackend backend;

  @override
  State<_TerminalKeysSheet> createState() => _TerminalKeysSheetState();
}

class _TerminalKeysSheetState extends State<_TerminalKeysSheet> {
  late List<List<String>> _pages = [
    for (final page in widget.backend.terminalKeyPages) [...page],
  ];
  int _page = 0;
  bool _blocked = false;

  List<String> _keysOn(int page) =>
      page < _pages.length ? _pages[page] : const [];

  bool get _modified => !listEquals(
    _signature(_pages),
    _signature(widget.backend.terminalKeyPages),
  );

  static List<String> _signature(List<List<String>> pages) => [
    for (final page in parseTerminalKeyPages(pages)) page.join(','),
  ];

  Future<void> _toggle(TerminalKey key) async {
    final pages = [
      for (final page in _pages) [...page],
    ];
    while (pages.length <= _page) {
      pages.add(<String>[]);
    }
    final current = pages[_page];
    var blocked = false;
    if (current.contains(key.id)) {
      current.remove(key.id);
    } else {
      for (final page in pages) {
        page.remove(key.id);
      }
      if (current.length >= maxKeysPerPage) {
        blocked = true;
      } else {
        current.add(key.id);
      }
    }
    setState(() {
      _pages = pages;
      _blocked = blocked;
    });
    if (blocked) return;
    await widget.backend.setTerminalKeyPages(pages);
  }

  Future<void> _reset() async {
    final pages = [
      for (final page in defaultTerminalKeyPages) [...page],
    ];
    setState(() {
      _pages = pages;
      _blocked = false;
    });
    await widget.backend.setTerminalKeyPages(pages);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = _keysOn(_page);
    final full = selected.length >= maxKeysPerPage;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.terminalKeyRow,
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
          const SizedBox(height: 6),
          Text(l10n.terminalKeysIntro, style: context.listCaptionStyle),
          const SizedBox(height: 16),
          SegmentedControl<int>(
            segments: [
              for (var page = 0; page < maxKeyPages; page++)
                (page, l10n.terminalKeyPage(page + 1)),
            ],
            value: _page,
            onChanged: (page) => setState(() {
              _page = page;
              _blocked = false;
            }),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final key in terminalKeyCatalog)
                        Chip(
                          label: key.kind == TerminalKeyKind.character
                              ? l10n.terminalKeyName(key.id)
                              : key.label,
                          selected: selected.contains(key.id),
                          onPressed: () => _toggle(key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    selected.isEmpty
                        ? l10n.terminalKeysEmptyPage
                        : _blocked && full
                        ? l10n.terminalKeysPageFull
                        : '',
                    style: context.listCaptionStyle,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (_modified)
                TextButton(
                  onPressed: _reset,
                  style: ButtonStyle.from(
                    foregroundColor: context.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                  child: Text(l10n.terminalKeysReset),
                ),
              const Spacer(),
              LoadingButton(
                label: l10n.submit,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
