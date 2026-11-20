import 'node_service_stub.dart' if (dart.library.io) 'node_service_io.dart';

/// Keeps the process alive around the Go node; a no-op away from Android.
abstract class NodeService {
  /// False when the OS refused, e.g. Android blocking a foreground service
  /// start from the background; the caller asks again later.
  Future<bool> start();
  Future<void> stop();

  /// Whether battery optimisation leaves the app alone; null off Android.
  Future<bool?> batteryExempt();

  /// Opens the system's battery optimisation prompt for this app.
  Future<void> requestBatteryExempt();
}

NodeService openNodeService() => openNodeServicePlatform();
