import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignedIn, this.onCancel});

  final VoidCallback onSignedIn;
  final VoidCallback? onCancel;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum _Stage { idle, waiting }

class _LoginPageState extends State<LoginPage> {
  _Stage _stage = Uri.base.queryParameters['login'] == 'waiting'
      ? _Stage.waiting
      : _Stage.idle;
  bool _authKey = false;
  bool _advanced = false;
  final _key = TextEditingController(text: 'tskey-auth-k...');
  Timer? _demoTimer;

  @override
  void dispose() {
    _demoTimer?.cancel();
    _key.dispose();
    super.dispose();
  }

  void _startBrowserLogin() {
    setState(() => _stage = _Stage.waiting);
    _demoTimer?.cancel();
    _demoTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) widget.onSignedIn();
    });
  }

  void _cancel() {
    _demoTimer?.cancel();
    setState(() => _stage = _Stage.idle);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
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
                          'Your tailnet, without the VPN slot.',
                          style: AppTextStyle.body
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                        if (_stage == _Stage.idle)
                          _buildChoices(context)
                        else
                          _waiting(context),
                        const SizedBox(height: 22),
                        Text(
                          'Works with Tailscale and Headscale control servers.',
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

  Widget _buildChoices(BuildContext context) {
    final scheme = context.colorScheme;
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
                title: 'Continue in browser',
                subtitle: 'Sign in to your control server',
                onTap: _startBrowserLogin,
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
                title: 'Use an auth key',
                subtitle: _authKey ? null : 'Paste a tskey-… key',
                onTap: () => setState(() => _authKey = !_authKey),
                trailing: GlyphIcon(
                  _authKey ? Glyphs.chevronDown : Glyphs.chevronForward,
                  size: 16,
                  color: scheme.onSurfaceVariant.opacity50,
                ),
              ),
              if (_authKey) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _key,
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
                  onPressed: widget.onSignedIn,
                  child: const Text('Connect'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() => _advanced = !_advanced),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Control server',
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: scheme.primary),
              ),
              GlyphIcon(
                _advanced ? Glyphs.chevronDown : Glyphs.chevronForward,
                size: 14,
                color: scheme.primary,
              ),
            ],
          ),
        ),
        if (_advanced)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
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

  Widget _waiting(BuildContext context) {
    final scheme = context.colorScheme;
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
                  'Waiting for approval',
                  style: AppTextStyle.body.of(context, emphasized: true),
                ),
              ),
              const ActivityIndicator(size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'A browser tab should have opened. Sign in, then come back — this screen updates on its own.',
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
                    'login.tailscale.com/a/4f2c9e',
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
            onPressed: _cancel,
            child: Text(
              'Cancel',
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
