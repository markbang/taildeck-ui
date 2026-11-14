import 'node_service.dart';

NodeService openNodeServicePlatform() => const _NoNodeService();

class _NoNodeService implements NodeService {
  const _NoNodeService();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
