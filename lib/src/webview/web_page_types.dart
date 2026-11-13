import 'package:flutter/widgets.dart';

/// What the page reports back while it loads.
class WebPageEvents {
  const WebPageEvents({
    required this.onProgress,
    required this.onCanGoBack,
    required this.onError,
  });

  /// 0–100, as the platform reports it.
  final ValueChanged<int> onProgress;
  final ValueChanged<bool> onCanGoBack;

  /// A main-frame load failure, with the platform's own description.
  final ValueChanged<String> onError;
}

/// An embedded page plus the actions the chrome offers. Android and iOS
/// implement this; every other platform has no WebView and never builds one.
abstract class WebPageController {
  Widget buildView();

  Future<void> reload();

  Future<void> goBack();
}
