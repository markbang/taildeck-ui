import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend.dart';
import '../data.dart';
import '../native/bridge.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../shell.dart';
import '../ssh_identities.dart';
import '../theme.dart';
import '../widgets/foundation.dart';
import 'key_sheet.dart';
import 'logs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.theme,
    required this.floatingNavigation,
    required this.onFloatingNavigationChanged,
    required this.onToggleTheme,
    required this.tabAnimation,
    required this.onTabAnimationChanged,
    required this.onSignOut,
  });

  final TaildeckTheme theme;
  final bool floatingNavigation;
  final ValueChanged<bool> onFloatingNavigationChanged;
  final TabAnimation tabAnimation;
  final ValueChanged<TabAnimation> onTabAnimationChanged;
  final VoidCallback onSignOut;
  final VoidCallback onToggleTheme;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<SshIdentity> _keys = const [];
  bool _keysLoaded = false;
  bool _showLogs = false;
  String _notice = '';
  String _error = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_keysLoaded) return;
    _keysLoaded = true;
    unawaited(_loadKeys());
  }

  static String _message(Object error) => switch (error) {
    BridgeException() => error.message,
    SshKeyException() => error.reason.name,
    _ => '$error',
  };

  Future<void> _loadKeys() async {
    final backend = BackendScope.of(context);
    if (!backend.available) return;
    try {
      final keys = await backend.sshIdentities();
      if (mounted) setState(() => _keys = keys);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _copy(String text) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _notice = l10n.publicKeyCopied);
  }

  Future<void> _import() async {
    final backend = BackendScope.of(context);
    final identity = await showKeySheet(context, backend);
    if (identity == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _notice = l10n.keyImported;
      _error = '';
    });
    await _loadKeys();
  }

  Future<void> _delete(SshIdentity identity) async {
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
        child: Text(l10n.deleteKeyConfirm(identity.name)),
      ),
    );
    if (confirmed != true || !mounted) return;
    final backend = BackendScope.of(context);
    try {
      await backend.deleteSshKey(identity);
      if (!mounted) return;
      setState(() {
        _notice = l10n.keyDeleted;
        _error = '';
      });
      await _loadKeys();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _forgetHosts() async {
    final backend = BackendScope.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await backend.forgetSshHostKeys();
      if (mounted) {
        setState(() {
          _notice = l10n.hostKeysCleared;
          _error = '';
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: AlertDialog(
        title: l10n.signOutTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.signOutAction),
          ),
        ],
        child: Text(l10n.signOutBody),
      ),
    );
    if (confirmed == true) widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogs) {
      return LogsPage(onBack: () => setState(() => _showLogs = false));
    }
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final backend = BackendScope.of(context);
    final live = backend.available;
    final self = backend.self;
    return PageBody(
      title: l10n.tabSettings,
      children: [
        if (_notice.isNotEmpty) ...[
          InlineNotice(text: _notice, tint: scheme.primary),
          const SizedBox(height: 14),
        ],
        if (_error.isNotEmpty) ...[
          InlineNotice(text: _error),
          const SizedBox(height: 14),
        ],
        SectionLabel(l10n.tailnetSection),
        GroupCard(
          dividerInset: 16,
          children: [
            _InfoRow(label: l10n.account, value: _orDash(self?.owner)),
            _InfoRow(label: l10n.tailnetName, value: backend.tailnet),
            _InfoRow(
              label: l10n.controlServer,
              value: backend.controlURL.isEmpty
                  ? 'controlplane.tailscale.com'
                  : backend.controlURL,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.thisDeviceSection),
        GroupCard(
          dividerInset: 16,
          children: [
            _InfoRow(
              label: l10n.hostname,
              value: self?.name ?? backend.hostname,
            ),
            _InfoRow(label: l10n.addresses, value: _orDash(self?.ip), mono: true),
            _InfoRow(
              label: l10n.status,
              value: (self?.online ?? false) ? l10n.online : l10n.offline,
              tint: (self?.online ?? false)
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.sshIdentities),
        GroupCard(
          dividerInset: 60,
          children: [
            if (!live)
              ListRow(
                leading: const IconBadge(Glyphs2.key),
                title: Text(l10n.builtinKey, style: context.listTitleStyle),
                subtitle: Text(l10n.sshNoBackend, style: context.listCaptionStyle),
              )
            else ...[
              for (final identity in _keys)
                _KeyRow(
                  identity: identity,
                  onCopy: identity.publicKey.isEmpty
                      ? null
                      : () => unawaited(_copy(identity.publicKey)),
                  onDelete: identity.builtin
                      ? null
                      : () => unawaited(_delete(identity)),
                ),
              PressRegion(
                onTap: () => unawaited(_import()),
                child: ListRow(
                  leading: const IconBadge(Glyphs2.plus),
                  title: Text(l10n.importKey, style: context.listTitleStyle),
                  subtitle: Text(
                    l10n.privateKeyHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.listCaptionStyle,
                  ),
                ),
              ),
              PressRegion(
                onTap: () => unawaited(_forgetHosts()),
                child: ListRow(
                  leading: const IconBadge(Glyphs2.refresh),
                  title: Text(l10n.forgetHostKeys, style: context.listTitleStyle),
                  subtitle: Text(
                    l10n.forgetHostKeysHint,
                    style: context.listCaptionStyle,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.tabServices),
        GroupCard(
          dividerInset: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.servicesOpen, style: context.listTitleStyle),
                  const SizedBox(height: 10),
                  SegmentedControl<bool>(
                    segments: [
                      (false, l10n.inBrowser),
                      (true, l10n.inApp),
                    ],
                    value: backend.openInApp,
                    onChanged: (value) =>
                        unawaited(backend.setOpenInApp(value)),
                  ),
                  if (backend.openInApp) ...[
                    const SizedBox(height: 8),
                    Text(l10n.inAppComingSoon, style: context.listCaptionStyle),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.logs),
        GroupCard(
          dividerInset: 60,
          children: [
            PressRegion(
              onTap: () => setState(() {
                _showLogs = true;
                _notice = '';
                _error = '';
              }),
              child: ListRow(
                leading: const IconBadge(Glyphs2.doc),
                title: Text(l10n.logs, style: context.listTitleStyle),
                subtitle: Text(
                  live ? 'td_logs()' : l10n.backendUnavailable,
                  style: context.listCaptionStyle,
                ),
                trailing: GlyphIcon(
                  Glyphs.chevronForward,
                  size: 16,
                  color: scheme.onSurfaceVariant.opacity50,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.session),
        GroupCard(
          dividerInset: 16,
          children: [
            PressRegion(
              onTap: () => unawaited(_signOut()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.signOut,
                        style: context.listTitleStyle.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                    GlyphIcon(
                      Glyphs.chevronForward,
                      size: 16,
                      color: scheme.error.opacity50,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.appearance),
        GroupCard(
          dividerInset: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.theme, style: context.listTitleStyle),
                  const SizedBox(height: 10),
                  SegmentedControl<ThemeMode>(
                    segments: [
                      (ThemeMode.system, l10n.system),
                      (ThemeMode.light, l10n.light),
                      (ThemeMode.dark, l10n.dark),
                    ],
                    value: widget.theme.mode,
                    onChanged: (value) => widget.theme.setMode(value),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.language, style: context.listTitleStyle),
                  const SizedBox(height: 10),
                  SegmentedControl<String>(
                    segments: [
                      ('system', l10n.system),
                      ('en', l10n.english),
                      ('zh', l10n.chinese),
                    ],
                    value: switch (widget.theme.locale?.languageCode) {
                      'en' => 'en',
                      'zh' => 'zh',
                      _ => 'system',
                    },
                    onChanged: (value) => widget.theme.setLocale(
                      switch (value) {
                        'en' => const Locale('en'),
                        'zh' => const Locale('zh'),
                        _ => null,
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.navigation),
        GroupCard(
          dividerInset: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.bottomBar, style: context.listTitleStyle),
                  const SizedBox(height: 2),
                  Text(
                    widget.floatingNavigation ? l10n.floatingHint : l10n.dockedHint,
                    style: context.listCaptionStyle,
                  ),
                  const SizedBox(height: 10),
                  SegmentedControl<bool>(
                    segments: [
                      (true, l10n.floating),
                      (false, l10n.docked),
                    ],
                    value: widget.floatingNavigation,
                    onChanged: widget.onFloatingNavigationChanged,
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.tabAnimation, style: context.listTitleStyle),
                  const SizedBox(height: 2),
                  Text(
                    widget.tabAnimation == TabAnimation.fade
                        ? l10n.fadeHint
                        : l10n.slideHint,
                    style: context.listCaptionStyle,
                  ),
                  const SizedBox(height: 10),
                  SegmentedControl<TabAnimation>(
                    segments: [
                      (TabAnimation.slide, l10n.slide),
                      (TabAnimation.fade, l10n.fade),
                    ],
                    value: widget.tabAnimation,
                    onChanged: widget.onTabAnimationChanged,
                  ),
                  if (context.disableAnimations) ...[
                    const SizedBox(height: 8),
                    Text(l10n.motionHint, style: context.listCaptionStyle),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.about),
        GroupCard(
          dividerInset: 60,
          children: [
            ListRow(
              leading: const IconBadge(Glyphs2.nodes),
              title: Text('Taildeck', style: context.listTitleStyle),
              trailing: Text(l10n.version(appVersion), style: context.listCaptionStyle),
            ),
            PressRegion(
              onTap: () => unawaited(launchUrl(
                Uri.parse(repoUrl),
                mode: LaunchMode.externalApplication,
              )),
              child: ListRow(
                leading: const IconBadge(Glyphs2.globe),
                title: Text(l10n.repository, style: context.listTitleStyle),
                subtitle: Text('markbang/taildeck-ui', style: context.listCaptionStyle),
                trailing: GlyphIcon(
                  Glyphs.chevronForward,
                  size: 16,
                  color: scheme.onSurfaceVariant.opacity50,
                ),
              ),
            ),
            ListRow(
              leading: const IconBadge(Glyphs2.agents),
              title: Text('prism_ui', style: context.listTitleStyle),
              trailing: Text('0.1.2', style: context.listCaptionStyle),
            ),
          ],
        ),
      ],
    );
  }

  static String _orDash(String? value) =>
      value == null || value.isEmpty ? '—' : value;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.tint,
  });

  final String label;
  final String value;
  final bool mono;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.listTitleStyle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: (mono
                      ? AppTextStyle.footnote.of(context).copyWith(
                          fontFamily: 'DejaVuSansMono',
                          fontSize: 11,
                        )
                      : AppTextStyle.body.of(context))
                  .copyWith(color: tint ?? scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.identity, this.onCopy, this.onDelete});

  final SshIdentity identity;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final subtitle = identity.publicKey.isEmpty
        ? l10n.publicKeyUnavailable
        : identity.publicKey;
    return ListRow(
      leading: IconBadge(Glyphs2.key, tint: identity.builtin ? null : scheme.primary),
      title: Text(
        identity.builtin ? l10n.builtinKey : identity.name,
        style: context.listTitleStyle,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.footnote.of(context).copyWith(
          fontFamily: 'DejaVuSansMono',
          fontSize: 11,
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const GlyphIcon(Glyphs.copy),
              tooltip: l10n.copyPublicKey,
            ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const GlyphIcon(Glyphs2.trash),
              tooltip: l10n.delete,
            ),
        ],
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge(this.glyph, {super.key, this.tint});

  final Glyph glyph;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final color = tint ?? scheme.primary;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: AppShape.all(10),
      ),
      child: GlyphIcon(glyph, size: 18, color: color),
    );
  }
}
