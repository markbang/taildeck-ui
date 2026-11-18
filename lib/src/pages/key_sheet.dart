import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../l10n.dart';
import '../ssh_identities.dart';
import '../widgets/controls.dart';
import '../widgets/bottom_sheet.dart';
import '../widgets/entry_row.dart';

/// Imports a private key as `ssh/<name>.key`; null when dismissed.
Future<SshIdentity?> showKeySheet(
  BuildContext context,
  TaildeckBackend backend,
) {
  return showMotionSheet<SshIdentity>(
    context: context,
    builder: (context) => _KeySheet(backend: backend),
  );
}

class _KeySheet extends StatefulWidget {
  const _KeySheet({required this.backend});

  final TaildeckBackend backend;

  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _passphrase = TextEditingController();
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    if (_key.text.trim().isEmpty) {
      setState(() => _error = l10n.privateKeyRequired);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final identity = await widget.backend.importSshKey(
        name: _name.text,
        pem: _key.text,
        passphrase: _passphrase.text,
      );
      if (mounted) Navigator.of(context).pop(identity);
    } on SshKeyException catch (error) {
      if (mounted) setState(() => _error = _textFor(l10n, error.reason));
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _textFor(AppLocalizations l10n, SshKeyError reason) =>
      switch (reason) {
        SshKeyError.nameTaken => l10n.keyNameTaken,
        SshKeyError.nameInvalid => l10n.keyImportInvalid,
        SshKeyError.unavailable => l10n.sshNoBackend,
        SshKeyError.io => l10n.keyImportFailed,
      };

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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.importKey,
                    style: AppTextStyle.title2.of(context, emphasized: true),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const GlyphIcon(Glyphs.close),
                  tooltip: l10n.close,
                ),
              ],
            ),
            const SizedBox(height: 14),
            generateGroup([
              EntryRow(
                label: l10n.keyName,
                controller: _name,
                hintText: l10n.keyNameHint,
              ),
              EntryRow(
                label: l10n.privateKey,
                controller: _key,
                hintText: l10n.privateKeyHint,
                monospace: true,
                minLines: 6,
                maxLines: 10,
              ),
              EntryRow(
                label: l10n.passphrase,
                controller: _passphrase,
                hintText: l10n.passphraseOptional,
                obscure: true,
              ),
            ]),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _error,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            LoadingButton(
              label: l10n.importKey,
              loading: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
