import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import 'backend.dart';
import 'data.dart';
import 'glyphs.dart';
import 'l10n.dart';
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

  int _tab = (int.tryParse(Uri.base.queryParameters['tab'] ?? '') ?? 0).clamp(0, _tabs - 1);
  NodeItem? _node = _queryNode();
  bool _floating = Uri.base.queryParameters['nav'] != 'docked';
  TabAnimation _animation =
      Uri.base.queryParameters['anim'] == 'fade' ? TabAnimation.fade : TabAnimation.slide;
  bool _sidebarExpanded = true;
  // Mock/preview sign-in; the native backend reports its own state.
  bool _previewSignedIn = switch (Uri.base.queryParameters['login']) {
    null || '0' => true,
    _ => false,
  };
  NodeItem? _sshNode = _querySsh();
  String _sshUser = 'root';

  late final PageController _pageController = PageController(initialPage: _tab);

  static NodeItem? _querySsh() {
    final name = Uri.base.queryParameters['ssh'];
    if (name == null) return null;
    for (final node in [selfNode, ...peers]) {
      if (node.name == name) return node;
    }
    return null;
  }

  static NodeItem? _queryNode() {
    final name = Uri.base.queryParameters['node'];
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
    final signedIn = backend.available ? backend.signedIn : _previewSignedIn;
    if (!signedIn) {
      return LoginPage(
        onSignedIn: () => setState(() => _previewSignedIn = true),
      );
    }
    final sshNode = _sshNode;
    if (sshNode != null) {
      return TerminalPage(
        node: sshNode,
        user: _sshUser,
        onClose: () => setState(() => _sshNode = null),
      );
    }
    final l10n = AppLocalizations.of(context);
    final items = <({Glyph glyph, String label})>[
      (glyph: Glyphs2.nodes, label: l10n.tabNodes),
      (glyph: Glyphs2.grid, label: l10n.tabServices),
      (glyph: Glyphs2.agents, label: l10n.tabAgents),
      (glyph: Glyphs2.sliders, label: l10n.tabSettings),
    ];
    final dockInset = mobile && _floating ? NavigationDock.insetOf(context) : 0.0;
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
                onToggle: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
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
                            child: _pages(),
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
              _sshNode = node;
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
