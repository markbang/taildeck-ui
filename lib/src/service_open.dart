import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backend.dart';
import 'pages/web_view.dart';
import 'services.dart';
import 'webview/web_page.dart';

enum ServiceOpen { inApp, browser, fallbackToBrowser, needsGateway, openFailed }

/// Opens [service] the way Settings asks: the in-app page on Android and iOS,
/// the system browser everywhere else. Callers turn the result into a notice.
Future<ServiceOpen> openService(BuildContext context, Service service) async {
  final backend = BackendScope.of(context);
  final url = gatewayUrl(service, backend.gatewayPort);
  if (backend.openInApp && inAppWebViewSupported) {
    if (url == null) return ServiceOpen.needsGateway;
    await Navigator.of(context)
        .push(ServiceWebViewPage.route(service: service, url: url));
    return ServiceOpen.inApp;
  }
  if (url == null) return ServiceOpen.needsGateway;
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!opened) return ServiceOpen.openFailed;
  return backend.openInApp
      ? ServiceOpen.fallbackToBrowser
      : ServiceOpen.browser;
}
