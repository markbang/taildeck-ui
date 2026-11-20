import 'node_service.dart';

NodeService openNodeServicePlatform() => const _NoNodeService();

class _NoNodeService implements NodeService {
  const _NoNodeService();

  @override
  Future<bool> start() async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<bool?> batteryExempt() async => null;

  @override
  Future<void> requestBatteryExempt() async {}
}
