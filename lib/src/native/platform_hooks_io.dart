import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('taildeck/platform');

const _fallback =
    'Android platform hooks are unavailable; the node falls back to Go '
    'interfaces, which Android 11+ blocks (peer discovery may fail).';

Future<({String name, String? warning})> resolve() async {
  // Only Android needs the Java APIs; desktops keep Go's stdlib.
  if (!Platform.isAndroid) return (name: 'go', warning: null);
  try {
    final attached = await _channel.invokeMethod<bool>('init') ?? false;
    if (attached) return (name: 'host', warning: null);
    return (name: 'go', warning: _fallback);
  } on Object catch (error) {
    return (name: 'go', warning: '$_fallback ($error)');
  }
}
