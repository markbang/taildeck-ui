import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import 'a11y.dart';
import 'back.dart';
import 'backend.dart';
import 'connection_memory.dart';
import 'data.dart';
import 'demo/demo.dart';
import 'demo/demo_herdr.dart';
import 'herdr.dart';
import 'preview_env.dart';
import 'glyphs.dart';
import 'l10n.dart';
import 'motion.dart';
import 'native/bridge.dart';
import 'notifications.dart';
import 'pages/agent_chat.dart';
import 'pages/agents.dart';
import 'pages/key_sheet.dart';
import 'pages/new_agent_sheet.dart';
import 'pages/node_detail.dart';
import 'pages/nodes.dart';
import 'pages/service_sheet.dart';
import 'pages/services.dart';
import 'pages/ssh_sheet.dart';
import 'pages/login.dart';
import 'pages/settings.dart';
import 'splash.dart';
import 'pages/terminal.dart';
import 'terminal_appearance.dart';
import 'terminal_store.dart';
import 'theme.dart';

enum TabAnimation { slide, fade }

class TaildeckShell extends StatefulWidget {
  const TaildeckShell({super.key, required this.theme});

  final TaildeckTheme theme;

  @override
  State<TaildeckShell> createState() => _TaildeckShellState();
}

class _TaildeckShellState extends State<TaildeckShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _tabs = 4;

  int _tab = (int.tryParse(previewParam('tab') ?? '') ?? 0).clamp(0, _tabs - 1);
  NodeItem? _node;

  /// The node page opened from a saved ping: it pings on open.
  bool _pingOnOpen = false;

  /// Devices dialing their saved connection; their rows say so.
  final Set<String> _connecting = {};
  bool _floating = previewParam('nav') != 'docked';
  TabAnimation _animation = previewParam('anim') == 'fade'
      ? TabAnimation.fade
      : TabAnimation.slide;
  bool _sidebarExpanded = true;
  // Mock/preview sign-in; the native backend reports its own state.
  bool _previewSignedIn = switch (previewParam('login')) {
    null || '0' => true,
    _ => false,
  };
  // `?preview=1`: show the signed-in shell without a live node, so pages that
  // need a tailnet (settings, logs) can be reviewed on a desk.
  final bool _previewShell = previewParam('preview') == '1';
  final _terminals = TerminalStore();
  final _exit = ExitGuard();
  // The terminal page currently open; its session lives on in [_terminals].
  SshTerminal? _attached;
  final bool _sshDemo = previewParam('ssh') == 'demo';
  // `?chat=<pane>&herdr=demo`: the chat page against a herdr held in memory.
  final HerdrController? _demoHerdr =
      demoData && previewParam('herdr') == 'demo'
      ? demoHerdr(
          status: previewParam('status') ?? 'working',
          failModel: previewParam('modelfail') == '1',
        )
      : null;

  /// Depth of the scene on screen, so the next swap knows its direction.
  int _sceneDepth = 0;
  String _sceneKey = 'boot';
  bool _previewSheetOpened = false;
  bool _previewNodeDone = false;
  AgentNotifications? _alerts;

  static NodeItem? _querySsh() {
    final name = previewParam('ssh');
    if (name == null || !demoData) return null;
    if (name == 'demo') return demoNode;
    for (final node in [demoSelfNode, ...demoPeers]) {
      if (node.name == name) return node;
    }
    return null;
  }

  /// `?node=<name>` opens that node's page on launch and `?node=*` the first
  /// one the tailnet lists, so a smoke test can reach the page without taps.
  /// The list arrives after the first frame, so this runs again on each change.
  void _openPreviewNode() {
    final name = previewParam('node');
    if (name == null || _node != null || _previewNodeDone || !mounted) return;
    final backend = BackendScope.of(context);
    // A backend that started but has no tailnet yet lists nothing; the preview
    // then falls back to the demo nodes, which is what the smoke gates expect.
    final nodes = backend.available && backend.nodes.isNotEmpty
        ? backend.nodes
        : (demoData ? [demoSelfNode, ...demoPeers] : const <NodeItem>[]);
    if (nodes.isEmpty) return;
    _previewNodeDone = true;
    for (final node in nodes) {
      if (name == '*' || node.name == name) {
        debugPrint('taildeck preview: node=${node.name}');
        setState(() => _node = node);
        return;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _terminals.addListener(_onTerminalsChanged);
    _demoHerdr?.addListener(_onDemoHerdr);
    final node = _querySsh();
    if (node != null) {
      _attached = _terminals.open(
        node: node,
        credentials: const SshCredentials(user: 'root', port: 22),
      );
    }
  }

  /// Background keep-alive off: the app leaves the foreground and its SSH
  /// sessions end with it, as the setting says they will.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      return;
    }
    if (BackendScope.of(context).terminalKeepAlive) return;
    if (_terminals.isEmpty) return;
    setState(() => _attached = null);
    _terminals.closeAll();
  }

  void _onTerminalsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final alerts = BackendScope.of(context).notifications;
    if (!identical(alerts, _alerts)) {
      _alerts?.removeListener(_openTappedPane);
      _alerts = alerts..addListener(_openTappedPane);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openTappedPane();
      _openPreviewNode();
      unawaited(_openPreviewSheet());
    });
  }

  void _onDemoHerdr() {
    if (_demoHerdr?.ready != true) return;
    _demoHerdr?.removeListener(_onDemoHerdr);
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _demoHerdr?.removeListener(_onDemoHerdr);
    _alerts?.removeListener(_openTappedPane);
    _terminals
      ..removeListener(_onTerminalsChanged)
      ..dispose();
    super.dispose();
  }

  /// A notification tap names a pane; its chat opens, or the Agents tab does
  /// when that pane is gone.
  void _openTappedPane() {
    final pane = _alerts?.takePendingPane();
    if (pane == null || !mounted) return;
    final backend = BackendScope.of(context);
    if (!_previewShell && backend.available && !backend.signedIn) return;
    final herdr = backend.herdr;
    final agent = herdr?.agents
        .where((item) => item.paneId == pane)
        .firstOrNull;
    if (herdr == null || agent == null) {
      _toPage(2);
      return;
    }
    unawaited(
      BaseNavigator.push<void>(
        context,
        AgentChatPage(agent: agent, herdr: herdr),
      ),
    );
  }

  void _toPage(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
      if (index != 0) _node = null;
    });
  }

  /// Esc leaves the terminal and node detail, the two pages the shell opens
  /// over itself; sheets and dialogs answer Esc on their own routes.
  void _handleEscape() {
    if (_attached != null) {
      _leaveTerminal();
      return;
    }
    if (_node != null) setState(() => _node = null);
  }

  /// The system back button: keyboard, then the tab's open page, then the
  /// first tab, then a second press to leave. Sheets, dialogs and popup menus
  /// are routes above this one, so they pop before the shell hears the press.
  void _handleBack() {
    if (hideKeyboard(context)) {
      logBack(BackStep.keyboard);
      return;
    }
    if (_attached != null) {
      logBack(BackStep.page);
      _leaveTerminal();
      return;
    }
    if (_node != null) {
      logBack(BackStep.page);
      setState(() => _node = null);
      return;
    }
    if (_tab != 0) {
      logBack(BackStep.tab);
      _toPage(0);
      return;
    }
    if (_exit.press()) {
      logBack(BackStep.exit);
      unawaited(leaveApp());
      return;
    }
    logBack(BackStep.askExit);
    showExitHint(context);
  }

  void _attach(SshTerminal terminal) => setState(() => _attached = terminal);

  /// Leaving the terminal keeps the shell running; back from it reattaches.
  void _leaveTerminal() {
    final terminal = _attached;
    if (terminal == null) return;
    setState(() => _attached = null);
    if (!terminal.live) _terminals.disconnect(terminal);
  }

  void _disconnectTerminal(SshTerminal terminal) {
    if (_attached == terminal) setState(() => _attached = null);
    _terminals.disconnect(terminal);
  }

  /// The session dropped: dial the same node again with the login and secret
  /// this session already used, without showing the sheet. The old session
  /// stays on screen (and in the strip) if the retry fails, so the next tap
  /// can try again.
  Future<void> _reconnectTerminal(SshTerminal terminal) async {
    final backend = BackendScope.of(context);
    final retried = await _dial(terminal.node, terminal.credentials);
    if (!mounted || retried == null) return;
    if (_attached == terminal) _leaveTerminal();
    _attach(retried);
    if (backend.available && terminal.live) {
      _terminals.disconnect(terminal);
    }
  }

  /// Opens a session for [node] with [credentials]; null when the dial failed.
  Future<SshTerminal?> _dial(NodeItem node, SshCredentials credentials) async {
    final backend = BackendScope.of(context);
    final palette = terminalPaletteOf(
      backend.terminalTheme,
      Theme.of(context).brightness,
    );
    if (!backend.available) {
      return _terminals.open(
        node: node,
        credentials: credentials,
        palette: palette,
      );
    }
    try {
      final session = await backend.openSshSession(
        host: node.name,
        user: credentials.user,
        port: credentials.port,
        password: credentials.password,
        identityId: credentials.identityId,
      );
      return _terminals.open(
        node: node,
        credentials: credentials,
        session: session,
        palette: palette,
      );
    } on Object {
      // The header keeps the dropped session and its Retry button, so the
      // user can try again without leaving the page.
      return null;
    }
  }

  /// The agents action in the terminal bar, as in the Kotlin app.
  void _openAgents(SshTerminal terminal) {
    _leaveTerminal();
    _toPage(2);
  }

  /// A tap on a device: its saved connection when there is one, else the
  /// node page with its actions.
  void _tapNode(NodeItem node) {
    final saved = BackendScope.of(context).connectionFor(node);
    switch (planTap(saved)) {
      case TapPlan.menu:
        _openMenu(node);
      case TapPlan.ping:
        setState(() {
          _node = node;
          _pingOnOpen = true;
        });
      case TapPlan.dial:
      case TapPlan.sheet:
        unawaited(_openSsh(node));
    }
  }

  void _openMenu(NodeItem node) => setState(() {
    _node = node;
    _pingOnOpen = false;
  });

  /// A ping that answered becomes the device's tap action, unless it already
  /// has one.
  void _onPinged(NodeItem node) {
    final backend = BackendScope.of(context);
    if (backend.connectionFor(node)?.ready ?? false) return;
    unawaited(
      backend.rememberConnection(
        node,
        const SavedConnection(action: ConnectionAction.ping),
      ),
    );
  }

  /// Reattaches a running shell, else dials the saved connection; the sheet
  /// opens first time, for a password, on [edit], and when the saved
  /// connection fails.
  Future<void> _openSsh(NodeItem node, {bool edit = false}) async {
    final existing = _terminals.forNode(node.name);
    if (!edit && existing != null && !existing.closed) {
      _attach(existing);
      return;
    }
    final backend = BackendScope.of(context);
    final saved = backend.connectionFor(node);
    if (edit || saved == null || planTap(saved) != TapPlan.dial) {
      _openTerminal(node, await showSshSheet(context, node));
      return;
    }
    final key = deviceKey(node);
    if (!_connecting.add(key)) return;
    setState(() {});
    final choice = await connectRemembered<SshChoice>(
      saved: saved,
      dial: (saved) => _dialSaved(node, saved),
      openSheet: (error) {
        if (!mounted) return Future<SshChoice?>.value();
        setState(() => _connecting.remove(key));
        final message = error is BridgeException ? error.message : '$error';
        return showSshSheet(
          context,
          node,
          error: sshFailureText(
            AppLocalizations.of(context),
            node.name,
            message,
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _connecting.remove(key));
    _openTerminal(node, choice);
  }

  Future<SshChoice> _dialSaved(NodeItem node, SavedConnection saved) async {
    final backend = BackendScope.of(context);
    final session = backend.available
        ? await backend.openSshSession(
            host: node.name,
            user: saved.user,
            port: saved.port,
            identityId: saved.dialIdentity,
          )
        : null;
    return (
      user: saved.user,
      port: saved.port,
      auth: saved.auth ?? SshAuth.tailscale,
      password: '',
      identityId: saved.dialIdentity,
      session: session,
    );
  }

  void _openTerminal(NodeItem node, SshChoice? choice) {
    if (choice == null || !mounted) return;
    _attach(
      _terminals.open(
        node: node,
        credentials: SshCredentials(
          user: choice.user,
          port: choice.port,
          password: choice.password,
          identityId: choice.identityId,
        ),
        session: choice.session,
        palette: terminalPaletteOf(
          BackendScope.of(context).terminalTheme,
          Theme.of(context).brightness,
        ),
      ),
    );
  }

  /// `?sheet=ssh|service|agent|key|dialog` opens one sheet on the preview
  /// build, so the back key can be tried without tapping the page.
  Future<void> _openPreviewSheet() async {
    final which = previewParam('sheet');
    if (which == null || _previewSheetOpened || !mounted) return;
    final backend = BackendScope.of(context);
    if (!_previewShell && backend.available && !backend.signedIn) return;
    _previewSheetOpened = true;
    // The ssh and service sheets need a node: the open page, the tailnet's own,
    // or the demo one in a build that still carries it. The key sheet needs
    // none, so a release build opens it too.
    final node = _node ?? backend.self ?? (demoData ? demoSelfNode : null);
    if (node == null && which != 'key') return;
    final l10n = AppLocalizations.of(context);
    debugPrint('taildeck preview: sheet=$which');
    switch (which) {
      case 'ssh':
        await showSshSheet(context, node!);
      case 'service':
        await showServiceSheet(context, nodes: [node!]);
      case 'agent':
        await showNewAgentSheet(context);
      case 'key':
        await showKeySheet(context, BackendScope.of(context));
      case 'dialog':
        await showFloatingDialog<bool>(
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
            child: Text(l10n.deleteKeyConfirm('taildeck')),
          ),
        );
    }
    debugPrint('taildeck preview: sheet closed');
  }

  void _signOut() {
    // A settings page open over the shell goes with the session.
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(BackendScope.of(context).signOut());
    final terminals = _terminals.all.toList();
    setState(() {
      _previewSignedIn = false;
      _tab = 0;
      _node = null;
      _attached = null;
    });
    for (final terminal in terminals) {
      _terminals.disconnect(terminal);
    }
  }

  @override
  Widget build(BuildContext context) => _backScope(_content(context));

  /// One place for the system back button: [canPop] stays false so every
  /// press comes here, and [_handleBack] decides how far it goes.
  Widget _backScope(Widget child) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: child,
    );
  }

  /// A full-screen scene and where it sits in the stack: 0 login, 1 the tab
  /// shell, 2 the pages opened over it.
  ({String key, int depth, Widget child}) _scene(BuildContext context) {
    final scheme = context.colorScheme;
    final mobile = ViewScope.isMobileOf(context);
    final backend = BackendScope.of(context);
    // The saved login is still being read: stay on the launch screen's colour
    // rather than guess, so the login page cannot flash before the answer.
    if (backend.available && !_previewShell && !backend.sessionKnown) {
      return (
        key: 'boot',
        depth: 0,
        child: const ColoredBox(color: splashBackground),
      );
    }
    final signedIn = _previewShell
        ? _previewSignedIn
        : (backend.available ? backend.showShell : _previewSignedIn);
    if (!signedIn) {
      return (
        key: 'login',
        depth: 0,
        child: LoginPage(
          onSignedIn: () => setState(() => _previewSignedIn = true),
        ),
      );
    }
    // `?chat=<pane>`: open a pane's chat on the preview build. Without a
    // herdr connection the page shows its real error state; `?status=` fakes
    // the agent's state so the queue chip can be reviewed on a desk.
    final previewChat = previewParam('chat');
    final herdr = _demoHerdr ?? backend.herdr;
    if (previewChat != null && _demoHerdr?.ready == false) {
      return (key: 'boot', depth: 0, child: const SizedBox.shrink());
    }
    if (previewChat != null && herdr != null) {
      return (
        key: 'chat',
        depth: 2,
        child: AgentChatPage(
          agent: HerdrAgent(
            paneId: previewChat,
            kind: previewParam('kind') ?? 'claude',
            label: previewChat,
            status: HerdrStatus.of(previewParam('status') ?? ''),
            workspace: '',
          ),
          herdr: herdr,
          demoQueue: [
            for (final text in (previewParam('queue') ?? '').split('|'))
              if (text.trim().isNotEmpty) text.trim(),
          ],
        ),
      );
    }
    final terminal = _attached;
    if (terminal != null) {
      return (
        key: 'terminal',
        depth: 2,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
          },
          child: TerminalPage(
            key: ValueKey(terminal),
            node: terminal.node,
            user: terminal.user,
            port: terminal.port,
            terminal: terminal,
            demo: _sshDemo,
            onClose: _leaveTerminal,
            onDisconnect: terminal.live
                ? () => _disconnectTerminal(terminal)
                : null,
            onReconnect: terminal.live
                ? () => unawaited(_reconnectTerminal(terminal))
                : null,
            onAgents: () => _openAgents(terminal),
            sessions: _terminals.all.toList(),
            onSwitch: _attach,
          ),
        ),
      );
    }
    final l10n = AppLocalizations.of(context);
    final items = <({Glyph glyph, String label})>[
      (glyph: Glyphs2.nodes, label: l10n.tabNodes),
      (glyph: Glyphs2.grid, label: l10n.tabServices),
      (glyph: Glyphs2.agents, label: l10n.tabAgents),
      (glyph: Glyphs2.sliders, label: l10n.tabSettings),
    ];
    final dockInset = mobile && _floating
        ? NavigationDock.insetOf(context)
        : 0.0;
    return (
      key: 'shell',
      depth: 1,
      child: Surface(
        color: SurfaceLevel.page.colorOf(scheme),
        child: Row(
          children: [
            AnimatedVisibility.sidebar(
              visible: !mobile,
              child: Surface(
                color: scheme.chromeSurface,
                shape: BorderDirectional(
                  end: Divider.createBorderSide(context),
                ),
                child: NavigationSidebar(
                  destinations: [
                    for (final item in items)
                      SidebarDestination(glyph: item.glyph, label: item.label),
                  ],
                  selectedIndex: _tab,
                  expanded: _sidebarExpanded,
                  onSelected: _toPage,
                  onToggle: () =>
                      setState(() => _sidebarExpanded = !_sidebarExpanded),
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: BottomInsetScope(
                            inset: dockInset,
                            child: _BodyPadding(
                              isMobile: mobile,
                              child: CallbackShortcuts(
                                bindings: {
                                  const SingleActivator(
                                    LogicalKeyboardKey.escape,
                                  ): _handleEscape,
                                },
                                child: _pages(),
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          start: 0,
                          end: 0,
                          bottom: 0,
                          child: AnimatedVisibility.bottomNavigation(
                            visible: mobile && _floating,
                            child: BarItemPresence.held(
                              child: _NavigationPadding(
                                child: NavigationDock(
                                  destinations: [
                                    for (final item in items)
                                      NavigationDockDestination(
                                        glyph: item.glyph,
                                        label: item.label,
                                      ),
                                  ],
                                  selectedIndex: _tab,
                                  onSelected: _toPage,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedVisibility.bottomNavigation(
                    visible: mobile && !_floating,
                    child: _NavigationPadding(
                      child: NavigationBar(
                        destinations: [
                          for (final (index, item) in items.indexed)
                            NavigationDestination(
                              icon: AnimatedGlyph(
                                glyph: item.glyph,
                                filled: index == _tab,
                              ),
                              label: item.label,
                            ),
                        ],
                        selectedIndex: _tab,
                        onDestinationSelected: _toPage,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const _StatusLive(),
          ],
        ),
      ),
    );
  }

  /// Scenes swap like routes: a push comes in from the right, a pop from the
  /// left. The depth is read during build only to decide the direction.
  Widget _content(BuildContext context) {
    final scene = _scene(context);
    if (scene.key != _sceneKey) debugPrint('taildeck route: ${scene.key}');
    // The first route appears under the launch screen, so it must not slide
    // or scale in: the splash hands straight over to it.
    final fromBoot = _sceneKey == 'boot';
    final forward = scene.depth >= _sceneDepth;
    // Signing in scales the shell up instead of sliding it in.
    final fadeThrough = scene.key == 'shell' && _sceneKey == 'login';
    _sceneDepth = scene.depth;
    _sceneKey = scene.key;
    final child = KeyedSubtree(key: ValueKey(scene.key), child: scene.child);
    if (fromBoot) return child;
    return MotionSwitcher(
      forward: forward,
      fadeThrough: fadeThrough,
      child: child,
    );
  }

  Widget _pages() {
    return TabSwitcher(
      index: _tab,
      count: _tabs,
      background: SurfaceLevel.page.colorOf(context.colorScheme),
      fade: _animation == TabAnimation.fade,
      animate: ViewScope.isMobileOf(context),
      pageBuilder: (context, index) => _pageAt(index),
    );
  }

  Widget _pageAt(int index) {
    switch (index) {
      case 1:
        return const ServicesPage();
      case 2:
        return const AgentsPage();
      case 3:
        return SettingsPage(
          theme: widget.theme,
          floatingNavigation: _floating,
          onFloatingNavigationChanged: (value) =>
              setState(() => _floating = value),
          tabAnimation: _animation,
          onTabAnimationChanged: (value) => setState(() => _animation = value),
          onSignOut: _signOut,
        );
      default:
        final node = _node;
        if (node == null) {
          return NodesPage(
            onOpenNode: _tapNode,
            onNodeActions: _openMenu,
            connecting: _connecting,
            onToggleTheme: widget.theme.toggle,
          );
        }
        final session = _terminals.forNode(node.name);
        return NodeDetailPage(
          node: node,
          previewPing: previewParam('ping') == '1',
          pingOnOpen: _pingOnOpen,
          onPinged: () => _onPinged(node),
          session: session == null || session.closed ? null : session,
          onBack: () => setState(() => _node = null),
          onOpenAgents: () => _toPage(2),
          onOpenSsh: () => unawaited(_openSsh(node)),
          onEditConnection:
              BackendScope.of(context).connectionFor(node)?.auth != null
              ? () => unawaited(_openSsh(node, edit: true))
              : null,
          onDisconnectSsh: session == null
              ? null
              : () => _disconnectTerminal(session),
        );
    }
  }
}

class _BodyPadding extends StatelessWidget {
  const _BodyPadding({required this.isMobile, required this.child});

  final bool isMobile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      removeTop: false,
      removeBottom: isMobile,
      removeLeft: isMobile,
      removeRight: isMobile,
      context: context,
      child: child,
    );
  }
}

class _NavigationPadding extends StatelessWidget {
  const _NavigationPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      removeTop: true,
      removeBottom: false,
      removeLeft: true,
      removeRight: true,
      context: context,
      child: child,
    );
  }
}

/// Announces the backend's state and each node's online/offline change through
/// one throttled live region, so a screen reader hears what the dots show.
class _StatusLive extends StatefulWidget {
  const _StatusLive();

  @override
  State<_StatusLive> createState() => _StatusLiveState();
}

class _StatusLiveState extends State<_StatusLive> {
  BackendState? _state;
  Map<String, bool> _online = const {};
  String _message = '';

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    final l10n = AppLocalizations.of(context);
    final found = <String>[];
    if (backend.available) {
      final state = backend.state;
      if (_state != null && state != _state) {
        found.add(switch (state) {
          BackendState.running => l10n.a11yTailnetConnected,
          BackendState.stopped || BackendState.error => l10n.a11yTailnetOffline,
          BackendState.starting ||
          BackendState.needsLogin => l10n.a11yTailnetStarting,
          BackendState.unavailable => '',
        });
      }
      _state = state;
      final online = {for (final node in backend.nodes) node.name: node.online};
      for (final node in online.entries) {
        final was = _online[node.key];
        if (was == null || was == node.value) continue;
        found.add(
          node.value
              ? l10n.a11yNodeOnline(node.key)
              : l10n.a11yNodeOffline(node.key),
        );
      }
      _online = online;
    }
    if (found.isNotEmpty) {
      _message = found.where((line) => line.isNotEmpty).join('; ');
    }
    return LiveRegion(message: _message);
  }
}
