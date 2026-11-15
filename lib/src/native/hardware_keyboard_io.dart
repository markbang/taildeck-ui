import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('taildeck/keyboard');

/// Android's `Configuration.keyboard`; a desk has an obvious one, so this is
/// only asked where the answer changes the layout.
Future<bool?> attached() async {
  if (!Platform.isAndroid) return null;
  try {
    return await _channel.invokeMethod<bool>('attached');
  } on MissingPluginException {
    return null;
  } on PlatformException catch (error) {
    debugPrint('taildeck: keyboard query failed: ${error.message}');
    return null;
  }
}
