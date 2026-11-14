import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'node_service.dart';

NodeService openNodeServicePlatform() => _AndroidNodeService();

/// Android only: the foreground service the app's Kotlin side owns.
class _AndroidNodeService implements NodeService {
  static const _channel = MethodChannel('taildeck/service');

  bool get _android => Platform.isAndroid;

  @override
  Future<void> start() => _send('start');

  @override
  Future<void> stop() => _send('stop');

  Future<void> _send(String method) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // A host without the Android side; the node runs without the service.
    } on PlatformException catch (error) {
      debugPrint('taildeck: service $method failed: ${error.message}');
    }
  }
}
