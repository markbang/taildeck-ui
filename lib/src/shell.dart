import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import 'a11y.dart';
import 'backend.dart';
import 'data.dart';
import 'herdr.dart';
import 'preview_env.dart';
import 'glyphs.dart';
import 'l10n.dart';
import 'native/ssh.dart';
import 'pages/agent_chat.dart';
import 'pages/agents.dart';
import 'pages/node_detail.dart';
import 'pages/nodes.dart';
import 'pages/services.dart';
import 'pages/ssh_sheet.dart';
import 'pages/login.dart';
import 'pages/settings.dart';
import 'pages/terminal.dart';
import 'theme.dart';

enum TabAnimation { slide, fade }

class TaildeckShell extends StatefulWidget {
  const TaildeckShell({super.key, required this.theme});

  final TaildeckTheme theme;

  @override
  State<TaildeckShell> createState() => _TaildeckShellState();
}

class _TaildeckShellState extends State<TaildeckShell>
    with SingleTickerProviderStateMixin {
  static const _tabs = 4;

  int _tab = (int.tryParse(previewParam('tab') ?? '') ?? 0).clamp(0, _tabs - 1);
  NodeItem? _node = _queryNode();
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
  NodeItem? _sshNode = _querySsh();
  bool _sshDemo = previewParam('ssh') == 'demo';
  String _sshUser = 'root';
  int _sshPort = 22;
  SshSession? _sshSession;

  late final PageController _pageController = PageController(initialPage: _tab);

  static NodeItem? _querySsh() {
    final name = previewParam('ssh');
    if (name == null) return null;
    if (name == 'demo') return demoNode;
    for (final node in [selfNode, ...peers]) {
      if (node.name == name) return node;
    }
    return null;
  }

  static NodeItem? _queryNode() {
    final name = previewParam('node');
    if (name == null) return null;
    for (final node in [selfNode, ...peers]) {
      if (node.name == name) return node;
    }
    return null;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toPage(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
      if (index != 0) _node = null;
    });
    if (!_pageController.hasClients) return;
    if (context.disableAnimations) {
      _pageController.jumpToPage(index);
      return;
    }
    if (ViewScope.isMobileOf(context)) {
      final fade = _animation == TabAnimation.fade;
      _pageController.animateToPage(
        index,
        duration: fade ? fadeTabDuration : kTabScrollDuration,
        curve: fade ? fadeTabCurve : Curves.easeOut,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  /// Esc leaves the terminal and node detail, the two pages the shell opens
  /// over itself; sheets and dialogs answer Esc on their own routes.
  void _handleEscape() {
    if (_sshNode != null) {
      setState(() {
        _sshNode = null;
        _sshSession = null;
      });
      return;
    }
    if (_node != null) setState(() => _node = null);
  }

  void _signOut() {
    unawaited(BackendScope.of(context).signOut());
    setState(() {
      _previewSignedIn = false;
      _tab = 0;
      _node = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final mobile = ViewScope.isMobileOf(context);
    final backend = BackendScope.of(context);
    final signedIn = _previewShell
        ? _previewSignedIn
        : (backend.available ? backend.signedIn : _previewSignedIn);
    if (!signedIn) {
      return LoginPage(
        onSignedIn: () => setState(() => _previewSignedIn = true),
      );
    }
    // `?chat=<pane>`: open a pane's chat on the preview build. Without a
    // herdr connection the page shows its real error state; `?status=` fakes
    // the agent's state so the queue chip can be reviewed on a desk.
    final previewChat = previewParam('chat');
    final herdr = backend.herdr;
    if (previewChat != null && herdr != null) {
      return AgentChatPage(
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
      );
    }
    final sshNode = _sshNode;
    if (sshNode != null) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
        },
        child: TerminalPage(
          node: sshNode,
          user: _sshUser,
          port: _sshPort,
          ssh: _sshSession,
          demo: _sshDemo,
          onClose: () => setState(() {
            _sshNode = null;
            _sshSession = null;
          }),
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
    return Surface(
      color: SurfaceLevel.page.colorOf(scheme),
      child: Row(
        children: [
          AnimatedVisibility.sidebar(
            visible: !mobile,
            child: Surface(
              color: scheme.chromeSurface,
              shape: BorderDirectional(end: Divider.createBorderSide(context)),
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
    );
  }

  Widget _pages() {
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tabs,
      itemBuilder: (context, index) {
        return KeepScope(
          key: ValueKey(index),
          child: TickerMode(
            enabled: index == _tab,
            child: ExcludeFocus(
              excluding: index != _tab,
              child: _TabPage(
                controller: _pageController,
                position: index,
                fade: _animation == TabAnimation.fade,
                child: _pageAt(index),
              ),
            ),
          ),
        );
      },
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
          onToggleTheme: widget.theme.toggle,
        );
      default:
        final node = _node;
        if (node == null) {
          return NodesPage(
            onOpenNode: (value) => setState(() => _node = value),
            onToggleTheme: widget.theme.toggle,
          );
        }
        return NodeDetailPage(
          node: node,
          onBack: () => setState(() => _node = null),
          onOpenAgents: () => _toPage(2),
          onOpenSsh: () async {
            final choice = await showSshSheet(context, node);
            if (choice == null) return;
            setState(() {
              _sshUser = choice.user;
              _sshPort = choice.port;
              _sshSession = choice.session;
              _sshNode = node;
              _sshDemo = false;
            });
          },
        );
    }
  }
}

/// Keeps the page at rest while the controller slides, so a tab switch
/// cross-fades in place — FlClash's fade mode, minus the snapshotting.
class _TabPage extends StatelessWidget {
  const _TabPage({
    required this.controller,
    required this.position,
    required this.fade,
    required this.child,
  });

  final PageController controller;
  final int position;
  final bool fade;
  final Widget child;

  double get _offset {
    if (!controller.hasClients) return 0;
    final metrics = controller.position;
    if (!metrics.hasContentDimensions || metrics.viewportDimension == 0) {
      return 0;
    }
    final page = metrics.pixels / metrics.viewportDimension;
    return (position - page).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final delta = fade ? _offset : 0.0;
        return FractionalTranslation(
          translation: Offset(-delta, 0),
          child: Opacity(opacity: 1 - delta.abs(), child: child),
        );
      },
      child: child,
    );
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
