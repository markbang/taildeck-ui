import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'web_page_types.dart';

/// iOS and Android are the only platforms webview_flutter implements.
bool get supported => Platform.isAndroid || Platform.isIOS;

const _channel = MethodChannel('taildeck/webview');

Future<bool> useGatewayProxy(int port) async {
  if (!Platform.isAndroid || port <= 0) return false;
  try {
    return await _channel.invokeMethod<bool>('proxy', {'port': port}) ?? false;
  } on PlatformException catch (error) {
    debugPrint('taildeck: web view proxy: ${error.message}');
    return false;
  } on MissingPluginException {
    return false;
  }
}

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
    );
  unawaited(_load(view, url));
  return _PlatformWebPage(view);
}

/// The Kotlin app's WebView settings: media starts without a tap, http media
/// on https pages loads, and the UA drops "; wv", which some apps answer with
/// a stripped-down page.
Future<void> _load(WebViewController view, String url) async {
  final platform = view.platform;
  if (platform is AndroidWebViewController) {
    try {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setMixedContentMode(MixedContentMode.compatibilityMode);
      final agent = await view.getUserAgent();
      if (agent != null && agent.contains('; wv)')) {
        await view.setUserAgent(agent.replaceFirst('; wv)', ')'));
      }
    } on Object catch (error) {
      debugPrint('taildeck: web view settings: $error');
    }
  }
  await view.loadRequest(Uri.parse(url));
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
