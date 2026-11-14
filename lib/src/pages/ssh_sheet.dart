import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../data.dart';
import '../l10n.dart';
import '../native/bridge.dart';
import '../native/ssh.dart';
import '../native/storage.dart';
import '../services.dart';
import '../ssh_identities.dart';

typedef SshChoice = ({String user, int port, SshSession? session});

/// [service] scopes the remembered login to one service on [node], so both
/// targets can keep their own user.
Future<SshChoice?> showSshSheet(
  BuildContext context,
  NodeItem node, {
  Service? service,
}) {
  // The sheet lives on its own route, above the BackendScope in the page tree,
  // so the backend is handed in from here.
  final backend = BackendScope.of(context);
  return showFormSheet<SshChoice>(
    context: context,
    builder: (context) => _SshSheet(
      node: node,
      backend: backend,
      loginKey: sshLoginKey(node.name, service: service?.id ?? ''),
    ),
  );
}

enum _Auth { tailscale, password, key }

class _SshSheet extends StatefulWidget {
  const _SshSheet({
    required this.node,
    required this.backend,
    required this.loginKey,
  });

  final NodeItem node;
  final TaildeckBackend backend;

  /// Config key the last login for this target is saved under.
  final String loginKey;

  @override
  State<_SshSheet> createState() => _SshSheetState();
}

class _SshSheetState extends State<_SshSheet> {
  late final _user = TextEditingController(text: _initialUser());
  String _userError = '';
  int _port = 22;
  _Auth _auth = _Auth.tailscale;
  final _password = TextEditingController();
  List<SshIdentity> _identities = const [];
  String _identityId = builtinKeyId;
  String _keyError = '';
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _user.addListener(_validate);
    if (widget.backend.available) unawaited(_loadKeys(widget.backend));
  }

  /// Remembered login first, then what Tailscale SSH would suggest, then root.
  String _initialUser() {
    final remembered = widget.backend.sshUserFor(widget.loginKey);
    if (remembered.isNotEmpty) return remembered;
    final suggested = widget.node.suggestedSshUser;
    return suggested.isEmpty ? 'root' : suggested;
  }

  static final _userPattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]{0,31}$');

  static bool _isValidUser(String user) => _userPattern.hasMatch(user);

  void _validate() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final value = _user.text.trim();
    final error = value.isEmpty
        ? l10n.sshUserRequired
        : _isValidUser(value)
        ? ''
        : l10n.sshUserInvalid;
    if (error != _userError) setState(() => _userError = error);
  }

  Future<void> _loadKeys(TaildeckBackend backend) async {
    try {
      final keys = await backend.sshIdentities();
      if (!mounted) return;
      setState(() {
        _identities = keys;
        if (keys.isNotEmpty && !keys.any((key) => key.id == _identityId)) {
          _identityId = keys.first.id;
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _keyError = _message(error));
    }
  }

  SshIdentity? get _identity {
    for (final key in _identities) {
      if (key.id == _identityId) return key;
    }
    return null;
  }

  static String _message(Object error) =>
      error is BridgeException ? error.message : '$error';

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    _validate();
    if (_busy || _userError.isNotEmpty) return;
    final user = _user.text.trim();
    final backend = widget.backend;
    if (!backend.available) {
      Navigator.of(context).pop((user: user, port: _port, session: null));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await backend.rememberSshUser(widget.loginKey, user);
      final session = await backend.openSshSession(
        host: widget.node.name,
        user: user,
        port: _port,
        password: _auth == _Auth.password ? _password.text : '',
        identityId: _identityId,
      );
      if (!mounted) {
        session.close();
        return;
      }
      Navigator.of(context).pop((user: user, port: _port, session: session));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final backend = widget.backend;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.ssh,
                        style: AppTextStyle.title2.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.node.name} · ${widget.node.ip}',
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
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
            Card(
              radius: AppCorner.xl,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _UserRow(
                    controller: _user,
                    label: l10n.sshUser,
                    errorText: _userError,
                    enabled: !_busy,
                  ),
                  const _RowDivider(),
                  _SelectRow<int>(
                    label: l10n.sshPort,
                    value: _port,
                    options: const [(22, '22'), (2222, '2222'), (2200, '2200')],
                    onChanged: (value) => setState(() => _port = value),
                  ),
                  const _RowDivider(),
                  _SelectRow<_Auth>(
                    label: l10n.sshAuth,
                    value: _auth,
                    options: [
                      (_Auth.tailscale, l10n.authTailscale),
                      (_Auth.password, l10n.authPassword),
                      (_Auth.key, l10n.authKey),
                    ],
                    onChanged: (value) => setState(() => _auth = value),
                  ),
                  if (_auth == _Auth.password) ...[
                    const _RowDivider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: TextField(
                        controller: _password,
                        obscureText: true,
                        style: context.listTitleStyle,
                        decoration: InputDecoration(
                          hintText: l10n.sshPasswordHint,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_auth == _Auth.key) ...[
              const SizedBox(height: 12),
              Card(
                radius: AppCorner.lg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_identities.length > 1) ...[
                        PopupAnchor(
                          targetBuilder: (open) => PressRegion(
                            onTap: open,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.sshIdentity,
                                      style: context.listTitleStyle,
                                    ),
                                  ),
                                  Text(
                                    _identity?.name ?? _identityId,
                                    style: AppTextStyle.body.of(context).copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
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
                              for (final key in _identities)
                                PopupMenuItem(
                                  label: key.builtin ? l10n.builtinKey : key.name,
                                  checked: key.id == _identityId,
                                  onPressed: () =>
                                      setState(() => _identityId = key.id),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 16, thickness: 0.5),
                      ],
                      Text(
                        l10n.sshKeyTitle,
                        style: AppTextStyle.body.of(context, emphasized: true),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        switch (_identity?.publicKey) {
                          final String key when key.isNotEmpty => key,
                          _ when _keyError.isNotEmpty => _keyError,
                          _ => '…',
                        },
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(
                              fontFamily: 'DejaVuSansMono',
                              fontSize: 11,
                              color: _keyError.isEmpty ? null : scheme.error,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.sshKeyHint,
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (!backend.available) ...[
              const SizedBox(height: 12),
              Text(
                l10n.sshNoBackend,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
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
            FilledButton(
              onPressed: _busy || _userError.isNotEmpty ? null : _connect,
              child: Text(_busy ? l10n.connecting : l10n.connect),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editable login row: the field keeps the sheet's grouped card rhythm while
/// the value stays free text.
class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.controller,
    required this.label,
    required this.errorText,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final String errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.listCaptionStyle.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: label,
            child: TextField(
              controller: controller,
              enabled: enabled,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              autofillHints: const [AutofillHints.username],
              style: context.listTitleStyle,
              decoration: InputDecoration(
                hintText: 'root',
                hintStyle: context.listCaptionStyle,
                errorText: errorText.isEmpty ? null : errorText,
                filled: true,
                fillColor: SurfaceLevel.block.colorOf(scheme),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
              ),
            ),
          ),
        ],
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

class _SelectRow<T> extends StatelessWidget {
  const _SelectRow({
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
    final current = options.firstWhere((o) => o.$1 == value).$2;
    return PopupAnchor(
      targetBuilder: (open) => PressRegion(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(child: Text(label, style: context.listTitleStyle)),
              Text(
                current,
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
