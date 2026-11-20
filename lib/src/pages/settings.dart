import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../backend.dart';
import '../data.dart';
import '../favicons.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../log_summary.dart';
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
import '../terminal_appearance.dart';
import 'logs.dart';
import 'theme_page.dart';
import 'terminal_keys_sheet.dart';
import 'terminal_snippets_sheet.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.theme,
    required this.floatingNavigation,
    required this.onFloatingNavigationChanged,
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

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<SshIdentity> _keys = const [];
  bool _keysLoaded = false;
  bool _active = true;
  LogSummary? _logSummary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.valuesOf(context).enabled;
    // The tab keeps its page alive; it opens on the list again.
    if (!_active) _logSummary = null;
    _logSummary ??= _readLogs();
    if (_keysLoaded) return;
    _keysLoaded = true;
    unawaited(_loadKeys());
  }

  LogSummary _readLogs() => summarizeLogs(BackendScope.of(context).logsText());

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

  @override
  Widget build(BuildContext context) {
    // A section may have changed what the list summarises.
    if (_active && _logSummary == null) _logSummary = _readLogs();
    return _list(context);
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
        generateGroup([
          _PageRow(
            glyph: Glyphs2.nodes,
            title: l10n.tailnetAndDevice,
            subtitle: backend.tailnet.isEmpty
                ? l10n.notSignedIn
                : backend.tailnet,
            page: const _TailnetSection(),
          ),
          _PageRow(
            glyph: Glyphs2.key,
            title: l10n.sshIdentities,
            subtitle: live ? l10n.keyCount(_keys.length) : l10n.unavailable,
            page: _SshIdentitiesSection(keys: _keys, reload: _loadKeys),
          ),
          _PageRow(
            glyph: Glyphs2.grid,
            title: l10n.tabServices,
            subtitle: backend.openInApp ? l10n.inApp : l10n.inBrowser,
            page: const _ServicesSection(),
          ),
          _PageRow(
            glyph: Glyphs2.bell,
            title: l10n.notificationsSection,
            subtitle: !backend.notifications.supported
                ? l10n.unavailable
                : backend.agentNotifications
                ? l10n.on
                : l10n.off,
            page: const _NotificationsSection(),
          ),
          _PageRow(
            glyph: Glyphs2.terminal,
            title: l10n.terminalSection,
            subtitle: l10n.terminalFontSizeValue(backend.terminalFontSize),
            page: const _TerminalSection(),
          ),
          _PageRow(
            glyph: Glyphs2.sun,
            title: l10n.theme,
            subtitle: _themeLabel(l10n, theme.mode),
            page: ThemePage(
              theme: widget.theme,
              floatingNavigation: widget.floatingNavigation,
              onFloatingNavigationChanged: widget.onFloatingNavigationChanged,
              tabAnimation: widget.tabAnimation,
              onTabAnimationChanged: widget.onTabAnimationChanged,
            ),
          ),
          SelectRow<String>(
            glyph: Glyphs2.globe,
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
          _PageRow(
            glyph: Glyphs2.doc,
            title: l10n.logs,
            subtitle: _logsSubtitle(l10n, live),
            page: const LogsPage(),
            onClosed: () => setState(() => _logSummary = null),
          ),
          _PageRow(
            glyph: Glyphs2.agents,
            title: l10n.about,
            subtitle: l10n.version(AppInfo.version),
            page: const _AboutSection(),
          ),
        ]),
        const SizedBox(height: 20),
        SectionLabel(l10n.session),
        generateGroup([_SignOutRow(onTap: () => unawaited(_signOut(context)))]),
      ],
    );
  }

  String _logsSubtitle(AppLocalizations l10n, bool live) {
    final summary = _logSummary;
    if (summary != null && summary.lines > 0) {
      return l10n.logsSummary(summary.lines, summary.lastTime);
    }
    return live ? l10n.logsNoEntries : l10n.unavailable;
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

/// One row of the grouped list: a glyph, the section and what it holds now.
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
    return Semantics(
      container: true,
      button: true,
      label: '$title, $subtitle',
      hint: l10n.opensSection,
      onTap: onTap,
      excludeSemantics: true,
      child: DecorationListItem(
        leading: GlyphIcon(glyph),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const GlyphIcon(Glyphs.chevronForward),
        onPressed: onTap,
      ),
    );
  }
}

/// A row that opens [page] by growing its card into it, as FlClash's
/// OpenContainer does: the rows around shift away, the page fades in over the
/// expansion, and back or a drag shrinks the page into the row again.
class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.page,
    this.onClosed,
  });

  final Glyph glyph;
  final String title;
  final String subtitle;
  final Widget page;

  /// Called once the page is closed, so the row's summary can be read again.
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    final position = ItemPositionProvider.of(context)?.position;
    Widget row(VoidCallback onTap) =>
        _EntryRow(glyph: glyph, title: title, subtitle: subtitle, onTap: onTap);
    final onClosed = this.onClosed;
    if (!context.isMobileView) {
      return row(
        () => unawaited(
          BaseNavigator.push<void>(context, page).then((_) => onClosed?.call()),
        ),
      );
    }
    // The widened row is no longer under the group's position provider.
    return OpenContainer<void>(
      clipBehavior: Clip.none,
      transition: OpenContainerTransition.zoom,
      closedShape: position == null
          ? null
          : AppShape.of(listItemRadiusOf(position)),
      closedBuilder: (context, open) => position == null
          ? row(open)
          : ItemPositionProvider(position: position, child: row(open)),
      onClosed: (_) => onClosed?.call(),
      openBuilder: (context, close) => page,
    );
  }
}

/// A page a row opened: its title, a back chevron and the rows themselves.
class _SectionPage extends StatelessWidget {
  const _SectionPage({
    required this.title,
    required this.children,
    this.notice = '',
    this.error = '',
  });

  final String title;
  final List<Widget> children;
  final String notice;
  final String error;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Surface(
      color: SurfaceLevel.page.colorOf(scheme),
      child: PageBody(
        title: title,
        onBack: () => Navigator.maybePop(context),
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
      ),
    );
  }
}

class _TailnetSection extends StatelessWidget {
  const _TailnetSection();

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
      children: [
        SectionLabel(l10n.tailnetSection),
        generateGroup([
          _InfoRow(label: l10n.account, value: _orDash(self?.owner)),
          _InfoRow(label: l10n.tailnetName, value: backend.tailnet),
          _InfoRow(
            label: l10n.controlServer,
            value: backend.controlURL.isEmpty
                ? 'controlplane.tailscale.com'
                : backend.controlURL,
          ),
        ]),
        const SizedBox(height: 20),
        SectionLabel(l10n.thisDeviceSection),
        generateGroup([
          _InfoRow(label: l10n.hostname, value: self?.name ?? backend.hostname),
          _InfoRow(label: l10n.addresses, value: _orDash(self?.ip), mono: true),
          _InfoRow(
            label: l10n.status,
            value: online ? l10n.online : l10n.offline,
            tint: online ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ]),
      ],
    );
  }
}

class _SshIdentitiesSection extends StatefulWidget {
  const _SshIdentitiesSection({required this.keys, required this.reload});

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
    final backend = BackendScope.of(context);
    final live = backend.available;
    return _SectionPage(
      title: l10n.sshIdentities,
      notice: _notice,
      error: _error,
      children: [
        generateGroup([
          if (!live)
            DecorationListItem(
              leading: const GlyphIcon(Glyphs2.key),
              title: Text(l10n.builtinKey),
              subtitle: Text(l10n.sshNoBackend),
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
            DecorationListItem(
              leading: const GlyphIcon(Glyphs2.plus),
              title: Text(l10n.importKey),
              subtitle: Text(
                l10n.privateKeyHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => unawaited(_import()),
            ),
            DecorationListItem(
              leading: const GlyphIcon(Glyphs2.refresh),
              title: Text(l10n.forgetHostKeys),
              subtitle: Text(l10n.forgetHostKeysHint),
              trailing: _forgetting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: LoadingIndicator(size: 18),
                    )
                  : null,
              onPressed: _forgetting ? null : () => unawaited(_forgetHosts()),
            ),
          ],
        ]),
        if (live) ListFooter(text: l10n.sshKeysHint),
      ],
    );
  }
}

class _ServicesSection extends StatefulWidget {
  const _ServicesSection();

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
      notice: _notice,
      error: _error,
      children: [
        generateGroup([
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
          DecorationListItem(
            leading: const GlyphIcon(Glyphs2.refresh),
            title: Text(l10n.refreshIcons),
            subtitle: Text(l10n.refreshIconsHint),
            trailing: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: LoadingIndicator(size: 18),
                  )
                : null,
            onPressed: _refreshing ? null : () => unawaited(_refreshIcons()),
          ),
        ]),
      ],
    );
  }
}

class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection();

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
      error: _error,
      children: [
        generateGroup([
          Semantics(
            label: l10n.a11yAgentNotifications(
              backend.agentNotifications,
              backend.notifications.denied,
            ),
            child: DecorationListItem(
              title: Text(l10n.agentNotifications),
              subtitle: Text(
                !backend.notifications.supported
                    ? l10n.notificationsUnsupported
                    : backend.notifications.denied
                    ? l10n.notificationsDenied
                    : backend.agentNotifications
                    ? l10n.agentNotificationsOn
                    : l10n.agentNotificationsOff,
              ),
              trailing: _busy
                  ? SizedBox(
                      width: 51,
                      height: 31,
                      child: Center(
                        child: LoadingIndicator(
                          size: 18,
                          semanticLabel: l10n.pleaseWait,
                        ),
                      ),
                    )
                  : Switch(
                      value: backend.agentNotifications,
                      onChanged: backend.notifications.supported
                          ? (value) => unawaited(_set(value))
                          : null,
                      semanticLabel: l10n.agentNotifications,
                    ),
              onPressed: backend.notifications.supported
                  ? () => unawaited(_set(!backend.agentNotifications))
                  : null,
            ),
          ),
        ]),
        if (backend.notifications.supported)
          ListFooter(text: l10n.nodeNotificationHint),
      ],
    );
  }
}

class _TerminalSection extends StatelessWidget {
  const _TerminalSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final backend = BackendScope.of(context);
    final keyPages = backend.terminalKeyPages.where((page) => page.isNotEmpty);
    final keyCount = keyPages.fold<int>(0, (sum, page) => sum + page.length);
    return _SectionPage(
      title: l10n.terminalSection,
      children: [
        generateGroup([
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
          DecorationListItem(
            title: Text(l10n.terminalFontSize),
            subtitle: Text(l10n.terminalFontSizeHint(backend.terminalFontSize)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                _FontStep(
                  glyph: 'A-',
                  label: l10n.terminalFontSmaller,
                  onTap: () => unawaited(
                    backend.setTerminalFontSize(backend.terminalFontSize - 1),
                  ),
                ),
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
          SelectRow<TerminalThemeId>(
            label: l10n.terminalColors,
            value: backend.terminalTheme,
            options: [
              (TerminalThemeId.follow, l10n.terminalThemeFollow),
              (TerminalThemeId.taildeck, l10n.terminalThemeTaildeck),
              (TerminalThemeId.midnight, l10n.terminalThemeMidnight),
              (TerminalThemeId.paper, l10n.terminalThemePaper),
              (TerminalThemeId.solarizedDark, l10n.terminalThemeSolarizedDark),
              (
                TerminalThemeId.solarizedLight,
                l10n.terminalThemeSolarizedLight,
              ),
            ],
            onChanged: (value) => unawaited(backend.setTerminalTheme(value)),
          ),
          SelectRow<TerminalFontId>(
            label: l10n.terminalFontFamily,
            value: backend.terminalFont,
            options: [
              (TerminalFontId.dejavu, l10n.terminalFontDejavu),
              (TerminalFontId.systemMono, l10n.terminalFontSystem),
              (TerminalFontId.sans, l10n.terminalFontSans),
            ],
            onChanged: (value) => unawaited(backend.setTerminalFont(value)),
          ),
          SelectRow<TerminalCursorId>(
            label: l10n.terminalCursorLabel,
            value: backend.terminalCursor,
            options: [
              (TerminalCursorId.follow, l10n.terminalCursorFollow),
              (TerminalCursorId.block, l10n.terminalCursorBlock),
              (TerminalCursorId.bar, l10n.terminalCursorBar),
              (TerminalCursorId.underline, l10n.terminalCursorUnderline),
            ],
            onChanged: (value) => unawaited(backend.setTerminalCursor(value)),
          ),
          _IconSwitchRow(
            label: l10n.terminalCursorBlink,
            caption: backend.terminalCursorBlink
                ? l10n.terminalCursorBlinkOn
                : l10n.terminalCursorBlinkOff,
            value: backend.terminalCursorBlink,
            semanticLabel: l10n.a11ySwitch(
              l10n.terminalCursorBlink,
              backend.terminalCursorBlink,
            ),
            onChanged: (value) =>
                unawaited(backend.setTerminalCursorBlink(value)),
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
          _IconSwitchRow(
            label: l10n.terminalKeepAlive,
            caption: backend.terminalKeepAlive
                ? l10n.terminalKeepAliveOn
                : l10n.terminalKeepAliveOff,
            value: backend.terminalKeepAlive,
            semanticLabel: l10n.a11ySwitch(
              l10n.terminalKeepAlive,
              backend.terminalKeepAlive,
            ),
            onChanged: (value) =>
                unawaited(backend.setTerminalKeepAlive(value)),
          ),
          if (backend.batteryExempt case final exempt?)
            DecorationListItem(
              title: Text(l10n.batteryExempt),
              subtitle: Text(
                exempt ? l10n.batteryExemptOn : l10n.batteryExemptOff,
              ),
              trailing: exempt ? null : const GlyphIcon(Glyphs.chevronForward),
              onPressed: exempt
                  ? null
                  : () => unawaited(backend.requestBatteryExempt()),
            ),

          DecorationListItem(
            leading: const GlyphIcon(Glyphs2.bolt),
            title: Text(l10n.terminalSnippets),
            subtitle: Text(
              backend.terminalSnippets.isEmpty
                  ? l10n.terminalSnippetsEmpty
                  : l10n.terminalSnippetsHint(backend.terminalSnippets.length),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const GlyphIcon(Glyphs.chevronForward),
            onPressed: () =>
                unawaited(showTerminalSnippetsSheet(context, backend: backend)),
          ),
          DecorationListItem(
            leading: const GlyphIcon(Glyphs2.terminal),
            title: Text(l10n.terminalKeyRow),
            subtitle: Text(l10n.terminalKeyRowHint(keyCount, keyPages.length)),
            trailing: const GlyphIcon(Glyphs.chevronForward),
            onPressed: () => unawaited(showTerminalKeysSheet(context, backend)),
          ),
        ]),
        ListFooter(text: l10n.terminalKeepAliveLimits),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SectionPage(
      title: l10n.about,
      children: [
        generateGroup([
          DecorationListItem(
            leading: const GlyphIcon(Glyphs2.nodes),
            title: const Text('Taildeck'),
            trailing: Text(l10n.version(AppInfo.version)),
          ),
          DecorationListItem(
            leading: const GlyphIcon(Glyphs2.globe),
            title: Text(l10n.repository),
            subtitle: const Text('markbang/taildeck-ui'),
            trailing: const GlyphIcon(Glyphs.chevronForward),
            onPressed: () => unawaited(
              launchUrl(
                Uri.parse(repoUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
          DecorationListItem(
            leading: const GlyphIcon(Glyphs2.agents),
            title: const Text('prism_ui'),
            trailing: const Text('0.1.2'),
          ),
        ]),
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
    return DecorationListItem(
      title: Text(label),
      subtitle: Text(caption),
      trailing: Semantics(
        label: semanticLabel,
        child: Switch(value: value, onChanged: onChanged, semanticLabel: label),
      ),
      onPressed: () => onChanged(!value),
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
    return DecorationListItem(
      title: Text(
        l10n.signOut,
        style: context.listTitleStyle.copyWith(color: scheme.error),
      ),
      trailing: GlyphIcon(Glyphs.chevronForward, color: scheme.error),
      onPressed: onTap,
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
    return DecorationListItem(
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: RowValue(value, style: style, tint: tint),
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
    return DecorationListItem(
      leading: const GlyphIcon(Glyphs2.key),
      title: Text(identity.builtin ? l10n.builtinKey : identity.name),
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
