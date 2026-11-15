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
import '../widgets/controls.dart';
import '../widgets/entry_row.dart';
import '../widgets/select_row.dart';
import '../widgets/bottom_sheet.dart';

/// What the sheet hands back. The password and the key id stay in memory so a
/// reconnect after a drop can dial again without asking.
typedef SshChoice = ({
  String user,
  int port,
  String password,
  String identityId,
  SshSession? session,
});

/// [service] scopes the remembered login to one service on [node], so both
/// targets keep their own user and port.
Future<SshChoice?> showSshSheet(
  BuildContext context,
  NodeItem node, {
  Service? service,
}) {
  // The sheet lives on its own route, above the BackendScope in the page tree,
  // so the backend is handed in from here.
  final backend = BackendScope.of(context);
  return showMotionSheet<SshChoice>(
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
  late final _port = TextEditingController(
    text: '${widget.backend.sshPortFor(widget.loginKey)}',
  );
  String _userError = '';
  String _portError = '';
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
    _user.addListener(_validateUser);
    _port.addListener(_validatePort);
    if (widget.backend.available) unawaited(_loadKeys(widget.backend));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _validateUser();
    _validatePort();
  }

  /// Last login for this target, the node's last one, the tailnet login, then
  /// root.
  late final _userSuggestions = [
    for (final user in {
      widget.backend.sshUserFor(widget.loginKey),
      if (widget.loginKey != widget.node.name)
        widget.backend.sshUserFor(widget.node.name),
      widget.node.suggestedSshUser,
      'root',
    })
      if (user.isNotEmpty) user,
  ];

  /// The first suggested login that is not the root default.
  String _initialUser() {
    for (final user in _userSuggestions) {
      if (user != 'root') return user;
    }
    return 'root';
  }

  void _validateUser() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final value = _user.text.trim();
    final error = value.isEmpty
        ? l10n.sshUserRequired
        : isValidSshUser(value)
        ? ''
        : l10n.sshUserInvalid;
    if (error != _userError) setState(() => _userError = error);
  }

  void _validatePort() {
    if (!mounted) return;
    final error = portValue(_port.text) == null
        ? AppLocalizations.of(context).portInvalid
        : '';
    if (error != _portError) setState(() => _portError = error);
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
    _validateUser();
    _validatePort();
    if (_busy || _userError.isNotEmpty || _portError.isNotEmpty) return;
    final user = _user.text.trim();
    final port = portValue(_port.text)!;
    final backend = widget.backend;
    if (!backend.available) {
      Navigator.of(context).pop((
        user: user,
        port: port,
        password: _password.text,
        identityId: _identityId,
        session: null,
      ));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await backend.rememberSshLogin(widget.loginKey, user: user, port: port);
      final session = await backend.openSshSession(
        host: widget.node.name,
        user: user,
        port: port,
        password: _auth == _Auth.password ? _password.text : '',
        identityId: _identityId,
      );
      if (!mounted) {
        session.close();
        return;
      }
      Navigator.of(context).pop((
        user: user,
        port: port,
        password: _password.text,
        identityId: _identityId,
        session: session,
      ));
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
                  EntryRow(
                    label: l10n.sshUser,
                    controller: _user,
                    hintText: 'root',
                    errorText: _userError.isEmpty ? null : _userError,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.username],
                    suggestions: _userSuggestions,
                  ),
                  const _RowDivider(),
                  EntryRow(
                    label: l10n.sshPort,
                    controller: _port,
                    hintText: '22',
                    numeric: true,
                    errorText: _portError.isEmpty ? null : _portError,
                    enabled: !_busy,
                  ),
                  const _RowDivider(),
                  SelectRow<_Auth>(
                    label: l10n.sshAuth,
                    value: _auth,
                    options: [
                      (_Auth.tailscale, l10n.authTailscale),
                      (_Auth.password, l10n.authPassword),
                      (_Auth.key, l10n.authKey),
                    ],
                    enabled: !_busy,
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
                        SelectRow<String>(
                          label: l10n.sshIdentity,
                          value: _identityId,
                          options: [
                            for (final key in _identities)
                              (
                                key.id,
                                key.builtin ? l10n.builtinKey : key.name,
                              ),
                          ],
                          enabled: !_busy,
                          onChanged: (value) =>
                              setState(() => _identityId = value),
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
            LoadingButton(
              label: l10n.connect,
              loading: _busy,
              onPressed: _userError.isNotEmpty || _portError.isNotEmpty
                  ? null
                  : _connect,
            ),
          ],
        ),
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
