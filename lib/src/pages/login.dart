import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../widgets/foundation.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignedIn, this.onCancel});

  final VoidCallback onSignedIn;
  final VoidCallback? onCancel;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum _Stage { idle, waiting }

class _LoginPageState extends State<LoginPage> {
  // Preview-only stage (web, or a run without the native library).
  _Stage _previewStage = Uri.base.queryParameters['login'] == 'waiting'
      ? _Stage.waiting
      : _Stage.idle;
  bool _authKey = false;
  bool _advanced = false;
  bool _busy = false;
  String _openedUrl = '';
  static const _previewUrl = 'login.tailscale.com/a/4f2c9e';
  final _key = TextEditingController();
  final _control = TextEditingController();
  Timer? _demoTimer;

  @override
  void dispose() {
    _demoTimer?.cancel();
    _key.dispose();
    _control.dispose();
    super.dispose();
  }

  void _startBrowserLogin() {
    setState(() => _previewStage = _Stage.waiting);
    _demoTimer?.cancel();
    _demoTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) widget.onSignedIn();
    });
  }

  void _cancel() {
    _demoTimer?.cancel();
    setState(() => _previewStage = _Stage.idle);
  }

  String? _controlURL() {
    final value = _control.text.trim();
    return _advanced && value.isNotEmpty ? value : null;
  }

  Future<void> _connectWithKey(TaildeckBackend backend) async {
    if (_busy) return;
    setState(() => _busy = true);
    await backend.signInWithKey(_key.text, controlURL: _controlURL());
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _connectInBrowser(TaildeckBackend backend) async {
    if (_busy) return;
    setState(() => _busy = true);
    await backend.signInInBrowser(controlURL: _controlURL());
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _leaveWaiting(TaildeckBackend backend) async {
    await backend.cancelSignIn();
    if (mounted) setState(() => _previewStage = _Stage.idle);
  }

  /// The node hands us the login URL; open it once in the system browser.
  void _openLoginUrl(String url) {
    if (url.isEmpty || url == _openedUrl) return;
    _openedUrl = url;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } on Object {
        // No browser on this host: the URL stays visible and copyable.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final backend = BackendScope.of(context);
    final live = backend.available;
    final waiting =
        live &&
        (backend.waitingForLogin ||
            (backend.needsLogin && backend.authUrl.isNotEmpty));
    if (live) _openLoginUrl(backend.authUrl);
    final previewWaiting = !live && _previewStage == _Stage.waiting;
    final showError = live && backend.error.isNotEmpty && !waiting;
    return Surface(
      color: SurfaceLevel.page.colorOf(scheme),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 56,
                            height: 56,
                            alignment: Alignment.center,
                            decoration: ShapeDecoration(
                              color: scheme.primary.withValues(alpha: 0.16),
                              shape: AppShape.all(18),
                            ),
                            child: GlyphIcon(
                              Glyphs2.nodes,
                              size: 28,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Taildeck',
                          style: AppTextStyle.largeTitle
                              .of(context, emphasized: true),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.tagline,
                          style: AppTextStyle.body
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                        if (waiting || previewWaiting)
                          _waiting(
                            context,
                            url: waiting ? backend.authUrl : _previewUrl,
                            onCancel: waiting
                                ? () => _leaveWaiting(backend)
                                : _cancel,
                          )
                        else if (live)
                          _buildLiveChoices(context, backend)
                        else
                          _buildPreviewChoices(context),
                        if (live && backend.state == BackendState.starting) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.startingNode,
                            textAlign: TextAlign.center,
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        if (showError) ...[
                          const SizedBox(height: 14),
                          InlineNotice(
                            text: '${l10n.signInFailed}: ${backend.error}',
                          ),
                        ],
                        if (!live && !kIsWeb) ...[
                          const SizedBox(height: 14),
                          InlineNotice(text: l10n.backendUnavailable),
                        ],
                        const SizedBox(height: 22),
                        Text(
                          l10n.worksWith,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.caption1.of(context).copyWith(
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLiveChoices(BuildContext context, TaildeckBackend backend) {
    return _Choices(
      authKey: _authKey,
      advanced: _advanced,
      keyController: _key,
      controlController: _control,
      connectEnabled: !_busy,
      onToggleAuthKey: () => setState(() => _authKey = !_authKey),
      onToggleAdvanced: () => setState(() => _advanced = !_advanced),
      onConnect: () => _connectWithKey(backend),
      onBrowser: () => _connectInBrowser(backend),
    );
  }

  Widget _buildPreviewChoices(BuildContext context) {
    return _Choices(
      authKey: _authKey,
      advanced: _advanced,
      keyController: _key,
      controlController: _control,
      connectEnabled: true,
      onToggleAuthKey: () => setState(() => _authKey = !_authKey),
      onToggleAdvanced: () => setState(() => _advanced = !_advanced),
      onConnect: widget.onSignedIn,
      onBrowser: _startBrowserLogin,
    );
  }

  Widget _waiting(
    BuildContext context, {
    required String url,
    required VoidCallback onCancel,
  }) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Card(
      radius: AppCorner.xxl,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.waitingTitle,
                  style: AppTextStyle.body.of(context, emphasized: true),
                ),
              ),
              const ActivityIndicator(size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.waitingBody,
            style: context.listSubtitleStyle,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: ShapeDecoration(
              color: scheme.surfaceContainerHigh,
              shape: AppShape.all(AppCorner.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url.isEmpty ? l10n.waitingForUrl : url,
                    style: AppTextStyle.footnote.of(context).copyWith(
                      fontFamily: 'DejaVuSansMono',
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                GlyphIcon(Glyphs.copy, size: 14, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onCancel,
            child: Text(
              l10n.cancel,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.authKey,
    required this.advanced,
    required this.keyController,
    required this.controlController,
    required this.connectEnabled,
    required this.onToggleAuthKey,
    required this.onToggleAdvanced,
    required this.onConnect,
    required this.onBrowser,
  });

  final bool authKey;
  final bool advanced;
  final TextEditingController keyController;
  final TextEditingController controlController;
  final bool connectEnabled;
  final VoidCallback onToggleAuthKey;
  final VoidCallback onToggleAdvanced;
  final VoidCallback onConnect;
  final VoidCallback onBrowser;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          radius: AppCorner.xxl,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OptionRow(
                glyph: Glyphs2.globe,
                title: l10n.continueInBrowser,
                subtitle: l10n.signInToControlServer,
                onTap: onBrowser,
                trailing: GlyphIcon(
                  Glyphs.chevronForward,
                  size: 16,
                  color: scheme.onSurfaceVariant.opacity50,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 0.5, thickness: 0.5),
              ),
              _OptionRow(
                glyph: Glyphs2.bolt,
                title: l10n.useAuthKey,
                subtitle: authKey ? null : l10n.pasteKey,
                onTap: onToggleAuthKey,
                trailing: GlyphIcon(
                  authKey ? Glyphs.chevronDown : Glyphs.chevronForward,
                  size: 16,
                  color: scheme.onSurfaceVariant.opacity50,
                ),
              ),
              if (authKey) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(fontFamily: 'DejaVuSansMono', fontSize: 13),
                  decoration: const InputDecoration(
                    filled: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: connectEnabled ? onConnect : null,
                  child: Text(l10n.connect),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: onToggleAdvanced,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.controlServer,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: scheme.primary),
              ),
              GlyphIcon(
                advanced ? Glyphs.chevronDown : Glyphs.chevronForward,
                size: 14,
                color: scheme.primary,
              ),
            ],
          ),
        ),
        if (advanced)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              controller: controlController,
              style: context.listSubtitleStyle,
              decoration: const InputDecoration(
                hintText: 'https://controlplane.tailscale.com',
                filled: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.glyph,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Glyph glyph;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return PressRegion(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                shape: AppShape.all(11),
              ),
              child: GlyphIcon(glyph, size: 18, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.listTitleStyle),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
                        style: context.listCaptionStyle,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
