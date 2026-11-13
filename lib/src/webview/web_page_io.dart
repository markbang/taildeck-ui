import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'web_page_types.dart';

/// iOS and Android are the only platforms webview_flutter implements.
bool get supported => Platform.isAndroid || Platform.isIOS;

WebPageController? create({
  required String url,
  required WebPageEvents events,
  required Color background,
}) {
  if (!supported) return null;
  late final WebViewController view;
  view = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(background)
    ..setNavigationDelegate(
      NavigationDelegate(
        onProgress: events.onProgress,
        onPageFinished: (_) => _reportHistory(view, events),
        onUrlChange: (_) => _reportHistory(view, events),
        onWebResourceError: (error) {
          if (error.isForMainFrame ?? true) {
            events.onError(error.description);
          }
        },
      ),
    )
    ..loadRequest(Uri.parse(url));
  return _PlatformWebPage(view);
}

Future<void> _reportHistory(
  WebViewController view,
  WebPageEvents events,
) async {
  try {
    events.onCanGoBack(await view.canGoBack());
  } on Object catch (error) {
    debugPrint('taildeck: could not read the web history: $error');
  }
}

class _PlatformWebPage implements WebPageController {
  _PlatformWebPage(this._view);

  final WebViewController _view;

  @override
  Widget buildView() => WebViewWidget(controller: _view);

  @override
  Future<void> reload() => _view.reload();

  @override
  Future<void> goBack() => _view.goBack();
}
