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
  Future<bool> start() async {
    if (!_android) return true;
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException catch (error) {
      debugPrint('taildeck: service start failed: ${error.message}');
      return false;
    }
  }

  @override
  Future<void> stop() => _send<void>('stop');

  @override
  Future<bool?> batteryExempt() async =>
      _android ? await _send<bool>('batteryExempt') : null;

  @override
  Future<void> requestBatteryExempt() => _send<bool>('requestBatteryExempt');

  Future<T?> _send<T>(String method) async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      // A host without the Android side; the node runs without the service.
      return null;
    } on PlatformException catch (error) {
      debugPrint('taildeck: service $method failed: ${error.message}');
      return null;
    }
  }
}
