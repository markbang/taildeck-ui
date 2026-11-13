import 'package:flutter/widgets.dart';

import 'web_page_types.dart';

/// Web has no platform WebView plugin.
bool get supported => false;

WebPageController? create({
  required String url,
  required WebPageEvents events,
  required Color background,
}) => null;
