import 'package:flutter/widgets.dart';

import 'web_page_stub.dart' if (dart.library.io) 'web_page_io.dart' as impl;
import 'web_page_types.dart';

export 'web_page_types.dart';

/// Android and iOS embed the page; desktop and web open the system browser.
bool get inAppWebViewSupported => impl.supported;

/// Builds the platform WebView, or null where [inAppWebViewSupported] is false.
WebPageController? createWebPageController({
  required String url,
  required WebPageEvents events,
  required Color background,
}) => impl.create(url: url, events: events, background: background);
