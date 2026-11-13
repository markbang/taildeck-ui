import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../services.dart';
import '../widgets/foundation.dart';
import '../webview/web_page.dart';

/// A service's page inside the app, through the loopback gateway. Android and
/// iOS only: `service_open.dart` sends other platforms to the system browser.
class ServiceWebViewPage extends StatefulWidget {
  const ServiceWebViewPage({
    super.key,
    required this.service,
    required this.url,
  });

  final Service service;

  /// `http://<node>-<port>[s].localhost:<gateway>/<path>`
  final String url;

  static Route<void> route({required Service service, required String url}) =>
      HomeRoute<void>(
        builder: (_) => ServiceWebViewPage(service: service, url: url),
      );

  @override
  State<ServiceWebViewPage> createState() => _ServiceWebViewPageState();
}

class _ServiceWebViewPageState extends State<ServiceWebViewPage> {
  WebPageController? _page;
  bool _created = false;
  int _progress = 0;
  bool _canGoBack = false;
  String _error = '';
  String _notice = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_created) return;
    _created = true;
    final scheme = context.colorScheme;
    _page = createWebPageController(
      url: widget.url,
      background: scheme.surface,
      events: WebPageEvents(
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
        onCanGoBack: (value) {
          if (!mounted || value == _canGoBack) return;
          setState(() => _canGoBack = value);
        },
        onError: (message) {
          if (mounted) {
            setState(() {
              _error = message;
              _progress = 100;
            });
          }
        },
      ),
    );
  }

  void _reload() {
    setState(() {
      _error = '';
      _notice = '';
      _progress = 0;
    });
    unawaited(_page?.reload());
  }

  void _goBack() => unawaited(_page?.goBack());

  Future<void> _openExternal() async {
    final l10n = AppLocalizations.of(context);
    final opened = await launchUrl(
      Uri.parse(widget.url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() => _notice = l10n.serviceOpenFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final name = widget.service.name.isEmpty
        ? widget.service.address
        : widget.service.name;
    final page = _page;
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Surface(
        color: SurfaceLevel.page.colorOf(scheme),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const GlyphIcon(Glyphs.arrowBack),
                      tooltip: l10n.close,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.headline.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                          ),
                          Text(
                            widget.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFamily: 'DejaVuSansMono',
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (_canGoBack)
                      IconButton(
                        onPressed: _goBack,
                        icon: const GlyphIcon(Glyphs.chevronBack),
                        tooltip: l10n.back,
                      ),
                    IconButton(
                      onPressed: _reload,
                      icon: const GlyphIcon(Glyphs2.refresh),
                      tooltip: l10n.reload,
                    ),
                    IconButton(
                      onPressed: () => unawaited(_openExternal()),
                      icon: const GlyphIcon(Glyphs2.globe),
                      tooltip: l10n.openInBrowser,
                    ),
                  ],
                ),
              ),
              if (_progress < 100 && _error.isEmpty)
                LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 3,
                  backgroundColor: scheme.surfaceContainerHigh,
                ),
              if (_notice.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: InlineNotice(text: _notice),
                ),
              Expanded(
                child: page == null
                    ? _Fallback(onOpenExternal: _openExternal)
                    : _error.isNotEmpty
                    ? _LoadError(
                        detail: _error,
                        gatewayDown: BackendScope.of(context).gatewayPort <= 0,
                        onRetry: _reload,
                        onOpenExternal: _openExternal,
                      )
                    : ColoredBox(
                        color: scheme.surface,
                        child: page.buildView(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.detail,
    required this.gatewayDown,
    required this.onRetry,
    required this.onOpenExternal,
  });

  final String detail;
  final bool gatewayDown;
  final VoidCallback onRetry;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(Glyphs2.globe, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              l10n.webPageFailed,
              textAlign: TextAlign.center,
              style: AppTextStyle.title3.of(context),
            ),
            const SizedBox(height: 8),
            Text(
              gatewayDown ? l10n.serviceNeedsGateway : l10n.webPageFailedBody,
              textAlign: TextAlign.center,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'DejaVuSansMono',
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onOpenExternal,
              child: Text(l10n.openInBrowser),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reached only if a route was pushed where the platform has no WebView.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.onOpenExternal});

  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.inAppDesktopOnly,
              textAlign: TextAlign.center,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenExternal,
              child: Text(l10n.openInBrowser),
            ),
          ],
        ),
      ),
    );
  }
}
