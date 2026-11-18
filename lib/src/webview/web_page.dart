import 'package:flutter/widgets.dart';

import 'web_page_stub.dart' if (dart.library.io) 'web_page_io.dart' as impl;
import 'web_page_types.dart';

export 'web_page_types.dart';

/// Android and iOS embed the page; desktop and web open the system browser.
bool get inAppWebViewSupported => impl.supported;

/// Points the app's WebViews at the gateway's forward proxy (Android only), so
/// a page can load from its tailnet URL. False when the WebView can't do it.
Future<bool> useGatewayProxy(int port) => impl.useGatewayProxy(port);

/// Drops the override [useGatewayProxy] set, once the service page closes.
Future<void> clearGatewayProxy() => impl.clearGatewayProxy();

/// Builds the platform WebView, or null where [inAppWebViewSupported] is false.
WebPageController? createWebPageController({
  required String url,
  required WebPageEvents events,
  required Color background,
}) => impl.create(url: url, events: events, background: background);
