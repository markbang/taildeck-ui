import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../back.dart';
import '../backend.dart';
import '../data.dart';
import '../favicons.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../motion.dart';
import '../native/bridge.dart';
import '../services.dart';
import '../shell.dart';
import '../ssh_identities.dart';
import '../theme.dart';
import '../webview/web_page.dart';
import '../widgets/controls.dart';
import '../widgets/foundation.dart';
import '../widgets/loading.dart';
import '../widgets/select_row.dart';
import 'key_sheet.dart';
import 'logs.dart';
import 'terminal_keys_sheet.dart';

/// What the grouped list opens, in the order the rows show.
enum _Section {
  tailnet,
  identities,
  services,
  notifications,
  terminal,
  appearance,
  logs,
  about,
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.backStack,
    required this.theme,
    required this.floatingNavigation,
    required this.onFloatingNavigationChanged,
    required this.tabAnimation,
    required this.onTabAnimationChanged,
    required this.onSignOut,
  });

  final BackStack backStack;
  final TaildeckTheme theme;
  final bool floatingNavigation;
  final ValueChanged<bool> onFloatingNavigationChanged;
  final TabAnimation tabAnimation;
  final ValueChanged<TabAnimation> onTabAnimationChanged;
  final VoidCallback onSignOut;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Section? _section;
  List<SshIdentity> _keys = const [];
  bool _keysLoaded = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    widget.backStack.add(_closeSection);
  }

  @override
  void dispose() {
    widget.backStack.remove(_closeSection);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.valuesOf(context).enabled;
    // The tab keeps its page alive; it opens on the list again.
    if (!_active) _section = null;
    if (_keysLoaded) return;
    _keysLoaded = true;
    unawaited(_loadKeys());
  }

  Future<void> _loadKeys() async {
    final backend = BackendScope.of(context);
    if (!backend.available) return;
    try {
      final keys = await backend.sshIdentities();
      if (mounted) setState(() => _keys = keys);
    } on Object catch (error) {
      debugPrint('taildeck settings: keys failed: ${_message(error)}');
    }
  }

  /// Back closes the open section; false when the list itself is showing.
  bool _closeSection() {
    if (_section == null || !_active || !mounted) return false;
    setState(() => _section = null);
    return true;
  }

  void _open(_Section section) => setState(() => _section = section);

  void _back() => setState(() => _section = null);

  @override
  Widget build(BuildContext context) {
    final section = _section;
    return ScaleFadeSwitcher(
      child: KeyedSubtree(
        key: ValueKey(section),
        child: section == null ? _list(context) : _page(context, section),
      ),
    );
  }

  Widget _page(BuildContext context, _Section section) {
    return switch (section) {
      _Section.tailnet => _TailnetSection(onBack: _back),
      _Section.identities => _SshIdentitiesSection(
        onBack: _back,
        keys: _keys,
        reload: _loadKeys,
      ),
      _Section.services => _ServicesSection(onBack: _back),
      _Section.notifications => _NotificationsSection(onBack: _back),
      _Section.terminal => _TerminalSection(onBack: _back),
      _Section.appearance => _AppearanceSection(
        onBack: _back,
        theme: widget.theme,
        floatingNavigation: widget.floatingNavigation,
        onFloatingNavigationChanged: widget.onFloatingNavigationChanged,
        tabAnimation: widget.tabAnimation,
        onTabAnimationChanged: widget.onTabAnimationChanged,
      ),
      _Section.logs => LogsPage(onBack: _back),
      _Section.about => _AboutSection(onBack: _back),
    };
  }

  Widget _list(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final backend = BackendScope.of(context);
    final live = backend.available;
    final theme = widget.theme;
    return PageBody(
      title: l10n.tabSettings,
      animateSize: true,
      children: [
        GroupCard(
          dividerInset: 60,
          children: [
            _EntryRow(
              glyph: Glyphs2.nodes,
              title: l10n.tailnetAndDevice,
              subtitle: backend.tailnet.isEmpty
                  ? l10n.notSignedIn
                  : backend.tailnet,
              onTap: () => _open(_Section.tailnet),
            ),
            _EntryRow(
              glyph: Glyphs2.key,
              title: l10n.sshIdentities,
              subtitle: live ? l10n.keyCount(_keys.length) : l10n.unavailable,
              onTap: () => _open(_Section.identities),
            ),
            _EntryRow(
              glyph: Glyphs2.grid,
              title: l10n.tabServices,
              subtitle: backend.openInApp ? l10n.inApp : l10n.inBrowser,
              onTap: () => _open(_Section.services),
            ),
            _EntryRow(
              glyph: Glyphs2.bell,
              title: l10n.notificationsSection,
              subtitle: !backend.notifications.supported
                  ? l10n.unavailable
                  : backend.agentNotifications
                  ? l10n.on
                  : l10n.off,
              onTap: () => _open(_Section.notifications),
            ),
            _EntryRow(
              glyph: Glyphs2.terminal,
              title: l10n.terminalSection,
              subtitle: l10n.terminalFontSizeValue(backend.terminalFontSize),
              onTap: () => _open(_Section.terminal),
            ),
            _EntryRow(
              glyph: Glyphs2.sun,
              title: l10n.appearanceAndLanguage,
              subtitle:
                  '${_themeLabel(l10n, theme.mode)} · '
                  '${_languageLabel(l10n, theme.locale?.languageCode)}',
              onTap: () => _open(_Section.appearance),
            ),
            _EntryRow(
              glyph: Glyphs2.doc,
              title: l10n.logs,
              subtitle: live ? 'td_logs()' : l10n.unavailable,
              onTap: () => _open(_Section.logs),
            ),
            _EntryRow(
              glyph: Glyphs2.agents,
              title: l10n.about,
              subtitle: l10n.version(appVersion),
              onTap: () => _open(_Section.about),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.session),
        GroupCard(
          dividerInset: 16,
          children: [_SignOutRow(onTap: () => unawaited(_signOut(context)))],
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context) async {
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
}

String _message(Object error) => switch (error) {
  BridgeException() => error.message,
  SshKeyException() => error.reason.name,
  _ => '$error',
};

String _themeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
  ThemeMode.light => l10n.light,
  ThemeMode.dark => l10n.dark,
  ThemeMode.system => l10n.system,
};

String _languageLabel(AppLocalizations l10n, String? code) => switch (code) {
  'en' => l10n.english,
  'zh' => l10n.chinese,
  _ => l10n.system,
};

/// One row of the grouped list: a badge, the section and what it holds now.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Glyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return RowSemantics(
      label: '$title, $subtitle',
      hint: l10n.opensSection,
      onTap: onTap,
      child: TapFeedback(
        onTap: onTap,
        child: ListRow(
          leading: IconBadge(glyph),
          title: Text(title, style: context.listTitleStyle),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.listCaptionStyle,
          ),
          trailing: GlyphIcon(
            Glyphs.chevronForward,
            size: 16,
            color: scheme.onSurfaceVariant.opacity50,
          ),
        ),
      ),
    );
  }
}

/// A page a row opened: its title, a back chevron and the rows themselves.
class _SectionPage extends StatelessWidget {
  const _SectionPage({
    required this.title,
    required this.onBack,
    required this.children,
    this.notice = '',
    this.error = '',
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> children;
  final String notice;
  final String error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return PageBody(
      title: title,
      titleMaxLines: 2,
      leading: IconButton(
        onPressed: onBack,
        icon: const GlyphIcon(Glyphs.chevronBack),
        tooltip: l10n.back,
      ),
      children: [
        if (notice.isNotEmpty) ...[
          InlineNotice(text: notice, tint: scheme.primary),
          const SizedBox(height: 14),
        ],
        if (error.isNotEmpty) ...[
          InlineNotice(text: error),
          const SizedBox(height: 14),
        ],
        ...children,
      ],
    );
  }
}

class _TailnetSection extends StatelessWidget {
  const _TailnetSection({required this.onBack});

  final VoidCallback onBack;

  static String _orDash(String? value) =>
      value == null || value.isEmpty ? '—' : value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final backend = BackendScope.of(context);
    final self = backend.self;
    final online = self?.online ?? false;
    return _SectionPage(
      title: l10n.tailnetAndDevice,
      onBack: onBack,
      children: [
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
            _InfoRow(
              label: l10n.addresses,
              value: _orDash(self?.ip),
              mono: true,
            ),
            _InfoRow(
              label: l10n.status,
              value: online ? l10n.online : l10n.offline,
              tint: online ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ],
    );
  }
}

class _SshIdentitiesSection extends StatefulWidget {
  const _SshIdentitiesSection({
    required this.onBack,
    required this.keys,
    required this.reload,
  });

  final VoidCallback onBack;
  final List<SshIdentity> keys;
  final Future<void> Function() reload;

  @override
  State<_SshIdentitiesSection> createState() => _SshIdentitiesSectionState();
}

class _SshIdentitiesSectionState extends State<_SshIdentitiesSection> {
  String _notice = '';
  String _error = '';
  bool _forgetting = false;

  Future<void> _copy(String text) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _notice = l10n.publicKeyCopied);
  }

  Future<void> _import() async {
    final backend = BackendScope.of(context);
    final identity = await showKeySheet(context, backend);
    if (identity == null || !mounted) return;
    setState(() {
      _notice = AppLocalizations.of(context).keyImported;
      _error = '';
    });
    await widget.reload();
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
      await widget.reload();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _forgetHosts() async {
    if (_forgetting) return;
    final backend = BackendScope.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _forgetting = true;
      _error = '';
    });
    try {
      await backend.forgetSshHostKeys();
      if (mounted) setState(() => _notice = l10n.hostKeysCleared);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _forgetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final backend = BackendScope.of(context);
    final live = backend.available;
    return _SectionPage(
      title: l10n.sshIdentities,
      onBack: widget.onBack,
      notice: _notice,
      error: _error,
      children: [
        GroupCard(
          dividerInset: 60,
          children: [
            if (!live)
              ListRow(
                leading: const IconBadge(Glyphs2.key),
                title: Text(l10n.builtinKey, style: context.listTitleStyle),
                subtitle: Text(
                  l10n.sshNoBackend,
                  style: context.listCaptionStyle,
                ),
              )
            else ...[
              for (final identity in widget.keys)
                _KeyRow(
                  identity: identity,
                  onCopy: identity.publicKey.isEmpty
                      ? null
                      : () => unawaited(_copy(identity.publicKey)),
                  onDelete: identity.builtin
                      ? null
                      : () => unawaited(_delete(identity)),
                ),
              TapFeedback(
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
              TapFeedback(
                onTap: _forgetting ? null : () => unawaited(_forgetHosts()),
                child: ListRow(
                  leading: const IconBadge(Glyphs2.refresh),
                  title: Text(
                    l10n.forgetHostKeys,
                    style: context.listTitleStyle,
                  ),
                  subtitle: Text(
                    l10n.forgetHostKeysHint,
                    style: context.listCaptionStyle,
                  ),
                  trailing: _forgetting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: LoadingIndicator(size: 18),
                        )
                      : null,
                ),
              ),
            ],
          ],
        ),
        if (live) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              l10n.sshKeysHint,
              style: context.listCaptionStyle.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

class _ServicesSection extends StatefulWidget {
  const _ServicesSection({required this.onBack});

  final VoidCallback onBack;

  @override
  State<_ServicesSection> createState() => _ServicesSectionState();
}

class _ServicesSectionState extends State<_ServicesSection> {
  String _notice = '';
  String _error = '';
  bool _refreshing = false;

  Future<void> _refreshIcons() async {
    if (_refreshing) return;
    final l10n = AppLocalizations.of(context);
    final favicons = FaviconsScope.of(context);
    final services = ServicesScope.of(context);
    setState(() {
      _refreshing = true;
      _notice = '';
      _error = '';
    });
    try {
      await favicons.refreshAll(services.all);
      if (mounted) setState(() => _notice = l10n.iconsRefreshed);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final backend = BackendScope.of(context);
    return _SectionPage(
      title: l10n.tabServices,
      onBack: widget.onBack,
      notice: _notice,
      error: _error,
      children: [
        GroupCard(
          dividerInset: 16,
          children: [
            SelectRow<bool>(
              label: l10n.servicesOpen,
              subtitle: backend.openInApp
                  ? (inAppWebViewSupported
                        ? l10n.inAppHint
                        : l10n.inAppDesktopOnly)
                  : null,
              value: backend.openInApp,
              options: [(false, l10n.inBrowser), (true, l10n.inApp)],
              onChanged: (value) => unawaited(backend.setOpenInApp(value)),
            ),
            _IconSwitchRow(
              label: l10n.serviceIcons,
              caption: backend.serviceIcons
                  ? l10n.serviceIconsOn
                  : l10n.serviceIconsOff,
              value: backend.serviceIcons,
              semanticLabel: l10n.a11yServiceIcons(backend.serviceIcons),
              onChanged: (value) => unawaited(backend.setServiceIcons(value)),
            ),
            TapFeedback(
              onTap: _refreshing ? null : () => unawaited(_refreshIcons()),
              child: ListRow(
                leading: const IconBadge(Glyphs2.refresh),
                title: Text(l10n.refreshIcons, style: context.listTitleStyle),
                subtitle: Text(
                  l10n.refreshIconsHint,
                  style: context.listCaptionStyle,
                ),
                trailing: _refreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: LoadingIndicator(size: 18),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection({required this.onBack});

  final VoidCallback onBack;

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  bool _busy = false;
  String _error = '';

  Future<void> _set(bool value) async {
    if (_busy) return;
    final backend = BackendScope.of(context);
    setState(() => _busy = true);
    try {
      await backend.setAgentNotifications(value);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final backend = BackendScope.of(context);
    return _SectionPage(
      title: l10n.notificationsSection,
      onBack: widget.onBack,
      error: _error,
      children: [
        GroupCard(
          dividerInset: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: RowSemantics(
                label: l10n.a11yAgentNotifications(
                  backend.agentNotifications,
                  backend.notifications.denied,
                ),
                onTap: backend.notifications.supported
                    ? () => unawaited(_set(!backend.agentNotifications))
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.agentNotifications,
                            style: context.listTitleStyle,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            !backend.notifications.supported
                                ? l10n.notificationsUnsupported
                                : backend.notifications.denied
                                ? l10n.notificationsDenied
                                : backend.agentNotifications
                                ? l10n.agentNotificationsOn
                                : l10n.agentNotificationsOff,
                            style: context.listCaptionStyle,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_busy)
                      SizedBox(
                        width: 51,
                        height: 31,
                        child: Center(
                          child: LoadingIndicator(
                            size: 18,
                            semanticLabel: l10n.pleaseWait,
                          ),
                        ),
                      )
                    else
                      Switch(
                        value: backend.agentNotifications,
                        onChanged: backend.notifications.supported
                            ? (value) => unawaited(_set(value))
                            : null,
                        semanticLabel: l10n.agentNotifications,
                      ),
                  ],
                ),
              ),
            ),
            if (backend.notifications.supported)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  l10n.nodeNotificationHint,
                  style: context.listCaptionStyle,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TerminalSection extends StatelessWidget {
  const _TerminalSection({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final backend = BackendScope.of(context);
    final keyPages = backend.terminalKeyPages.where((page) => page.isNotEmpty);
    final keyCount = keyPages.fold<int>(0, (sum, page) => sum + page.length);
    return _SectionPage(
      title: l10n.terminalSection,
      onBack: onBack,
      children: [
        GroupCard(
          dividerInset: 16,
          children: [
            _IconSwitchRow(
              label: l10n.terminalKeyHaptics,
              caption: backend.terminalKeyHaptics
                  ? l10n.terminalKeyHapticsOn
                  : l10n.terminalKeyHapticsOff,
              value: backend.terminalKeyHaptics,
              semanticLabel: l10n.a11yTerminalKeyHaptics(
                backend.terminalKeyHaptics,
              ),
              onChanged: (value) =>
                  unawaited(backend.setTerminalKeyHaptics(value)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.terminalFontSize,
                          style: context.listTitleStyle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.terminalFontSizeHint(backend.terminalFontSize),
                          style: context.listCaptionStyle,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _FontStep(
                    glyph: 'A-',
                    label: l10n.terminalFontSmaller,
                    onTap: () => unawaited(
                      backend.setTerminalFontSize(backend.terminalFontSize - 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FontStep(
                    glyph: 'A+',
                    label: l10n.terminalFontLarger,
                    onTap: () => unawaited(
                      backend.setTerminalFontSize(backend.terminalFontSize + 1),
                    ),
                  ),
                ],
              ),
            ),
            _IconSwitchRow(
              label: l10n.terminalSwipeArrows,
              caption: backend.terminalSwipeArrows
                  ? l10n.terminalSwipeArrowsOn
                  : l10n.terminalSwipeArrowsOff,
              value: backend.terminalSwipeArrows,
              semanticLabel: l10n.a11ySwitch(
                l10n.terminalSwipeArrows,
                backend.terminalSwipeArrows,
              ),
              onChanged: (value) =>
                  unawaited(backend.setTerminalSwipeArrows(value)),
            ),
            _IconSwitchRow(
              label: l10n.terminalKeyRowWithKeyboard,
              caption: backend.terminalKeyRowWithKeyboard
                  ? l10n.terminalKeyRowWithKeyboardOn
                  : l10n.terminalKeyRowWithKeyboardOff,
              value: backend.terminalKeyRowWithKeyboard,
              semanticLabel: l10n.a11ySwitch(
                l10n.terminalKeyRowWithKeyboard,
                backend.terminalKeyRowWithKeyboard,
              ),
              onChanged: (value) =>
                  unawaited(backend.setTerminalKeyRowWithKeyboard(value)),
            ),
            TapFeedback(
              onTap: () => unawaited(showTerminalKeysSheet(context, backend)),
              child: ListRow(
                leading: const IconBadge(Glyphs2.terminal),
                title: Text(l10n.terminalKeyRow, style: context.listTitleStyle),
                subtitle: Text(
                  l10n.terminalKeyRowHint(keyCount, keyPages.length),
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
      ],
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({
    required this.onBack,
    required this.theme,
    required this.floatingNavigation,
    required this.onFloatingNavigationChanged,
    required this.tabAnimation,
    required this.onTabAnimationChanged,
  });

  final VoidCallback onBack;
  final TaildeckTheme theme;
  final bool floatingNavigation;
  final ValueChanged<bool> onFloatingNavigationChanged;
  final TabAnimation tabAnimation;
  final ValueChanged<TabAnimation> onTabAnimationChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SectionPage(
      title: l10n.appearanceAndLanguage,
      onBack: onBack,
      children: [
        SectionLabel(l10n.appearance),
        GroupCard(
          dividerInset: 16,
          children: [
            SelectRow<ThemeMode>(
              label: l10n.theme,
              value: theme.mode,
              options: [
                (ThemeMode.system, l10n.system),
                (ThemeMode.light, l10n.light),
                (ThemeMode.dark, l10n.dark),
              ],
              onChanged: theme.setMode,
            ),
            SelectRow<String>(
              label: l10n.language,
              value: switch (theme.locale?.languageCode) {
                'en' => 'en',
                'zh' => 'zh',
                _ => 'system',
              },
              options: [
                ('system', l10n.system),
                ('en', l10n.english),
                ('zh', l10n.chinese),
              ],
              onChanged: (value) => theme.setLocale(switch (value) {
                'en' => const Locale('en'),
                'zh' => const Locale('zh'),
                _ => null,
              }),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.navigation),
        GroupCard(
          dividerInset: 16,
          children: [
            SelectRow<bool>(
              label: l10n.bottomBar,
              subtitle: floatingNavigation
                  ? l10n.floatingHint
                  : l10n.dockedHint,
              value: floatingNavigation,
              options: [(true, l10n.floating), (false, l10n.docked)],
              onChanged: onFloatingNavigationChanged,
            ),
            SelectRow<TabAnimation>(
              label: l10n.tabAnimation,
              subtitle: tabAnimation == TabAnimation.fade
                  ? l10n.fadeHint
                  : l10n.slideHint,
              value: tabAnimation,
              options: [
                (TabAnimation.slide, l10n.slide),
                (TabAnimation.fade, l10n.fade),
              ],
              onChanged: onTabAnimationChanged,
            ),
          ],
        ),
        if (context.disableAnimations) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(l10n.motionHint, style: context.listCaptionStyle),
          ),
        ],
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return _SectionPage(
      title: l10n.about,
      onBack: onBack,
      children: [
        GroupCard(
          dividerInset: 60,
          children: [
            ListRow(
              leading: const IconBadge(Glyphs2.nodes),
              title: Text('Taildeck', style: context.listTitleStyle),
              trailing: Text(
                l10n.version(appVersion),
                style: context.listCaptionStyle,
              ),
            ),
            TapFeedback(
              onTap: () => unawaited(
                launchUrl(
                  Uri.parse(repoUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              child: ListRow(
                leading: const IconBadge(Glyphs2.globe),
                title: Text(l10n.repository, style: context.listTitleStyle),
                subtitle: Text(
                  'markbang/taildeck-ui',
                  style: context.listCaptionStyle,
                ),
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
}

/// A titled switch row, with the switch at the row's end.
class _IconSwitchRow extends StatelessWidget {
  const _IconSwitchRow({
    required this.label,
    required this.caption,
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
  });

  final String label;
  final String caption;
  final bool value;
  final String semanticLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: RowSemantics(
        label: semanticLabel,
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.listTitleStyle),
                  const SizedBox(height: 2),
                  Text(caption, style: context.listCaptionStyle),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged, semanticLabel: label),
          ],
        ),
      ),
    );
  }
}

class _SignOutRow extends StatelessWidget {
  const _SignOutRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return RowSemantics(
      label: l10n.signOut,
      onTap: onTap,
      child: TapFeedback(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.signOut,
                  style: context.listTitleStyle.copyWith(color: scheme.error),
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
    );
  }
}

/// A label and its value, the value ending at the row's edge.
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
    final style = mono
        ? AppTextStyle.footnote
              .of(context)
              .copyWith(fontFamily: 'DejaVuSansMono', fontSize: 11)
        : AppTextStyle.body.of(context);
    return RowSemantics(
      label: '$label, $value',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.listTitleStyle,
              ),
            ),
            const SizedBox(width: 16),
            RowValue(value, style: style, tint: tint),
          ],
        ),
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
      leading: IconBadge(
        Glyphs2.key,
        tint: identity.builtin ? null : scheme.primary,
      ),
      title: Text(
        identity.builtin ? l10n.builtinKey : identity.name,
        style: context.listTitleStyle,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(
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

/// A small square button that steps one number, used for the font size.
class _FontStep extends StatelessWidget {
  const _FontStep({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final String glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: TapFeedback(
        onTap: onTap,
        shape: AppShape.all(8),
        child: Container(
          width: 34,
          height: 30,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: scheme.surfaceContainerHighest,
            shape: AppShape.all(8),
          ),
          child: Text(
            glyph,
            style: context.listTitleStyle.copyWith(fontSize: 13),
          ),
        ),
      ),
    );
  }
}
