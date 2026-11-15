import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../terminal_snippets.dart';
import '../widgets/bottom_sheet.dart';
import '../widgets/controls.dart';
import '../widgets/entry_row.dart';
import '../widgets/foundation.dart';
import '../widgets/select_row.dart';

/// The snippet drawer: tap a row to send it into the terminal, or open one to
/// edit it. Without [onSend] the rows open the editor instead, which is what
/// Settings shows.
Future<void> showTerminalSnippetsSheet(
  BuildContext context, {
  required TaildeckBackend backend,
  ValueChanged<TerminalSnippet>? onSend,
}) {
  return showMotionSheet<void>(
    context: context,
    builder: (context) =>
        _SnippetsSheet(backend: backend, onSend: onSend),
  );
}

class _SnippetsSheet extends StatefulWidget {
  const _SnippetsSheet({required this.backend, this.onSend});

  final TaildeckBackend backend;
  final ValueChanged<TerminalSnippet>? onSend;

  @override
  State<_SnippetsSheet> createState() => _SnippetsSheetState();
}

class _SnippetsSheetState extends State<_SnippetsSheet> {
  late List<TerminalSnippet> _snippets = widget.backend.terminalSnippets;
  final _name = TextEditingController();
  final _command = TextEditingController();
  TerminalSnippet? _draft;
  bool _isNew = false;
  bool _enter = true;
  String _error = '';

  bool get _editing => _draft != null;

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  void _begin([TerminalSnippet? snippet]) {
    final draft =
        snippet ??
        TerminalSnippet(id: newSnippetId(), name: '', command: '');
    setState(() {
      _isNew = snippet == null;
      _draft = draft;
      _enter = draft.enter;
      _error = '';
      _name.text = draft.name;
      _command.text = draft.command;
    });
  }

  void _back() => setState(() {
    _draft = null;
    _error = '';
  });

  Future<void> _write(List<TerminalSnippet> next) async {
    setState(() => _snippets = next);
    await widget.backend.setTerminalSnippets(next);
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    final l10n = AppLocalizations.of(context);
    final command = _command.text.trim();
    if (command.isEmpty) {
      setState(() => _error = l10n.snippetCommandRequired);
      return;
    }
    final snippet = draft.copyWith(
      name: _name.text,
      command: command,
      enter: _enter,
    );
    final next = upsertSnippet(_snippets, snippet);
    final exists = _snippets.any((item) => item.id == snippet.id);
    if (!exists && next.length == _snippets.length) {
      setState(() => _error = l10n.snippetLimit(maxTerminalSnippets));
      return;
    }
    setState(() => _draft = null);
    await _write(next);
  }

  Future<void> _delete(TerminalSnippet snippet) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: AlertDialog(
        title: l10n.delete,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
        child: Text(l10n.snippetDeleteConfirm(snippet.label)),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _draft = null);
    await _write(removeSnippet(_snippets, snippet.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
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
                if (_editing)
                  IconButton(
                    onPressed: _back,
                    icon: const GlyphIcon(Glyphs.chevronBack),
                    tooltip: l10n.cancel,
                  )
                else
                  const IconBadge(Glyphs2.bolt),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _editing
                        ? (_isNew ? l10n.snippetNew : l10n.snippetName)
                        : l10n.terminalSnippets,
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
            const SizedBox(height: 8),
            if (_editing) _editor(l10n) else _list(l10n),
          ],
        ),
      ),
    );
  }

  Widget _list(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_snippets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              l10n.terminalSnippetsEmpty,
              style: AppTextStyle.footnote.of(context).copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Card(
          radius: AppCorner.xl,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final snippet in _snippets)
                _SnippetRow(
                  snippet: snippet,
                  onTap: widget.onSend == null
                      ? () => _begin(snippet)
                      : () {
                          widget.onSend!(snippet);
                          unawaited(HapticFeedback.lightImpact());
                        },
                  onEdit: () => _begin(snippet),
                ),
              TapFeedback(
                onTap: _snippets.length >= maxTerminalSnippets
                    ? null
                    : () => _begin(),
                child: ListRow(
                  leading: const IconBadge(Glyphs2.plus),
                  title: Text(l10n.snippetNew, style: context.listTitleStyle),
                  subtitle: _snippets.length >= maxTerminalSnippets
                      ? Text(
                          l10n.snippetLimit(maxTerminalSnippets),
                          style: context.listCaptionStyle,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editor(AppLocalizations l10n) {
    final draft = _draft!;
    final index = _snippets.indexWhere((item) => item.id == draft.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          radius: AppCorner.xl,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              EntryRow(
                label: l10n.snippetName,
                controller: _name,
                hintText: l10n.snippetNameHint,
              ),
              const _RowDivider(),
              EntryRow(
                label: l10n.snippetCommand,
                controller: _command,
                hintText: l10n.snippetCommandHint,
                maxLines: 2,
                // Save stays disabled until there is something to send.
                onChanged: (_) => setState(() {}),
              ),
              const _RowDivider(),
              SelectRow<bool>(
                label: l10n.snippetAppendEnter,
                subtitle: _enter
                    ? l10n.snippetAppendEnterOn
                    : l10n.snippetAppendEnterOff,
                value: _enter,
                options: [(true, l10n.onLabel), (false, l10n.offLabel)],
                onChanged: (value) => setState(() => _enter = value),
              ),
            ],
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          InlineNotice(text: _error),
        ],
        if (index >= 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _OrderButton(
                glyph: Glyphs2.arrowUp,
                label: l10n.snippetMoveUp,
                onTap: index == 0
                    ? null
                    : () => unawaited(
                        _write(moveSnippet(_snippets, draft.id, -1)),
                      ),
              ),
              const SizedBox(width: 8),
              _OrderButton(
                glyph: Glyphs2.arrowDown,
                label: l10n.snippetMoveDown,
                onTap: index == _snippets.length - 1
                    ? null
                    : () => unawaited(
                        _write(moveSnippet(_snippets, draft.id, 1)),
                      ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => unawaited(_delete(draft)),
                child: Text(
                  l10n.delete,
                  style: TextStyle(color: context.colorScheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        LoadingButton(
          label: l10n.snippetSave,
          onPressed: _command.text.trim().isEmpty ? null : _save,
        ),
      ],
    );
  }
}

class _SnippetRow extends StatelessWidget {
  const _SnippetRow({
    required this.snippet,
    required this.onTap,
    required this.onEdit,
  });

  final TerminalSnippet snippet;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.a11yTerminalSnippet(snippet.label),
      excludeSemantics: true,
      onTap: onTap,
      child: TapFeedback(
        onTap: onTap,
        excludeFromSemantics: true,
        child: ListRow(
          leading: const IconBadge(Glyphs2.terminal),
          title: Text(snippet.label, style: context.listTitleStyle),
          subtitle: Text(
            snippet.command,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote.of(context).copyWith(
              fontFamily: 'DejaVuSansMono',
              fontSize: 11,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: IconButton(
            onPressed: onEdit,
            icon: const GlyphIcon(Glyphs2.sliders),
            tooltip: l10n.edit,
          ),
        ),
      ),
    );
  }
}

class _OrderButton extends StatelessWidget {
  const _OrderButton({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onTap,
        icon: GlyphIcon(glyph, size: 18),
        tooltip: label,
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
