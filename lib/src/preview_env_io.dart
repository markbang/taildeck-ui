import 'dart:io';

import 'package:flutter/services.dart';

String? _launchQuery;

String? get queryOverride =>
    _launchQuery ?? Platform.environment['TAILDECK_QUERY'];

/// `adb shell am start -a android.intent.action.VIEW -d 'taildeck://preview/?node=devbox'`
/// is the only way to open a preview page on a device; other platforms have
/// no launch link.
Future<void> readLaunchQuery() async {
  if (!Platform.isAndroid) return;
  try {
    _launchQuery = await const MethodChannel('taildeck/link')
        .invokeMethod<String>('initialQuery');
  } on PlatformException {
    _launchQuery = null;
  } on MissingPluginException {
    _launchQuery = null;
  }
}
