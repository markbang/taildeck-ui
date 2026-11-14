import 'node_service_stub.dart' if (dart.library.io) 'node_service_io.dart';

/// Keeps the process alive around the Go node; a no-op away from Android.
abstract class NodeService {
  Future<void> start();
  Future<void> stop();
}

NodeService openNodeService() => openNodeServicePlatform();
